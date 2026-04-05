# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**KPEG** is a ultra-compressed image format (~1-2KB) developed at the ETHGlobal Cannes Hackathon. A photo is encoded into a tiny `.kpeg` file containing a color bitmap, metadata, and an AI scene description. An AI later reconstructs a visually similar photo from that data. The pitch: "Your entire life's photo library fitting on a floppy disk."

**Team:** 2 people. Jose Maria builds the App + API integration + Hedera. German builds the KPEG engine (`Tooling/kpeg/`) — real AI encode (Claude Vision) and decode (FLUX).

**Privacy-first:** Face detection AND identification happen entirely on-device. No biometric data leaves the phone. Person selfies are sent to the server only for AI image reconstruction purposes.

**Language:** English for UI, Spanish for internal comments and documentation.

## Architecture

```
┌──────────────────────────────────────┐
│   Flutter App (Android)              │
│                                      │
│  - Camera capture                    │
│  - Metadata collection (sensors)     │
│  - Face detection (ML Kit)           │  ON-DEVICE
│  - Face identification (embeddings)  │  PRIVACY-FIRST
│  - Library: People, Places, Objects  │
│  - .kpeg local storage + thumbnails  │
│  - Gallery + decode viewer           │
│                                      │
│                                      │   ┌──────────────────────┐
│  Registration (selfies/photos) ─────────▶│  Backend (API/)       │
│                                      │◀──│  Python/Flask+SQLite  │
│  Encode/decode ─────────────────────────▶│  /health             │
│                                      │   │  /library/people/*   │
│                                      │   │  /library/places/*   │
│                                      │   │  /library/objects/*  │
│                                      │   │  /encode  (mockup*)  │
│                                      │   │  /decode  (mockup*)  │
│                                      │   └──────────────────────┘
│  * mockup: saves original, returns it as "reconstruction"
└──────────────────────────────────────┘
```

**All services on localhost** (same WiFi, hackathon).
**Face identification is 100% on-device** — embeddings stored in local SQLite, cosine similarity matching.
**Server receives selfies/photos only for reconstruction** — not for identification.
**Library data (People, Places, Objects)** lives on server + cached locally with thumbnails.

## Data Flow

### Encoding (photo → .kpeg)
1. User captures photo in the app
2. App collects metadata from sensors (GPS, compass, tilt, orientation, device model)
3. App runs **on-device face detection** (ML Kit) → gets bboxes
4. App runs **on-device face identification** (64x64 grayscale embeddings, cosine similarity) → matches against stored profiles
5. Auto-tags by confidence: >0.8 green, 0.5-0.8 yellow, <0.5 red ("Unknown")
6. User can correct/assign faces manually, select indoor place
7. App sends photo + metadata JSON to **`POST /encode`**
8. Backend: Claude Vision analyzes scene → palette + bitmap + compressed scene JSON → `.kpeg` ≤2.5KB
9. Backend registers on Hedera (File Service + HCS + NFT)
10. Returns JSON `{kpeg_base64, image_id, hedera}` to app
11. App saves `.kpeg` + local thumbnail to storage

### Decoding (.kpeg → reconstructed photo) — multi-pass pipeline
1. User taps a `.kpeg` file in the gallery (shows local thumbnail)
2. App sends it to **`POST /decode`** with quality param (fast/balanced/high)
3. Backend pipeline:
   - **Stage 1**: PuLID FLUX generates image WITH face identity embedded (all tiers when people detected). Fast uses 12 steps/id=0.85, balanced/high use 28 steps/id=0.95. Prompt includes explicit multi-person constraints to prevent face duplication.
   - **Stage 2** (balanced/high): Kontext refines scene with bitmap guide (color regions + edge boundaries explained in prompt), place refs, and object refs. Prompt explicitly describes what each reference type is.
   - **Stage 3** (high only): Clarity upscaler 2x
4. App displays the result

### Decode Quality Tiers
| Tier | Stage 1 | Stage 2 (Scene+Objects) | Stage 3 | Time |
|------|---------|------------------------|---------|------|
| fast | PuLID FLUX (12 steps, id=0.85) | skip | skip | 5-10s |
| balanced | PuLID FLUX (28 steps, id=0.95) | Kontext + bitmap/place/object refs | skip | 10-20s |
| high | PuLID FLUX (28 steps, id=0.95) | Kontext + bitmap/place/object refs | Clarity 2x | 20-40s |

