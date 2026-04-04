# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**KPEG** is a ultra-compressed image format (~1-2KB) developed at the ETHGlobal Cannes Hackathon. A photo is encoded into a tiny `.kpeg` file containing a color bitmap, metadata, and an AI scene description. An AI later reconstructs a visually similar photo from that data. The pitch: "Your entire life's photo library fitting on a floppy disk."

**Team:** 2 people. This repo covers the **App** (with on-device face recognition). A teammate builds the encode/decode backend separately.

**Privacy-first:** Face detection, recognition, and person profiles stay entirely on-device. No biometric data ever leaves the phone. This is a key selling point for the pitch.

**Language:** Spanish for UI strings, comments, and documentation.

## Architecture

```
┌──────────────────────────────────┐
│   Flutter App (Android)          │
│                                  │
│  - Camera capture                │
│  - Metadata collection (sensors) │
│  - Face detection (ML Kit)       │  ON-DEVICE
│  - Face recognition (ML Kit)     │  (privacy-first)
│  - Person profiles (SQLite)      │
│  - .kpeg local storage           │
│  - Gallery + decode viewer       │
│                                  │
│                                  │     ┌──────────────────────┐
│                                  │────▶│  Encode/Decode API   │
│                                  │◀────│  (teammate's backend) │
│                                  │     │  POST /encode        │
│                                  │     │  POST /decode        │
│                                  │     │  GET  /health        │
│                                  │     └──────────────────────┘
└──────────────────────────────────┘
```

**Encode/Decode API runs on localhost** (same WiFi, hackathon presencial).
**Face recognition is 100% on-device** — no server needed, no biometric data transmitted.

## Data Flow

### Encoding (photo → .kpeg)
1. User captures photo in the app
2. App collects metadata from sensors (GPS, compass, tilt, orientation, device model, etc.)
3. App runs **on-device face detection/recognition** (Google ML Kit) → gets bboxes + matched user_ids from local SQLite
4. App sends photo (multipart) + metadata JSON to **`POST /encode`**
5. Backend returns `.kpeg` binary file (≤2KB)
6. App saves `.kpeg` to local storage

### Decoding (.kpeg → reconstructed photo)
1. User taps a `.kpeg` file in the gallery
2. App sends it to **`POST /decode`** with quality param (fast/balanced/high)
3. Backend returns reconstructed JPEG (takes 5-15 seconds)
4. App displays the result

## Repository Layout

```
KPEG/
├── AndroidApp/kpeg_app/     # Flutter app
│   ├── lib/                 # Dart source code
│   ├── pubspec.yaml         # Flutter dependencies
│   └── android/             # Android config (manifest, gradle)
├── API/                     # Legacy/utilities (may be repurposed or removed)
├── CONTEXT.md               # Historical dev notes and solved problems
├── ClaudeInfo/              # Project specs and reference images (local only, gitignored)
└── CLAUDE.md                # This file
```

## Common Commands

### Flutter App (from `AndroidApp/kpeg_app/`)
```bash
flutter run                                    # Run on emulator/device
flutter build apk --release --split-per-abi    # Build lightweight release APK
flutter test                                   # Run widget tests
flutter analyze                                # Lint/static analysis
flutter clean && flutter pub get               # Clean rebuild
```


## Encode/Decode API Contract (teammate's backend)

### POST /encode
- **Content-Type:** multipart/form-data
- **Fields:**
  - `image` — JPEG file (max 10MB)
  - `metadata` — JSON string (see below)
- **Response:** `200 OK`, `application/octet-stream` — raw .kpeg binary (≤2KB)
- **Error:** `422`, JSON `{"error": "description"}`

### POST /decode
- **Content-Type:** multipart/form-data
- **Fields:**
  - `kpeg_file` — .kpeg binary
  - `quality` — `"fast"`, `"balanced"`, or `"high"` (default: `"balanced"`)
- **Response:** `200 OK`, `image/jpeg` — reconstructed image

### GET /health
- Health check endpoint

## Metadata JSON Structure

Sent as the `metadata` field in `/encode`:

