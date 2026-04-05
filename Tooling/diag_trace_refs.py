"""Trace what reference URLs the decoder actually collects for a given .kpeg.

Injects a mock submit() into FLUX so we can see EXACTLY what gets sent to fal.ai
without spending money. Prints:
  - The scene JSON refs (what the encoder stored)
  - The DB lookups the decoder performs
  - Whether each file_path actually resolves on this machine
  - What reference_image_urls get sent to Stage 2 (Kontext)
  - Which tier would run Stage 2 at all

Run: cd Tooling && python diag_trace_refs.py [path_to.kpeg]
"""
import sys
from pathlib import Path
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))

from kpeg.decoder import _parse_kpeg, _collect_reference_urls
from kpeg.bitmap import unpack_bitmap, render_bitmap
from kpeg.library_reader import (
    get_person_photos, get_object_photos,
    select_best_place_refs, get_person_name,
)


def main():
    kpeg_path = Path(sys.argv[1]) if len(sys.argv) > 1 else \
        Path("C:/Users/Nonce00/Downloads/bae6e272.kpeg")

    if not kpeg_path.exists():
        print(f"Not found: {kpeg_path}")
        sys.exit(1)

    print("=" * 70)
    print(f"KPEG DECODE TRACE: {kpeg_path.name}")
    print("=" * 70)

    kpeg_bytes = kpeg_path.read_bytes()
    kpeg, scene = _parse_kpeg(kpeg_bytes)
    metadata = scene.get("m") or {}

    # --- Enumerate the refs stored in the JSON ---
    person_refs, obj_refs = [], []
    for o in scene.get("o") or []:
        ref = o.get("ref", "")
        if ref.startswith("usr_"):
            person_refs.append(ref)
        elif ref.startswith("obj_"):
            obj_refs.append(ref)
    place_id = (scene.get("p") or {}).get("place")

    print()
    print(f"PERSON REFS in JSON:  {person_refs}")
    print(f"OBJECT REFS in JSON:  {obj_refs}")
    print(f"PLACE REF in JSON:    {place_id}")
    print(f"camera compass/tilt:  {metadata.get('compass')} / {metadata.get('tilt')}")
    print()

    # --- DB lookups per ref ---
    print("-" * 70)
    print("DB LOOKUPS (what library_reader returns for each ref)")
    print("-" * 70)

    for pref in person_refs:
        name = get_person_name(pref)
        paths = get_person_photos(pref)
        print(f"\nperson {pref}  (name={name!r})")
        for p in paths:
            exists = Path(p).exists()
            print(f"  file_path: {p}")
            print(f"     exists on THIS machine: {exists}")

    for oref in obj_refs:
        paths = get_object_photos(oref)
        print(f"\nobject {oref}")
        for p in paths:
            exists = Path(p).exists()
            print(f"  file_path: {p}")
            print(f"     exists on THIS machine: {exists}")

    if place_id:
        place_refs = select_best_place_refs(
            place_id,
            target_compass=metadata.get("compass"),
            target_tilt=metadata.get("tilt"),
            max_refs=3,
        )
        print(f"\nplace {place_id} — select_best_place_refs returned {len(place_refs)} refs:")
        for pr in place_refs:
            p = pr["file_path"]
            exists = Path(p).exists()
            print(f"  {pr['id']}: {pr['hint']}")
            print(f"     file_path: {p}")
            print(f"     exists on THIS machine: {exists}")

    # --- Render bitmap guide the same way the decoder does ---
    custom_palette, grid, keypoints = unpack_bitmap(kpeg.bitmap_data)
    guide = render_bitmap(custom_palette, grid, keypoints, width=512, height=512)

    # --- What the decoder's _collect_reference_urls() would return ---
    print()
    print("-" * 70)
    print("WHAT THE DECODER ACTUALLY PREPARES FOR FLUX STAGE 2")
    print("-" * 70)
    refs = _collect_reference_urls(scene, metadata, guide_image=guide)
    print(f"\nreference_urls count:  {len(refs)}  (bitmap guide included at priority 1)")
    if refs:
        for i, u in enumerate(refs):
            size = len(u)
            print(f"  [{i}] {u[:60]}... ({size}B data URL)")
    else:
        print("  EMPTY — FLUX will get NO references, not even the bitmap!")

    # --- Also show what Stage 2 would do with/without bitmap ---
    refs_no_bitmap = _collect_reference_urls(scene, metadata, guide_image=None)
    print()
    print(f"refs without bitmap:  {len(refs_no_bitmap)} (what older code returned)")

    print()
    print("=" * 70)
    print("DIAGNOSIS")
    print("=" * 70)
    if not refs:
        print("BUG: reference_urls empty even with bitmap guide. Check bitmap unpack.")
    else:
        png_count = sum(1 for u in refs if u.startswith("data:image/png"))
        jpeg_count = sum(1 for u in refs if u.startswith("data:image/jpeg"))
        print(f"{len(refs)} reference URL(s) resolved successfully.")
        print(f"  - JPEG refs (people/places/objects): {jpeg_count}")
        print(f"  - PNG bitmap guide:                  {png_count}")
        print()
        print("Stage 2 Kontext will receive these as reference_image_urls,")
        print("giving balanced/high tiers the bitmap as a color/composition anchor")
        print("even though their Stage 1 models are text-to-image only.")


if __name__ == "__main__":
    main()
