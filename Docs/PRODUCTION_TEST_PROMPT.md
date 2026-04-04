# KPEG Production Test Plan — Android + Flask (WiFi)

> Prompt for Jose's Claude Code agent. Paste into Cloud Code to start the production smoke test.

You are helping run the PRODUCTION smoke test for KPEG, our 1-2KB image format for ETHGlobal Cannes. My teammate German has already validated the engine and the Flask HTTP stack locally (Flask `test_client` + real Claude Vision + real FLUX). Your job is to validate the REAL device-to-server-to-AI round trip.

## Architecture reminder

- Flutter Android app (`AndroidApp/kpeg_app/`) running on a physical Pixel/Samsung device
- Flask backend (`API/api.py`) running on my dev machine at `0.0.0.0:8000`
- Both on the SAME WiFi network
- App connects via `AppConfig.apiBaseUrl` which MUST be the dev machine's LAN IP (NOT `localhost` / `10.0.2.2`)
- App is already built against the real API (`AppConfig.useMock = false`)
- Encoder uses ~1.5 KB bitmap + ~1 KB compressed JSON (hard max 2514 B total)

## Pre-flight checks (do these first)

1. `cd API && python3 api.py` → verify it prints `Running on http://0.0.0.0:8000`
2. From the dev machine: `curl http://localhost:8000/health` returns `{"status":"ok","version":"1.0.0"}`
3. Find the dev machine's LAN IP:
   - Linux/Mac: `ip a | grep inet` or `ifconfig`
   - Windows: `ipconfig` → look for IPv4 address on the WiFi adapter
4. Open port 8000 on the dev machine firewall:
   - Linux: `sudo ufw allow 8000/tcp`
   - Mac: System Preferences → Security → Firewall → allow Python
   - Windows: New inbound rule for TCP port 8000
5. From the phone's browser on the same WiFi: visit `http://<LAN_IP>:8000/health` → should return JSON. If not, firewall is still blocking.
6. Edit `AndroidApp/kpeg_app/lib/config/app_config.dart`:
   ```dart
   apiBaseUrl = "http://<LAN_IP>:8000"  // e.g. "http://192.168.1.42:8000"
   ```
7. Rebuild + install the app:
   ```bash
   cd AndroidApp/kpeg_app
   flutter build apk --release --split-per-abi
   adb install build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
   ```

## Test scenarios (run in order)

### T1 — Health check from the app
- Open the app
- Go to Gallery tab (triggers a backend load)
- **Expected:** no "network error" snackbar, app loads its empty state
- **If fail:** phone can't reach Flask → verify pre-flight #5 works from phone browser

### T2 — Register one Person (library population)
- Library tab → People → Add person
- Take 3 selfies from different angles (ML Kit should auto-detect → auto-crop)
- Name: "Test User 1" → Save
- **Expected:**
  - App shows the person with a face thumbnail
  - Server: `ls API/library/people/usr_*/` shows 3 JPEGs
  - `sqlite3 API/kpeg_library.db "SELECT user_id, name, selfie_count FROM people"` shows `selfie_count=3`
  - Phone DB has 3 face embeddings: `adb shell "run-as com.example.kpeg_app sqlite3 databases/kpeg.db 'SELECT COUNT(*) FROM face_embeddings'"`

### T3 — Register one Place
- Library tab → Places → Add place
- Name: "Cannes Venue Main Hall"
- Take 3 photos from different angles (app captures lat/lng/compass/tilt per photo)
- Save
- **Expected:**
  - `SELECT place_id, name FROM places` shows the row
  - `SELECT photo_id, lat, lng, compass, tilt FROM place_photos WHERE place_id=...` shows 3 rows with non-null sensor values (compass 0-360, tilt ±90)
  - Files in `API/library/places/place_<uuid>/`

### T4 — Register one Object
- Library tab → Objects → Add object
- Category: furniture, Name: "Black bistro chair", 2 photos, Save
- **Expected:** `SELECT object_id, name, category FROM objects` shows the row; files in `API/library/objects/obj_<uuid>/`

### T5 — Capture + Encode (the money shot)
- Capture tab → point camera at a scene with Test User 1 + the chair
- Tap shutter
- App should:
  a) Show photo with green/yellow/red face overlays (ML Kit)
  b) Auto-identify Test User 1 with GREEN confidence (>0.8 cosine similarity)
  c) Show "Indoor" toggle active, Place selector auto-suggesting Cannes Venue (GPS-based)
  d) Offer scene hint + tags inputs
- Select "Cannes Venue Main Hall"
- Scene hint: "test capture with user 1"
- Tags: `hackathon`, `test`
- Tap "Encode .kpeg"
- **Expected:**
  - 5-12 s loading (Claude Vision call)
  - Toast "Encoded! ~2100 bytes" (should be 1800-2500 B)
  - .kpeg appears in Gallery with thumbnail
  - Server log: `📦 Encoded: <id> (XXXX bytes)`
  - File exists: `ls API/library/_kpeg/*.kpeg`

### T6 — Decode at each quality tier
- Gallery → tap the .kpeg
- Quality `fast` → Decode → 3-8 s, reconstruction shown
- Quality `balanced` → 15-30 s, better fidelity
- Quality `high` → 30-60 s, best fidelity
- All succeed without network errors

### T7 — Verify the prompt quality
On the server:
```bash
cd Tooling && python -c "
from pathlib import Path
from kpeg.decoder import inspect
import json
kpeg = sorted(Path('../API/library/_kpeg').glob('*.kpeg'))[-1]
print(json.dumps(inspect(kpeg.read_bytes()), indent=2))
"
```
- **Expected:**
  - `scene.description` starts with SUBJECT + ACTION verb (e.g. "Man in blue shirt sitting on black bistro chair...")
  - `scene.objects >= 1` with `obj_<id>` refs
  - `flags.has_people: true`
  - `flags.has_library_refs: true` (critical: library matching worked!)
  - `size_bytes <= 2514`

### T8 — /update_people correction flow
- In Gallery, tap the .kpeg → "Correct people" / "Re-tag"
- If any face was tagged "Unknown", assign it to Test User 1
- **Expected:**
  - .kpeg updated in place
  - Server log shows `/update_people` call
  - Decoding again gives better reconstruction (library face used)

## Success criteria

All of T1-T8 pass. On failure, capture:
- App logcat: `adb logcat | grep -i kpeg`
- Flask stdout
- The .kpeg file
- Screenshot of app state

## Common production failures

| Symptom | Likely cause | Fix |
|---|---|---|
| "Connection refused" | Firewall blocks port 8000 | Open port in OS firewall |
| "Connection timed out" | Phone on different WiFi | Verify both on same SSID |
| Encode hangs >60 s | Claude API key invalid | Check `.env` `ANTHROPIC_API_KEY` |
| Decode returns 500 | FLUX key invalid / credits empty | Check `.env` `FAL_KEY` |
| Face not auto-tagged | Low-res selfies during registration | Re-register in better light |
| KPEG file >2514 B | JSON trim loop not activating | Check encoder logs |
| Faces in wrong position after decode | Bbox coords swapped | Verify `metadata.people[N].bbox` is `[x0,y0,x1,y1]` normalized 0-1 |
| Reconstruction nothing like original | Fast tier (Schnell) ignores color bitmap | Try `balanced` or `high` |

## What to hand back to German

1. Which T1-T8 passed / failed
2. The .kpeg file from T5
3. Reconstructions from T6 at all 3 qualities
4. JSON output from T7
5. Any logcat errors
6. LAN IP + phone model used
