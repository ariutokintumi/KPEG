"""Real reconstruction test: .kpeg -> FLUX Schnell via fal.ai.

Uses the cannes_diag.kpeg saved by diag_cannes.py. Costs ~$0.003 per call.
"""
from pathlib import Path
from kpeg.decoder import decode


def main():
    kpeg_path = Path("sample_photos/cannes_diag.kpeg")
    if not kpeg_path.exists():
        print(f"Missing {kpeg_path} — run diag_cannes.py first")
        return

    kpeg_bytes = kpeg_path.read_bytes()
    print(f"Loaded: {kpeg_path} ({len(kpeg_bytes)} bytes)")
    print("Calling FLUX Schnell via fal.ai (fast tier, no stage 2)...")
    print()

    jpeg_bytes = decode(
        kpeg_bytes,
        quality="fast",            # FLUX Schnell, Stage 1 only
        max_output_dim=1024,
        output_format="JPEG",
        output_quality=90,
        verbose=True,
    )

    out_path = Path("sample_photos/cannes_reconstructed.jpg")
    out_path.write_bytes(jpeg_bytes)
    print()
    print(f"Saved: {out_path} ({len(jpeg_bytes)} bytes)")


if __name__ == "__main__":
    main()
