"""Full KPEG decoder: .kpeg binary → reconstructed JPEG.

Pipeline:
  1. Unpack binary container (verify CRC, magic, version)
  2. Decompress JSON (Brotli)
  3. Unpack bitmap (palette + grid + keypoints)
  4. Render color guide image
  5. Resolve library refs → reference photo URLs:
       obj_xxx  → library/objects/{id}/*.jpg
       usr_xxx  → library/people/{id}/*.jpg
       place_id → library/places/{id}/*.jpg (best angle match)
  6. Build prompt + call FLUX (via image_generator)
  7. Encode output as JPEG bytes
"""
import base64
import io
import mimetypes
from pathlib import Path
from typing import Callable, Optional
from PIL import Image

from .format import unpack_kpeg, KPEGFile
from .compression import decompress_json
from .bitmap import unpack_bitmap, render_bitmap
from .image_generator import generate_image, stub_generate, build_prompt
from .library_reader import (
    get_object_photos,
    get_person_photos,
    select_best_place_refs,
)
from .config import FAL_KEY

# Cap reference images so we don't blow past FLUX's max per request
MAX_REFERENCE_IMAGES = 8
# Faces > places > objects when deciding what to keep under the cap
_REF_PRIORITY_PEOPLE = 0
_REF_PRIORITY_PLACES = 1
_REF_PRIORITY_OBJECTS = 2


def _file_path_to_data_url(file_path: str) -> Optional[str]:
    """Read a local image file and encode to data URL. Returns None if missing."""
    p = Path(file_path)
    if not p.exists() or not p.is_file():
        return None
    mime, _ = mimetypes.guess_type(str(p))
    mime = mime or "image/jpeg"
    try:
        data = p.read_bytes()
    except OSError:
        return None
    b64 = base64.standard_b64encode(data).decode("ascii")
    return f"data:{mime};base64,{b64}"


def _collect_reference_urls(scene: dict, metadata: dict) -> list[str]:
    """Walk the scene refs + place metadata to build the library reference list.

    Priority order (so people are kept first when truncating):
      1. usr_xxx (faces)
      2. place refs closest to camera angle
      3. obj_xxx (distinctive objects)
    """
    prioritized: list[tuple[int, str]] = []

    # People first — faces matter most for identity preservation
    for obj in scene.get("o") or []:
        ref = obj.get("ref", "")
        if ref.startswith("usr_"):
            for path in get_person_photos(ref)[:2]:  # up to 2 selfies per person
                url = _file_path_to_data_url(path)
                if url:
                    prioritized.append((_REF_PRIORITY_PEOPLE, url))

    # Places — pick angle-matched refs
    place_id = (scene.get("p") or {}).get("place")
    if place_id:
        place_refs = select_best_place_refs(
            place_id,
            target_compass=metadata.get("compass"),
            target_tilt=metadata.get("tilt"),
            max_refs=3,
        )
        for pr in place_refs:
            url = _file_path_to_data_url(pr["file_path"])
            if url:
                prioritized.append((_REF_PRIORITY_PLACES, url))

    # Objects last (distinctive items)
    seen_object_ids: set[str] = set()
    for obj in scene.get("o") or []:
        ref = obj.get("ref", "")
        if ref.startswith("obj_") and ref not in seen_object_ids:
            seen_object_ids.add(ref)
            photos = get_object_photos(ref)
            if photos:
                url = _file_path_to_data_url(photos[0])
                if url:
                    prioritized.append((_REF_PRIORITY_OBJECTS, url))

    # Sort by priority (stable), truncate
    prioritized.sort(key=lambda t: t[0])
    return [url for _, url in prioritized[:MAX_REFERENCE_IMAGES]]


def _compute_output_size(aspect_w: int, aspect_h: int, max_dim: int = 1024) -> tuple[int, int]:
    """Derive output (width, height) from aspect ratio, capped at max_dim per side."""
    if aspect_w >= aspect_h:
        return max_dim, max(1, int(max_dim * aspect_h / aspect_w))
    return max(1, int(max_dim * aspect_w / aspect_h)), max_dim


