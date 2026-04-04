"""End-to-end diagnostic: real Claude Vision on cannes_venue.jpg.

Validates:
  1. The analyzer produces rich, FLUX-ready scene JSON
  2. The full KPEG JSON after merging with metadata is sensible
  3. The FLUX prompt assembled from it makes sense
  4. No JSON redundancy, Brotli actually compresses

Invented App metadata (plausible for the Cannes photo):
  - Pixel 8 Pro, landscape
  - Cannes coords, afternoon timezone
  - One unknown person (the staff member visible)
  - NO indoor_place_id (as requested — see how the pipeline handles it)
"""
import json
from unittest.mock import patch
from pathlib import Path
from PIL import Image

from kpeg.encoder import encode, _build_full_json, _normalize_known_people
from kpeg.scene_analyzer import analyze_scene, _build_system_prompt
from kpeg.compression import compress_json, decompress_json
from kpeg.format import unpack_kpeg
from kpeg.bitmap import unpack_bitmap
from kpeg.image_generator import build_prompt, build_person_prompt
from kpeg.library_reader import format_objects_catalog_for_prompt


def main():
    img_path = Path("sample_photos/cannes_venue.jpg")
    img = Image.open(img_path)
    print(f"=== INPUT ===")
    print(f"Image: {img_path} ({img.size[0]}x{img.size[1]}, {img_path.stat().st_size} bytes JPEG)")

    # ═══ INVENTED App metadata (plausible, with indoor_place_id missing) ═══
    metadata = {
        "orientation": "landscape",
        "timestamp": 1743724800,                  # 2026-04-04 00:00 UTC
        "timezone": "Europe/Paris",
        "device_model": "Pixel 8 Pro",
        "is_outdoor": False,
        "lens_info": {"focal_length_mm": 6.9, "aperture": 1.8, "zoom_level": 1.0},
        "flash_used": False,
        "lat": 43.5528,
        "lng": 7.0174,
        "compass_heading": 145.0,
        "camera_tilt": 0.0,
        "people": [
            {"user_id": "unknown_0", "bbox": [0.47, 0.03, 0.62, 0.90]},
        ],
        "scene_hint": "venue setup",
        "tags": ["ethglobal", "cannes", "venue"],
        # indoor_place_id intentionally MISSING
        "session_id": "sess_20260404_1800",
    }
    print()
    print(f"=== APP METADATA (invented) ===")
    print(json.dumps(metadata, indent=2))

    # Realistic objects library (matches what would be populated in production)
    objects_catalog = [
        {"id": "obj_bistro_chair_blk", "name": "Black bistro chair", "category": "furniture"},
        {"id": "obj_deck_chair_wood", "name": "Wooden deck chair", "category": "furniture"},
        {"id": "obj_service_cart_gsf", "name": "GSF service cart", "category": "equipment"},
        {"id": "obj_palm_tropical", "name": "Tropical palm plant", "category": "decor"},
        {"id": "obj_banana_plant", "name": "Banana leaf plant", "category": "decor"},
        {"id": "obj_olive_potted", "name": "Potted olive tree", "category": "decor"},
        {"id": "obj_table_linen_blk", "name": "Black-skirted table", "category": "furniture"},
        {"id": "obj_fire_ext_red", "name": "Red fire extinguisher", "category": "equipment"},
        {"id": "obj_wicker_chair", "name": "Wicker lounge chair", "category": "furniture"},
    ]

    # ═══ Show Claude's system prompt ═══
    known_people = _normalize_known_people(metadata["people"])
    catalog_text = format_objects_catalog_for_prompt(objects_catalog)
    system_prompt = _build_system_prompt(catalog_text, known_people)
    print()
    print("=== CLAUDE VISION SYSTEM PROMPT ===")
    print(system_prompt)
    print()
    print(f"(System prompt: {len(system_prompt)} chars)")

    # ═══ REAL Claude Vision call ═══
    print()
    print("=== CALLING CLAUDE VISION (real API)... ===")
    scene = analyze_scene(img, known_people=known_people, objects_catalog=objects_catalog)

    print()
    print("=== ANALYZER OUTPUT (scene JSON from Claude) ===")
    print(json.dumps(scene, indent=2, ensure_ascii=False))

    # Measure raw scene JSON
    scene_raw = json.dumps(scene, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    print(f"\nScene JSON size: {len(scene_raw)} bytes (raw)")

    # ═══ Compose FULL KPEG JSON (scene + metadata + place_refs) ═══
    full_json = _build_full_json(scene, metadata, place_refs=[])
    print()
    print("=== FULL KPEG JSON (scene + metadata merged) ===")
    print(json.dumps(full_json, indent=2, ensure_ascii=False))

    full_raw = json.dumps(full_json, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    full_compressed = compress_json(full_json)
    print(f"\nFull JSON raw:        {len(full_raw)} bytes")
    print(f"Full JSON compressed: {len(full_compressed)} bytes (Brotli Q11)")
    print(f"Compression ratio:    {len(full_compressed) / len(full_raw):.1%}")

    # ═══ Test round trip: decompress and verify ═══
    decompressed = decompress_json(full_compressed)
    assert decompressed == full_json, "Round-trip failed!"
    print(f"\nRound-trip OK (decompressed JSON == original)")

    # ═══ Now do FULL encode and show FLUX prompt ═══
    print()
    print("=== RUNNING FULL ENCODER (scene_override from above)... ===")
    with patch("kpeg.encoder.get_objects_catalog", return_value=objects_catalog), \
         patch("kpeg.encoder.select_best_place_refs", return_value=[]), \
         patch("kpeg.encoder.get_person_name", return_value=None):
        kpeg_bytes = encode(img, metadata, scene_override=scene, verbose=True)

    # Parse what went into the .kpeg
    parsed = unpack_kpeg(kpeg_bytes)
    stored_scene = decompress_json(parsed.compressed_json)
    palette, grid, keypoints = unpack_bitmap(parsed.bitmap_data)

    print()
    print(f"=== .kpeg CONTENTS VERIFIED ===")
    print(f"Header magic+version+flags+sizes+aspect: 12B")
    print(f"Bitmap: {len(parsed.bitmap_data)}B ({len(keypoints)} keypoints, {grid.shape[0]}x{grid.shape[0]} grid)")
    print(f"JSON:   {len(parsed.compressed_json)}B compressed (stored, not duplicated)")
    print(f"CRC:    2B")
    print(f"Total:  {len(kpeg_bytes)}B")

    # ═══ FLUX PROMPT that would be sent for reconstruction ═══
    camera = stored_scene.get("c") or {}
    colors = stored_scene.get("colors") or []
    flux_prompt = build_prompt(stored_scene, camera=camera, colors=colors)
    person_prompt = build_person_prompt(stored_scene)

    print()
    print("=== FLUX POSITIVE PROMPT (Stage 1, sent to img2img) ===")
    print(flux_prompt)
    print()
    print(f"(Prompt: {len(flux_prompt)} chars)")
    if person_prompt:
        print()
        print("=== STAGE 2 PERSON DESCRIPTIONS (sent to Kontext for face preservation) ===")
        print(person_prompt)

    # Save .kpeg for inspection
    kpeg_out = Path("sample_photos/cannes_diag.kpeg")
    kpeg_out.write_bytes(kpeg_bytes)
    print()
    print(f"Saved: {kpeg_out} ({len(kpeg_bytes)} bytes)")


if __name__ == "__main__":
    main()