## Repository Layout

```
KPEG/
├── AndroidApp/kpeg_app/       # Flutter app
│   ├── lib/
│   │   ├── main.dart          # MultiProvider + BottomNav (Capture, Gallery, Library)
│   │   ├── config/            # AppConfig (URLs, mock toggle) + Theme
│   │   ├── models/            # Person, Place, IndoorObject, KpegFile, CaptureMetadata, DetectedFace
│   │   ├── services/          # API, Database, Repos, Sensors, FaceDetection, FaceCrop
│   │   ├── providers/         # Capture, Gallery, People, Places, Objects
│   │   ├── screens/           # Capture, Gallery, Decode, Library, PersonDetail, PlaceDetail, ObjectDetail
│   │   └── widgets/           # FaceOverlay, MetadataForm, QualitySelector, KpegFileCard, etc.
│   ├── pubspec.yaml
│   └── android/
├── .env                       # API keys + Hedera credentials (gitignored)
├── API/                       # Python backend (Flask + SQLite)
│   ├── api.py                 # Flask app — all endpoints
│   ├── hedera_service.py      # Hedera SDK integration (File Service + HCS + HTS)
│   ├── database.py            # SQLite schema (kpeg_library.db) + CRUD helpers
│   ├── debug_decode.py        # Debug tool: simulates decode, saves prompts + refs to debug/
│   ├── requirements.txt       # flask, Pillow, hiero-sdk-python, anthropic, fal-client, etc.
│   └── library/               # Photo storage (gitignored)
├── Tooling/kpeg/              # KPEG engine (German's code)
│   ├── encoder.py             # Real encode: Claude Vision → palette + bitmap + scene JSON
│   ├── decoder.py             # Real decode: multi-pass FLUX pipeline
│   ├── image_generator.py     # FLUX stages: generate → scene refine → face-swap → upscale
│   ├── library_reader.py      # DB reader for resolving refs → file paths
│   ├── scene_analyzer.py      # Claude Vision scene analysis with place context
│   ├── format.py              # .kpeg binary format (pack/unpack)
│   ├── compression.py         # Brotli JSON compression
│   ├── bitmap.py              # Color bitmap encode/decode/render
│   ├── palette.py             # KMeans color palette extraction
│   └── config.py              # Paths, API keys, model selection
│       ├── people/{user_id}/  # Face crop selfies
│       ├── places/{place_id}/ # Place reference photos
│       ├── objects/{object_id}/ # Object reference photos
│       └── _originals/        # Original photos for encode/decode mockup
├── CONTEXT.md                 # Historical dev notes
├── ClaudeInfo/                # Project specs (local only, gitignored)
└── CLAUDE.md
```

## Common Commands

### Python Backend (from `API/`)
```bash
pip install -r requirements.txt                # Install dependencies
python3 api.py                                 # Start API on 0.0.0.0:8000
```

### Flutter App (from `AndroidApp/kpeg_app/`)
```bash
flutter run                                    # Run on emulator/device
flutter build apk --release --split-per-abi    # Build lightweight release APK
flutter test                                   # Run widget tests
flutter analyze                                # Lint/static analysis
flutter clean && flutter pub get               # Clean rebuild
```

## API Contracts

### Core Pipeline (real AI — Claude Vision + FLUX)

| Endpoint | Method | Request | Response | Status |
|----------|--------|---------|----------|--------|
| `/encode` | POST | multipart: `image` (JPEG) + `metadata` (JSON) | JSON: `{kpeg_base64, image_id, hedera}` | Real encode via `Tooling/kpeg/encoder.py` + Hedera |
| `/decode` | POST | multipart: `kpeg_file` + `quality` (fast/balanced/high) | Reconstructed JPEG | Real decode via `Tooling/kpeg/decoder.py` multi-pass |
| `/update_people` | POST | multipart: `kpeg_file` + `mapping` (JSON) | Updated .kpeg binary | Re-tag unknown persons without re-encoding |
| `/inspect` | POST | multipart: `kpeg_file` | JSON header + scene summary | Debug: inspect .kpeg contents |
| `/health` | GET | — | `{"status": "ok"}` | Implemented |