def _parse_kpeg(kpeg_bytes: bytes) -> tuple[KPEGFile, dict]:
    """Unpack container + decompress the JSON payload."""
    kpeg = unpack_kpeg(kpeg_bytes)
    scene = decompress_json(kpeg.compressed_json)
    return kpeg, scene


def decode(
    kpeg_bytes: bytes,
    quality: str = "balanced",
    max_output_dim: int = 1024,
    output_format: str = "JPEG",
    output_quality: int = 90,
    submit: Optional[Callable[[str, dict], dict]] = None,
    verbose: bool = False,
) -> bytes:
    """Reconstruct a photo from a .kpeg binary.

    Args:
        kpeg_bytes: Raw .kpeg file contents.
        quality: "fast" | "balanced" | "high" (tier routing in image_generator).
        max_output_dim: Max output width/height (pixels).
        output_format: "JPEG" or "PNG".
        output_quality: JPEG quality 1-100.
        submit: Injectable fal.ai call for testing / offline mode.
        verbose: Print pipeline breakdown.

    Returns:
        Reconstructed image as bytes (JPEG or PNG).
    """
    # 1-2. Unpack + decompress
    kpeg, scene = _parse_kpeg(kpeg_bytes)

    # 3. Unpack bitmap
    custom_palette, grid, keypoints = unpack_bitmap(kpeg.bitmap_data)

    # 4. Render color guide
    out_w, out_h = _compute_output_size(kpeg.aspect_w, kpeg.aspect_h, max_output_dim)
    guide_size = min(512, max(out_w, out_h))
    guide = render_bitmap(custom_palette, grid, keypoints, width=guide_size, height=guide_size)

    # 5. Resolve library refs
    metadata = scene.get("m") or {}
    reference_urls = _collect_reference_urls(scene, metadata)

    # 6. Generate via FLUX
    camera = scene.get("c") or {}
    colors = scene.get("colors") or []
    result_img = generate_image(
        scene=scene,
        guide_image=guide,
        reference_urls=reference_urls,
        quality=quality,
        width=out_w,
        height=out_h,
        camera=camera,
        colors=colors,
        submit=submit,
    )

    # 7. Encode output
    buf = io.BytesIO()
    if output_format.upper() == "JPEG":
        result_img.convert("RGB").save(buf, format="JPEG", quality=output_quality)
    else:
        result_img.save(buf, format=output_format)
    out_bytes = buf.getvalue()

    if verbose:
        prompt = build_prompt(scene, camera=camera, colors=colors)
        print(
            f"KPEG decoded: {len(kpeg_bytes)}B -> {len(out_bytes)}B {output_format}\n"
            f"  Quality:     {quality}\n"
            f"  Output:      {out_w}x{out_h}\n"
            f"  Keypoints:   {len(keypoints)}\n"
            f"  Objects:     {len(scene.get('o', []))}\n"
            f"  References:  {len(reference_urls)}\n"
            f"  Prompt head: {prompt[:120]!r}"
        )

    return out_bytes


def decode_to_image(kpeg_bytes: bytes, **kwargs) -> Image.Image:
    """Variant returning a PIL.Image instead of encoded bytes (test-friendly)."""
    jpeg_bytes = decode(kpeg_bytes, **kwargs)
    return Image.open(io.BytesIO(jpeg_bytes))


def inspect(kpeg_bytes: bytes) -> dict:
    """Return header + scene summary without generating an image. Used by CLI/API."""
    kpeg, scene = _parse_kpeg(kpeg_bytes)
    return {
        "size_bytes": len(kpeg_bytes),
        "version": kpeg.version,
        "flags": {
            "portrait": kpeg.is_portrait,
            "has_library_refs": kpeg.has_library_refs,
            "has_people": kpeg.has_people,
            "is_outdoor": kpeg.is_outdoor,
            "has_text": kpeg.has_text,
            "session_linked": kpeg.session_linked,
        },
        "aspect": f"{kpeg.aspect_w}:{kpeg.aspect_h}",
        "bitmap_bytes": len(kpeg.bitmap_data),
        "json_bytes": len(kpeg.compressed_json),
        "scene": {
            "objects": len(scene.get("o", [])),
            "texts": len(scene.get("t", [])),
            "has_place": "p" in scene,
            "description": (scene.get("s") or {}).get("d", "")[:100],
        },
    }
