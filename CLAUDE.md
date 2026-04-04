# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**KPEG** is a ultra-compressed image format (~1-2KB) developed at the ETHGlobal Cannes Hackathon. A photo is encoded into a tiny `.kpeg` file containing a color bitmap, metadata, and an AI scene description. An AI later reconstructs a visually similar photo from that data. The pitch: "Your entire life's photo library fitting on a floppy disk."

**Team:** 2 people. This repo covers the **App** + **Library API backend** (Python/Flask). A teammate implements the `/encode` and `/decode` AI endpoints.

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
│  Registration (selfies/photos) ─────────▶│  Backend API         │
│                                      │◀──│  (teammate's server)  │
│  Encode/decode ─────────────────────────▶│  POST /encode        │
│                                      │   │  POST /decode        │
│                                      │   │  /library/people/*   │
│                                      │   │  /library/places/*   │
│                                      │   │  /library/objects/*  │
│                                      │   │  GET  /health        │
│                                      │   └──────────────────────┘
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
8. Backend returns `.kpeg` binary file (≤2KB)
9. App saves `.kpeg` + local thumbnail to storage

### Decoding (.kpeg → reconstructed photo)
1. User taps a `.kpeg` file in the gallery (shows local thumbnail)
2. App sends it to **`POST /decode`** with quality param (fast/balanced/high)
3. Backend returns reconstructed JPEG (takes 5-15 seconds)
4. App displays the result

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
├── API/                       # Python backend (Flask + SQLite)
│   ├── api.py                 # Flask app — /health + /library/* + /encode,/decode stubs
│   ├── database.py            # SQLite schema + CRUD helpers
│   ├── requirements.txt       # flask>=3.0.0
│   └── library/               # Photo storage (gitignored)
│       ├── people/{user_id}/  # Face crop selfies
│       ├── places/{place_id}/ # Place reference photos
│       └── objects/{object_id}/ # Object reference photos
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

### Core Pipeline (teammate's backend)

| Endpoint | Method | Request | Response |
|----------|--------|---------|----------|
| `/encode` | POST | multipart: `image` (JPEG) + `metadata` (JSON) | `.kpeg` binary (≤2KB) |
| `/decode` | POST | multipart: `kpeg_file` + `quality` | Reconstructed JPEG |
| `/health` | GET | — | `{"status": "ok"}` |

### People Library

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/library/people` | POST | Register person (user_id, name, 2-5 selfies, selfie_timestamps) |
| `/library/people` | GET | List all people |
| `/library/people/{user_id}` | DELETE | Delete person |

### Places Library

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/library/places` | POST | Register place (place_id, name, 2-5 photos, photos_metadata with per-photo coordinates/angle) |
| `/library/places` | GET | List all places |
| `/library/places/{place_id}` | DELETE | Delete place |

### Objects Library

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/library/objects` | POST | Register object (object_id, name, category, 1-3 photos) |
| `/library/objects` | GET | List all objects |
| `/library/objects/{object_id}` | DELETE | Delete object |

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
| `kpeg_files` | Encoded .kpeg files | filename, file_path, file_size_bytes, thumbnail_path |

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
- **People**: face thumbnails, name, selfie count. Add with 2-5 selfies (auto face crop).
- **Places**: photo thumbnails, name. Add with 2-5 photos + per-photo metadata (coordinates, camera angle).
- **Objects**: photo thumbnails, name, category. Add with 1-3 photos + category picker.

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
- **DB migrations:** Version bumps drop all tables — uninstall app on device when schema changes
- **Mock mode:** `AppConfig.useMock = true` for testing without backend. Set to `false` + update `apiBaseUrl` when backend is ready.