```json
{
  "orientation": "landscape",              // REQUIRED: from camera sensor
  "timestamp": 1743724800,                 // REQUIRED: Unix epoch seconds
  "timezone": "Europe/Madrid",             // REQUIRED: IANA timezone
  "device_model": "Pixel 8 Pro",           // REQUIRED: Build.MODEL
  "is_outdoor": true,                      // REQUIRED: user toggle in UI

  "lat": 40.4168,                          // LOCATION (if permission granted)
  "lng": -3.7038,
  "altitude": 650.0,
  "compass_heading": 225.0,               // 0-360, 0=North, from SensorManager
  "camera_tilt": -5.0,                    // -90 to 90, 0=horizontal

  "people": [                              // PEOPLE (on-device ML Kit + local DB)
    {"user_id": "usr_maria_01", "bbox": [0.3, 0.1, 0.55, 0.9]}
  ],

  "lens_info": {                           // CAMERA (from EXIF)
    "focal_length_mm": 6.9,
    "aperture": 1.8,
    "zoom_level": 1.0
  },
  "flash_used": false,

  "scene_hint": "lunch at Plaza Mayor",    // USER CONTEXT (optional)
  "tags": ["madrid", "friends"],

  "indoor_place_id": null,                 // Only if is_outdoor=false
  "indoor_description": null               // Free text if indoor
}
```

- All `null` fields can be omitted — API handles missing data
- `bbox` coordinates are normalized 0.0–1.0 (not pixels), relative to image dimensions, top-left origin
- Capture sensor data AT the moment of photo capture (compass/tilt change fast)

## On-Device Face Recognition (privacy-first)

All face processing happens locally on the phone. No biometric data is ever sent to any server.

### Technology Stack
- **Face detection:** Google ML Kit Face Detection (`google_mlkit_face_detection` Flutter package)
- **Face recognition/matching:** ML Kit or TFLite model for face embeddings — compare embeddings against stored profiles
- **Profile storage:** SQLite on-device (`sqflite` Flutter package)

### How It Works
1. User creates person profiles in the app (name + reference face photo)
2. App extracts face embedding from reference photo and stores it in local SQLite
3. When a new photo is captured, ML Kit detects faces and extracts embeddings
4. Embeddings are compared against stored profiles (cosine similarity) to find matches
5. Matched `user_id` + normalized `bbox` are added to the metadata JSON sent to `/encode`

### Data Model (SQLite)
- **people** table: `id`, `name`, `created_at`
- **face_embeddings** table: `id`, `person_id`, `embedding` (binary), `reference_photo_path`

## Flutter App Screens

1. **Capture screen** — Camera preview + metadata controls (indoor/outdoor toggle, scene hint text field, tag input)
2. **Encoding feedback** — "Encoding..." spinner after capture → calls `/encode` → saves .kpeg
3. **Gallery view** — List of saved .kpeg files (filename, date). Tap to decode
4. **Decode viewer** — Quality selector (fast/balanced/high) → calls `/decode` → displays reconstructed JPEG
5. **People management** — Create/view/delete person profiles with reference photos

## Critical Android Configuration

The `AndroidManifest.xml` must include:
- `flutterEmbedding=2` meta-data (required for Flutter 3.41.6, build fails without it)
- `CAMERA` and `INTERNET` permissions
- `ACCESS_FINE_LOCATION` and `ACCESS_COARSE_LOCATION` permissions (for GPS metadata)
- `usesCleartextTraffic=true` (for local HTTP in hackathon)
- `FileProvider` with `@xml/file_paths` (required by `image_picker`)

## Key Gotchas

- **Emulator networking:** Use `10.0.2.2` instead of `localhost` to reach the host machine
- **Physical device:** PC and phone must be on same WiFi; open firewall ports (`sudo ufw allow <port>`)
- **IP changes:** Device IP may change with DHCP; verify with `ip a` before building
- **Decode is slow:** 5-15 seconds for AI reconstruction — UI must show loading state
- **Sensor timing:** Compass heading and camera tilt must be captured AT the moment of photo capture, not after
- **Weather API:** Deprioritized for the hackathon, send `null`

## Hackathon Priorities

**Must have:**
1. Photo capture with metadata collection
2. On-device face detection + recognition + profile management
3. Integration with teammate's /encode endpoint
4. .kpeg local storage and gallery
5. Integration with /decode to view reconstructed photos

**Nice to have:**
- Indoor/outdoor toggle with place description
- Scene hint and tags
- Quality selector for decode
- EXIF lens info extraction
