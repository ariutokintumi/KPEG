"""Full KPEG encoder with adaptive budget-fill loop.

Pipeline:
  1. Load image + extract custom palette (k-means 16)
  2. Generate 8x8 grid bitmap (minimal)
  3. Read Library: objects catalog + place refs by camera angle
  4. Call Claude Vision with image + people + catalog → scene JSON
  5. Compose full KPEG JSON (scene + App metadata + place_refs)
  6. Compress (Brotli Q11) and measure
  7. Budget-fill loop: add keypoints to approach target size
  8. Trim JSON if over max (rare safety path)
  9. Compute flags + aspect ratio
  10. Pack into KPEG binary container
"""
import io
from math import gcd
from pathlib import Path
from typing import Optional, Union
from PIL import Image

from .config import TARGET_SIZE, MAX_SIZE
from .palette import extract_custom_palette, build_full_palette
from .bitmap import (
    generate_grid,
    extract_keypoints,
    pack_bitmap,
    compute_bitmap_size,
    MAX_KEYPOINTS,
)
from .compression import compress_json
from .format import (
    pack_kpeg,
    compute_total_size,
    FLAG_PORTRAIT,
    FLAG_HAS_LIB_REFS,
    FLAG_HAS_PEOPLE,
    FLAG_IS_OUTDOOR,
    FLAG_HAS_TEXT,
    FLAG_SESSION_LINKED,
)
from .library_reader import (
    get_objects_catalog,
    select_best_place_refs,
    get_person_name,
)
from .scene_analyzer import analyze_scene

SAFETY_MARGIN = 40  # reserve a few bytes to absorb compression variance


def _load_image(image_input) -> Image.Image:
    """Accept PIL image, raw bytes, or file path."""
    if isinstance(image_input, Image.Image):
        return image_input
    if isinstance(image_input, (bytes, bytearray)):
        return Image.open(io.BytesIO(image_input))
    if isinstance(image_input, (str, Path)):
        return Image.open(image_input)
    raise TypeError(f"Unsupported image input type: {type(image_input)}")


def _normalize_known_people(app_people: list[dict]) -> list[dict]:
    """Convert App's people format to KPEG internal format.

    App sends:    {"user_id": "usr_xxx"|"unknown_N", "bbox": [...]}  (N is 0-indexed)
    KPEG stores:  {"ref": "usr_xxx"|"unknownN+1", "bbox": [...], "name": ...}
    """
    result = []
    for p in app_people:
        user_id = p.get("user_id", "")
        if user_id.startswith("unknown_"):
            try:
                idx = int(user_id.split("_", 1)[1]) + 1
                ref = f"unknown{idx}"
            except (ValueError, IndexError):
                ref = user_id
        else:
            ref = user_id
        entry = {"ref": ref, "bbox": p.get("bbox", [0, 0, 1, 1])}
        if ref.startswith("usr_"):
            name = get_person_name(ref)
            if name:
                entry["name"] = name
        result.append(entry)
    return result


