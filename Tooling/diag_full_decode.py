"""Full decode diagnostic: JSON + bitmap + reconstructed image.

Loads cannes_diag.kpeg and produces:
  1. Decompressed JSON (pretty-printed to console)
  2. Bitmap rendered as PNG (the color-guide passed to FLUX)
  3. Real FLUX Schnell reconstruction at 1024px longest side, JPEG Q95

The library is EMPTY — no reference photos exist yet, so FLUX has only:
  - The text prompt (built from the JSON, subject-first with action verbs)
  - The color-bitmap guide (not used on `fast` tier — t2i only)
Expect some hallucinations.
"""
import json
from pathlib import Path

from kpeg.format import unpack_kpeg
from kpeg.compression import decompress_json
from kpeg.bitmap import unpack_bitmap, render_bitmap
from kpeg.image_generator import build_prompt, build_person_prompt
from kpeg.decoder import decode


def main():
    kpeg_path = Path("sample_photos/cannes_diag.kpeg")
    if not kpeg_path.exists():
        print(f"Missing {kpeg_path} - run diag_cannes.py first")
        return

    kpeg_bytes = kpeg_path.read_bytes()
    print(f"=== INPUT: {kpeg_path} ({len(kpeg_bytes)} bytes) ===")
    print()

    # ═══ 1. Unpack container ═══
    parsed = unpack_kpeg(kpeg_bytes)
    print(f"=== KPEG CONTAINER ===")
    print(f"  Magic+Ver+Flags+Sizes+Aspect header: 12B")
    print(f"  Bitmap section:                      {len(parsed.bitmap_data)}B")
    print(f"  Compressed JSON:                     {len(parsed.compressed_json)}B (Brotli Q11)")
    print(f"  CRC-16:                              2B")
    print(f"  Total:                               {len(kpeg_bytes)}B  (~1-2 KB target, hard max 2514B)")
    print()

    # ═══ 2. Decompress JSON (Brotli) ═══
    scene = decompress_json(parsed.compressed_json)
    print(f"=== DECOMPRESSED JSON (what FLUX receives) ===")
    print(json.dumps(scene, indent=2, ensure_ascii=False))
    print()

    # Raw size (for redundancy check)
    raw_json = json.dumps(scene, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    print(f"  Raw JSON:        {len(raw_json)}B")
    print(f"  Brotli-compressed: {len(parsed.compressed_json)}B")
    print(f"  Compression:     {len(parsed.compressed_json)/len(raw_json):.1%}")
    print()

    # ═══ 3. Unpack + render bitmap ═══
    palette, grid, keypoints = unpack_bitmap(parsed.bitmap_data)
    print(f"=== BITMAP ===")
    print(f"  Custom palette:  16 colors (48B, from k-means on original)")
    print(f"  Grid:            {grid.shape[0]}x{grid.shape[0]} ({grid.shape[0]**2}B, dominant color per cell)")
    print(f"  Keypoints:       {len(keypoints)} (3B each = {len(keypoints)*3}B)")
    print()

    # Render at 512x512 (matches what the decoder passes to FLUX)
    bitmap_img = render_bitmap(palette, grid, keypoints, width=512, height=512)
    bitmap_path = Path("sample_photos/cannes_bitmap.png")
    bitmap_img.save(bitmap_path, format="PNG")
    print(f"  Bitmap rendered to: {bitmap_path} (512x512 PNG)")
    print()

    # ═══ 4. FLUX prompt breakdown ═══
    camera = scene.get("c") or {}
    colors = scene.get("colors") or []
    flux_prompt = build_prompt(scene, camera=camera, colors=colors)
    person_prompt = build_person_prompt(scene)

    print(f"=== FLUX POSITIVE PROMPT ({len(flux_prompt)} chars) ===")
    print(flux_prompt)
    print()
    if person_prompt:
        print(f"=== PERSON PROMPT (Stage 2 only, skipped on fast tier) ===")
        print(person_prompt)
        print()

    # ═══ 5. Real FLUX reconstruction (fast tier, 1024px, JPEG Q95) ═══
    print("=== CALLING FLUX SCHNELL (real fal.ai)... ===")
    jpeg_bytes = decode(
        kpeg_bytes,
        quality="fast",
        max_output_dim=1024,
        output_format="JPEG",
        output_quality=95,     # best practical JPEG quality
        verbose=True,
    )
    print()

    out_path = Path("sample_photos/cannes_reconstructed.jpg")
    out_path.write_bytes(jpeg_bytes)
    print(f"Saved: {out_path} ({len(jpeg_bytes)} bytes)")


if __name__ == "__main__":
    main()
