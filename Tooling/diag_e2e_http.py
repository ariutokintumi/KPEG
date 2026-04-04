"""End-to-end HTTP test (no production server needed).

Uses Flask's test_client to exercise the REAL HTTP stack (multipart parsing,
response headers, byte flow) with REAL Claude Vision + REAL FLUX APIs.
This is what the Android app will hit — minus WiFi, firewall, and the phone itself.

Flow:
  1. Build a Flask test client pointed at API/api.py
  2. POST sample_photos/cannes_venue.jpg + metadata to /encode (HTTP multipart)
  3. Receive .kpeg binary (real Claude Vision was called, real bitmap built)
  4. POST the .kpeg back to /decode with quality=fast (HTTP multipart)
  5. Receive reconstructed JPEG (real FLUX Schnell was called)
  6. Save both outputs + print a flow summary

Cost per run: ~1 Claude Vision call + 1 FLUX Schnell call ≈ $0.01.

Run: cd Tooling && python diag_e2e_http.py
"""
import io
import json
import sys
import time
from pathlib import Path

# Force UTF-8 stdout so api.py's emoji print statements work on Windows consoles
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

# Make API/ importable from this Tooling script
REPO_ROOT = Path(__file__).resolve().parent.parent
API_DIR = REPO_ROOT / "API"
sys.path.insert(0, str(API_DIR))

import api as api_module  # noqa: E402
from database import init_db  # noqa: E402


def main():
    sample = REPO_ROOT / "Tooling" / "sample_photos" / "cannes_venue.jpg"
    if not sample.exists():
        print(f"Missing {sample}")
        sys.exit(1)

    # Ensure the DB exists (otherwise library_reader lookups fail)
    init_db()

    # Invented app metadata matching the CLAUDE.md schema
    metadata = {
        "orientation": "landscape",
        "timestamp": int(time.time()),
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
        "tags": ["ethglobal", "cannes", "e2e-http"],
        "session_id": f"sess_e2e_{int(time.time())}",
    }

    print("=" * 60)
    print("KPEG E2E HTTP TEST — Flask test_client + real AI APIs")
    print("=" * 60)
    print(f"Input photo: {sample.name} ({sample.stat().st_size} bytes)")
    print(f"Metadata: {len(json.dumps(metadata))} chars of JSON")
    print()

    api_module.app.config["TESTING"] = True
    client = api_module.app.test_client()

    # ─── 1) Health check ───────────────────────────────────────────────
    print("--- GET /health ---------------------------------------------")
    t0 = time.time()
    resp = client.get("/health")
    print(f"  Status:   {resp.status_code}")
    print(f"  Body:     {resp.get_json()}")
    print(f"  Latency:  {(time.time() - t0) * 1000:.0f} ms")
    assert resp.status_code == 200, "health check failed"
    print()

    # ─── 2) POST /encode (real Claude Vision under the hood) ───────────
    print("--- POST /encode (real Claude Vision call) -----------------")
    img_bytes = sample.read_bytes()
    t0 = time.time()
    resp = client.post("/encode", data={
        "image": (io.BytesIO(img_bytes), sample.name),
        "metadata": json.dumps(metadata),
    }, content_type="multipart/form-data")
    encode_ms = (time.time() - t0) * 1000
    print(f"  Status:   {resp.status_code}")
    print(f"  Headers:")
    for k in ("Content-Type", "X-KPEG-Id", "X-KPEG-Size"):
        if k in resp.headers:
            print(f"    {k}: {resp.headers[k]}")
    print(f"  Body:     {len(resp.data)} bytes (magic: {resp.data[:4]!r})")
    print(f"  Latency:  {encode_ms:.0f} ms")

    if resp.status_code != 200:
        print(f"  ERROR: {resp.get_json()}")
        sys.exit(1)

    kpeg_bytes = resp.data
    assert kpeg_bytes[:4] == b"KPEG", "response is not a KPEG file"
    assert len(kpeg_bytes) <= 2514, f"KPEG too big: {len(kpeg_bytes)} > 2514"

    # Save for inspection
    out_kpeg = REPO_ROOT / "Tooling" / "sample_photos" / "cannes_e2e.kpeg"
    out_kpeg.write_bytes(kpeg_bytes)
    print(f"  Saved:    {out_kpeg.relative_to(REPO_ROOT)}")
    print()

    # ─── 3) POST /decode (real FLUX Schnell) ───────────────────────────
    print("--- POST /decode quality=fast (real FLUX Schnell call) -----")
    t0 = time.time()
    resp = client.post("/decode", data={
        "kpeg_file": (io.BytesIO(kpeg_bytes), "cannes.kpeg"),
        "quality": "fast",
    }, content_type="multipart/form-data")
    decode_ms = (time.time() - t0) * 1000
    print(f"  Status:   {resp.status_code}")
    print(f"  Headers:  Content-Type: {resp.headers.get('Content-Type')}")
    print(f"  Body:     {len(resp.data)} bytes")
    print(f"  Latency:  {decode_ms:.0f} ms")

    if resp.status_code != 200:
        print(f"  ERROR: {resp.get_json()}")
        sys.exit(1)

    jpeg_bytes = resp.data
    assert jpeg_bytes[:3] == b"\xff\xd8\xff", "response is not a JPEG"

    out_jpeg = REPO_ROOT / "Tooling" / "sample_photos" / "cannes_e2e.jpg"
    out_jpeg.write_bytes(jpeg_bytes)
    print(f"  Saved:    {out_jpeg.relative_to(REPO_ROOT)}")
    print()

    # ─── 4) POST /inspect (verify the .kpeg is self-describing) ────────
    print("--- POST /inspect (sanity check the .kpeg) -----------------")
    t0 = time.time()
    resp = client.post("/inspect", data={
        "kpeg_file": (io.BytesIO(kpeg_bytes), "cannes.kpeg"),
    }, content_type="multipart/form-data")
    inspect_ms = (time.time() - t0) * 1000
    print(f"  Status:   {resp.status_code}")
    print(f"  Latency:  {inspect_ms:.0f} ms")
    if resp.status_code == 200:
        summary = resp.get_json()
        print(f"  Summary:  {json.dumps(summary, indent=2)[:500]}...")
    print()

    # ─── Done ──────────────────────────────────────────────────────────
    print("=" * 60)
    print("E2E HTTP TEST PASSED")
    print("=" * 60)
    print(f"  Original JPEG:   {sample.stat().st_size:>8} bytes")
    print(f"  KPEG binary:     {len(kpeg_bytes):>8} bytes "
          f"({100 * len(kpeg_bytes) / sample.stat().st_size:.2f}% of original)")
    print(f"  Reconstructed:   {len(jpeg_bytes):>8} bytes")
    print(f"  Compression:     {sample.stat().st_size // len(kpeg_bytes)}x")
    print()
    print(f"  /encode latency: {encode_ms:>6.0f} ms  (real Claude Vision)")
    print(f"  /decode latency: {decode_ms:>6.0f} ms  (real FLUX Schnell)")
    print(f"  /inspect latency:{inspect_ms:>6.0f} ms")
    print()
    print("The full Flask HTTP stack works end-to-end with real AI APIs.")
    print("Jose can now hand the Flutter app to any of these endpoints.")


if __name__ == "__main__":
    main()