### People Library

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/library/people` | POST | Register person (user_id, name, selfies, selfie_timestamps) |
| `/library/people` | GET | List all people |
| `/library/people/{user_id}` | DELETE | Delete person |

### Places Library

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/library/places` | POST | Register place (place_id, name, photos, photos_metadata with per-photo coordinates/angle) |
| `/library/places` | GET | List all places |
| `/library/places/{place_id}` | DELETE | Delete place |

### Objects Library

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/library/objects` | POST | Register object (object_id, name, category, photos) |
| `/library/objects` | GET | List all objects |
| `/library/objects/{object_id}` | DELETE | Delete object |

### Photo Management (per-entity)

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/library/people/{user_id}/selfies` | GET | List selfies (count + indices) |
| `/library/people/{user_id}/selfie/{idx}` | GET | Serve selfie JPEG |
| `/library/people/{user_id}/selfies` | POST | Add more selfies (no max limit) |
| `/library/places/{place_id}/photos` | GET | List photos |
| `/library/places/{place_id}/photo/{idx}` | GET | Serve photo JPEG |
| `/library/places/{place_id}/photos` | POST | Add more photos (no max limit) |
| `/library/objects/{object_id}/photos` | GET | List photos |
| `/library/objects/{object_id}/photo/{idx}` | GET | Serve photo JPEG |
| `/library/objects/{object_id}/photos` | POST | Add more photos (no max limit) |