def _build_full_json(scene: dict, metadata: dict, place_refs: list[dict]) -> dict:
    """Compose the raw JSON payload from Claude's scene + App metadata + library hints."""
    j = {"v": 1}
    # From Claude Vision
    if "s" in scene:
        j["s"] = scene["s"]
    if "o" in scene:
        j["o"] = scene["o"]
    if scene.get("t"):
        j["t"] = scene["t"]
    if scene.get("colors"):
        j["colors"] = scene["colors"]

    # Place section
    place_section = {}
    if metadata.get("indoor_place_id"):
        place_section["place"] = metadata["indoor_place_id"]
    if metadata.get("indoor_description"):
        place_section["indoor"] = metadata["indoor_description"]
    if place_refs:
        place_section["place_refs"] = [
            {"id": r["id"], "hint": r["hint"]} for r in place_refs
        ]
    if place_section:
        j["p"] = place_section

    # Metadata (sensor/camera capture context)
    m = {}
    if metadata.get("timestamp") is not None:
        m["ts"] = metadata["timestamp"]
    if metadata.get("timezone"):
        m["tz"] = metadata["timezone"]
    if metadata.get("lat") is not None and metadata.get("lng") is not None:
        m["loc"] = [metadata["lat"], metadata["lng"]]
    if metadata.get("compass_heading") is not None:
        m["compass"] = metadata["compass_heading"]
    if metadata.get("camera_tilt") is not None:
        m["tilt"] = metadata["camera_tilt"]
    if metadata.get("device_model"):
        m["dev"] = metadata["device_model"]
    if metadata.get("is_outdoor"):
        m["outdoor"] = True
    if m:
        j["m"] = m

    # Camera lens
    lens = metadata.get("lens_info") or {}
    c = {}
    if lens.get("focal_length_mm") is not None:
        c["fl"] = lens["focal_length_mm"]
    if lens.get("aperture") is not None:
        c["ap"] = lens["aperture"]
    if lens.get("zoom_level") is not None:
        c["zm"] = lens["zoom_level"]
    if metadata.get("flash_used"):
        c["flash"] = True
    if c:
        j["c"] = c

    # Optional hints
    if metadata.get("scene_hint"):
        j["hint"] = metadata["scene_hint"]
    if metadata.get("tags"):
        j["tags"] = metadata["tags"]
    if metadata.get("session_id"):
        j["sid"] = metadata["session_id"]

    return j


def _compute_flags(full_json: dict, image: Image.Image) -> int:
    """Derive the flags bitfield from final JSON + image orientation."""
    flags = 0
    w, h = image.size
    if h > w:
        flags |= FLAG_PORTRAIT

    # Any library-backed ref? (usr_*, obj_*, or place_refs)
    has_lib = False
    for obj in full_json.get("o", []):
        ref = obj.get("ref", "")
        if ref.startswith(("obj_", "usr_")):
            has_lib = True
            break
    if not has_lib and "place_refs" in full_json.get("p", {}):
        has_lib = True
    if has_lib:
        flags |= FLAG_HAS_LIB_REFS

    if any(o.get("n") == "person" for o in full_json.get("o", [])):
        flags |= FLAG_HAS_PEOPLE
    if full_json.get("m", {}).get("outdoor"):
        flags |= FLAG_IS_OUTDOOR
    if full_json.get("t"):
        flags |= FLAG_HAS_TEXT
    if full_json.get("sid"):
        flags |= FLAG_SESSION_LINKED

    return flags


# Common aspect ratios to snap to (saves bytes + matches display defaults)
_COMMON_RATIOS = [
    (4, 3), (3, 4), (16, 9), (9, 16), (1, 1),
    (3, 2), (2, 3), (16, 10), (10, 16), (5, 4), (4, 5),
]