### Hedera

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/hedera/setup` | POST | Create HCS topic + NFT collection (once) |
| `/hedera/status` | GET | Current Hedera state (topic_id, nft_token_id) |
| `/hedera/info/{image_id}` | GET | Hedera metadata for an encoded image |

## Metadata JSON Structure

Sent as the `metadata` field in `/encode`:

```json
{
  "orientation": "portrait",
  "timestamp": 1743724800,
  "timezone": "Europe/Madrid",
  "device_model": "Pixel 8 Pro",
  "is_outdoor": false,

  "lens_info": {
    "focal_length_mm": 6.9,
    "aperture": 1.8,
    "zoom_level": 1.0
  },
  "flash_used": false,

  "lat": 40.4168,
  "lng": -3.7038,
  "compass_heading": 225.0,
  "camera_tilt": -5.0,

  "people": [
    {"user_id": "usr_maria_01", "bbox": [0.30, 0.10, 0.55, 0.90]},
    {"user_id": "unknown_0", "bbox": [0.05, 0.20, 0.25, 0.75]}
  ],

  "scene_hint": "team lunch",
  "tags": ["hackathon", "team"],

  "indoor_place_id": "place_venue_main_hall",
  "indoor_description": "near the window, 2nd floor",

  "session_id": "sess_20260404_1430"
}
```

- `lens_info` and `flash_used` are **always included** (mandatory)
- `people` includes ALL non-excluded faces; untagged faces appear as `"unknown_N"` (N = left-to-right index)
- All other null fields can be omitted
- `bbox` normalized 0.0-1.0, top-left origin
- `session_id` auto-generated, reused within 30-min windows
- `is_outdoor` defaults to `false` (hackathon = indoor focus)

## Face Detection + On-Device Identification (privacy-first)

### How It Works
1. ML Kit detects faces on-device (bounding boxes)
2. Each face cropped, resized to 64x64 grayscale → embedding (4096 bytes)
3. Embedding compared against stored profiles via cosine similarity
4. Auto-tags by confidence: >0.8 green, 0.5-0.8 yellow, <0.5 red ("Unknown")
5. User can manually correct/assign via bottom sheet picker
6. Untagged faces appear in the metadata as `"unknown_N"` (N = left-to-right index, 0-based). Only faces explicitly excluded by the user are omitted from the people array.
7. The people array in the metadata includes ALL non-excluded faces (both identified and unidentified)

### Hybrid Model
- **Identification: ON-DEVICE** — face embeddings in local SQLite, no network calls
- **Registration: LOCAL + SERVER** — embeddings stored locally for identification, selfies sent to server for reconstruction AI
- `POST /library/people/identify` is NOT used — identification is purely local

### Selfie Registration Flow
1. User takes 2-5 selfies (different angles)
2. ML Kit detects face in each → auto-crops to face only
3. Face crops shown as preview (not full photos)
4. Embeddings extracted and stored in local `face_embeddings` table
5. Face crop files sent to server via `POST /library/people`
6. First face crop saved as local thumbnail

## Local Storage (SQLite)

| Table | Purpose | Key columns |
|-------|---------|-------------|
| `people` | Person profiles cache | user_id, name, selfie_count, thumbnail_path |
| `face_embeddings` | On-device face matching | person_id, embedding (BLOB, 4096 bytes) |
| `places` | Indoor places cache | place_id, name, lat, lng, thumbnail_path |
| `objects` | Indoor objects cache | object_id, name, category, thumbnail_path |
| `kpeg_files` | Encoded .kpeg files | filename, file_path, file_size_bytes, thumbnail_path, hedera_file_id, hedera_nft_token_id, hedera_nft_serial, hedera_network |

**Thumbnails** are local-only (120px, 60% JPEG quality). Never sent to the server. Used for:
- Gallery: preview of each .kpeg file
- Library People: face crop thumbnail
- Library Places: first photo thumbnail
- Library Objects: first photo thumbnail

## App Screens

### Bottom Navigation (3 tabs)
1. **Capture** — camera icon
2. **Gallery** — photo library icon
3. **Library** — library book icon (`local_library`)

### Capture Flow
- Take photo → ML Kit face detection → auto-identification → face overlay (green/yellow/red)
- Indoor/Outdoor segmented button (default: Indoor)
- When Indoor: place selector (searchable, nearby GPS), indoor description text field
- Scene hint + tags input
- "Encode .kpeg" button → encode → save with thumbnail

### Gallery
- List of .kpeg files with thumbnail, filename, size, date, scene hint
- Tap → Decode screen with quality selector (Fast/Balanced/High)
- Delete with confirmation

### Library (3 sub-tabs)
- **People**: face thumbnails, name, selfie count. Tap to view info + selfies from server. Add selfies (no max limit, auto face crop).
- **Places**: photo thumbnails, name. Tap to view info + photos from server. Add photos (no max limit).
- **Objects**: photo thumbnails, name, category. Tap to view info + photos from server. Add photos (no max limit).

## Critical Android Configuration

The `AndroidManifest.xml` must include:
- `flutterEmbedding=2` meta-data (required for Flutter 3.41.6)
- `CAMERA` and `INTERNET` permissions
- `ACCESS_FINE_LOCATION` and `ACCESS_COARSE_LOCATION` permissions
- `usesCleartextTraffic=true` (for local HTTP)
- `FileProvider` with `@xml/file_paths` (required by `image_picker`)

## Key Gotchas

- **Emulator networking:** Use `10.0.2.2` instead of `localhost` to reach the host machine
- **Physical device:** Same WiFi + firewall ports open (`sudo ufw allow <port>`)
- **IP changes:** Verify with `ip a` before building for physical device
- **Decode is slow:** 5-15 seconds for AI reconstruction — show loading state
- **Sensor timing:** Compass/tilt captured AT photo moment, not after
- **DB migrations:** Version bumps drop all tables — uninstall app on device when schema changes. Current DB version: **10**.
- **Thumbnails lost on reinstall:** Local thumbnails are lost when app is reinstalled. Library tiles fall back to server photos via `Image.network`. Photos are always persisted on the server.
- **API JSON field names:** Server returns `selfie_count` (people) and `photo_count` (places/objects) — not `count`. Flutter `fromApiJson()` factories must read `photo_count` to populate `photoCount` or the network thumbnail fallback won't trigger.
- **App connects to real API** — `AppConfig.useMock = false`. Backend must be running.
- **API URL config:** `AppConfig.apiBaseUrl` — use `10.0.2.2:8000` for emulator, PC's WiFi IP for physical device.
- **Encode/decode are REAL AI** — encode uses Claude Vision (scene analysis) + bitmap with edge map + Brotli compression. Decode uses PuLID FLUX (face identity in generation) → Kontext (scene/objects) → optional upscale.
- **Face identity via PuLID FLUX** — do NOT use `fal-ai/face-swap` (model removed/deprecated, gives 404). Use `fal-ai/flux-pulid` in Stage 1 to embed face identity DURING generation. Fast: 12 steps/id=0.85, balanced/high: 28 steps/id=0.95. `enable_safety_checker=False`. Multi-person: prompt explicitly says each person has a UNIQUE face and the reference face is ONLY for Person 1. Kontext Stage 2 must NOT modify faces.
- **Face tagging is manual** — auto-identification removed. All detected faces start as unknown (left→right order). User assigns each manually via bottom sheet picker. No max selfie/photo limits.
- **No face duplication** — `build_prompt()` adds explicit constraint: "There are exactly N DIFFERENT people. Each has a UNIQUE face — do NOT duplicate." PuLID prompt says reference face is only for Person 1.
- **Place photo selection is strict** — `select_best_place_refs()` picks 1 best match by compass/tilt angle, only adds more if within 30° of best. Photos with NULL compass get penalized (distance 999).
- **Bounding boxes in prompts** — `build_prompt()` translates bbox coordinates to spatial positions ("on the left", "center", "right top") for both people and objects.
- **Bitmap includes edge map** — 32x32 binary edge map (128 bytes, Sobel thresholded) appended after keypoints. Rendered as white overlay on color grid. Stage 2 prompt explains to FLUX: "colored regions = original color layout, white lines = object boundaries and edges." Backward compatible — old .kpeg files without edges still decode fine.
- **Debug decode** — `cd API && python3 debug_decode.py [kpeg_file]` simulates decode without calling AI, saves prompts, bitmap, edge map (as visible PNG), and all reference files per tier to `debug/`.
- **Debug encode** — each `/encode` call saves input image, metadata JSON, output .kpeg, extracted bitmap, edge map, and scene JSON to `API/debug/`.

## Hedera Integration (Blockchain)

**SDK:** `hiero-sdk-python` (Python). No Node.js — all backend is Python.
**Services used:** File Service + Consensus Service (HCS) + Token Service (HTS/NFT)
**Credentials:** `.env` at project root (gitignored). Needs `OPERATOR_ID`, `OPERATOR_KEY`, `NETWORK`.
**State:** `API/.hedera_state.json` persists topic_id + nft_token_id after first `POST /hedera/setup`.

### Hedera Flow (on each encode)
1. Upload .kpeg to **File Service** → `file_id`
2. Log `{user, image_id, file_id, timestamp}` to **HCS topic** → `topic_tx_id`
3. Mint **NFT** with metadata referencing the file → `nft_serial`
4. All three are best-effort — encode succeeds even if Hedera fails

### Key Files
- `API/hedera_service.py` — Hedera SDK wrapper (setup, create_file, log_message, mint_nft, register_image)
- `API/.hedera_state.json` — persisted topic_id + nft_token_id (gitignored)
- `.env` — Hedera credentials (gitignored)

### Hedera Gotchas
- `PrivateKey.from_string_ecdsa()` — use this for ECDSA keys, not `from_string()` (avoids ambiguity warning)
- `TokenId.from_string()` / `TopicId.from_string()` — SDK setters need typed objects, not raw strings
- `POST /hedera/setup` must be called once before encoding (creates HCS topic + NFT collection)
- Testnet accounts need HBAR — use faucet if `INSUFFICIENT_PAYER_BALANCE`

## Backend (API/)

**Stack:** Python + Flask + SQLite (`kpeg_library.db`) + `Tooling/kpeg/` engine

**Endpoints:** `/health`, `/encode`, `/decode`, `/update_people`, `/inspect`, `/library/*`, `/hedera/*`

**Dependencies:** `flask`, `Pillow>=10.0.0`, `numpy`, `brotli`, `anthropic`, `fal-client`, `scikit-learn`, `scipy`, `python-dotenv`, `hiero-sdk-python`

**DB tables:** `people`, `people_selfies`, `places`, `place_photos`, `objects`, `object_photos`, `hedera_metadata`

**Photo storage:** `library/people/{user_id}/`, `library/places/{place_id}/`, `library/objects/{object_id}/`, `library/_kpeg/` (persisted .kpeg files)

**API keys in `.env`:** `ANTHROPIC_API_KEY` (Claude Vision for encode), `FAL_KEY` (FLUX for decode), `OPERATOR_ID`/`OPERATOR_KEY` (Hedera)

**To run:** `cd API && python3 api.py` (listens on `0.0.0.0:8000`). Call `POST /hedera/setup` once to init blockchain.