def _compute_aspect_ratio(image: Image.Image) -> tuple[int, int]:
    """Snap to common ratio if within 2%, else reduce via GCD and cap at uint8."""
    w, h = image.size
    ratio = w / h
    for cw, ch in _COMMON_RATIOS:
        if abs(ratio - cw / ch) / (cw / ch) < 0.02:
            return cw, ch
    g = gcd(w, h)
    aw, ah = w // g, h // g
    while aw > 255 or ah > 255:
        aw = max(1, aw // 2)
        ah = max(1, ah // 2)
    return aw, ah


def _trim_json_if_needed(full_json: dict) -> dict:
    """Strip optional fields in decreasing priority when over budget."""
    # Order: tags → hint → m.dev → m.tz → c.zm → c.flash
    for field in ("tags", "hint"):
        if field in full_json:
            del full_json[field]
            return full_json
    for section, key in [("m", "dev"), ("m", "tz"), ("c", "zm"), ("c", "flash")]:
        if section in full_json and key in full_json[section]:
            del full_json[section][key]
            if not full_json[section]:
                del full_json[section]
            return full_json
    return full_json


def encode(
    image_input: Union[Image.Image, bytes, str, Path],
    metadata: dict,
    target_size: int = TARGET_SIZE,
    max_size: int = MAX_SIZE,
    verbose: bool = False,
    scene_override: Optional[dict] = None,
) -> bytes:
    """Encode a photo + metadata into a KPEG binary.

    Args:
        image_input: PIL.Image, bytes, or file path.
        metadata: App-provided dict (see CLAUDE.md metadata schema).
        target_size: Desired KPEG size (budget-fill aims for this, default 1950).
        max_size: Hard ceiling (default 2048).
        verbose: Print size breakdown to stdout.
        scene_override: Inject pre-analyzed scene JSON (for testing without Claude API).

    Returns:
        KPEG binary file as bytes.
    """
    image = _load_image(image_input)
    image_rgb = image.convert("RGB")

    # 1. Extract custom palette + standard grid
    custom_palette = extract_custom_palette(image_rgb, k=16)
    full_palette = build_full_palette(custom_palette)
    grid = generate_grid(image_rgb, full_palette, grid_size=8)

    # 2. Library-aware scene analysis
    known_people = _normalize_known_people(metadata.get("people", []))
    if scene_override is not None:
        scene = scene_override
    else:
        objects_catalog = get_objects_catalog(limit=100)
        scene = analyze_scene(image_rgb, known_people, objects_catalog)

    # 3. Select place_refs by camera angle
    place_refs = []
    if metadata.get("indoor_place_id"):
        place_refs = select_best_place_refs(
            metadata["indoor_place_id"],
            target_compass=metadata.get("compass_heading"),
            target_tilt=metadata.get("camera_tilt"),
            max_refs=3,
        )

    # 4. Compose full JSON
    full_json = _build_full_json(scene, metadata, place_refs)

    # 5. Initial compressed JSON
    compressed_json = compress_json(full_json)

    # 6. Trim JSON if JSON alone blows the budget
    while compute_total_size(114, len(compressed_json)) > max_size:
        before = full_json.copy()
        full_json = _trim_json_if_needed(full_json)
        if full_json == before:
            break  # nothing left to trim
        compressed_json = compress_json(full_json)

    # 7. Budget-fill loop: add keypoints to use remaining space
    bitmap_data = pack_bitmap(custom_palette, grid, keypoints=[])
    total = compute_total_size(len(bitmap_data), len(compressed_json))
    keypoints = []

    if total < target_size:
        budget_bytes = max(0, target_size - total - SAFETY_MARGIN)
        kp_count = min(budget_bytes // 3, MAX_KEYPOINTS)
        if kp_count > 0:
            keypoints = extract_keypoints(image_rgb, full_palette, max_count=kp_count)
            bitmap_data = pack_bitmap(custom_palette, grid, keypoints)
            total = compute_total_size(len(bitmap_data), len(compressed_json))

    # 8. Drop keypoints if we overshot max (shouldn't happen with safety margin)
    while total > max_size and keypoints:
        keypoints = keypoints[:-max(1, len(keypoints) // 10)]
        bitmap_data = pack_bitmap(custom_palette, grid, keypoints)
        total = compute_total_size(len(bitmap_data), len(compressed_json))

    # 9. Flags + aspect ratio
    flags = _compute_flags(full_json, image_rgb)
    aspect_w, aspect_h = _compute_aspect_ratio(image_rgb)

    # 10. Pack
    kpeg_bytes = pack_kpeg(
        bitmap_data=bitmap_data,
        compressed_json=compressed_json,
        flags=flags,
        aspect_w=aspect_w,
        aspect_h=aspect_h,
    )

    if verbose:
        print(
            f"KPEG encoded: {len(kpeg_bytes)}B / {max_size}B "
            f"(target {target_size}B)\n"
            f"  Header:    12B\n"
            f"  Bitmap:    {len(bitmap_data)}B (grid 8x8 + {len(keypoints)} keypoints)\n"
            f"  JSON:      {len(compressed_json)}B compressed\n"
            f"  CRC:       2B\n"
            f"  Flags:     0x{flags:02X}\n"
            f"  Aspect:    {aspect_w}:{aspect_h}\n"
            f"  Objects:   {len(full_json.get('o', []))}\n"
            f"  Texts:     {len(full_json.get('t', []))}\n"
            f"  PlaceRefs: {len(place_refs)}"
        )

    return kpeg_bytes
