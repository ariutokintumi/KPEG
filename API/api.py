import base64
import json
import os
import shutil
import sys
import uuid
from pathlib import Path
from flask import Flask, request, jsonify, send_file
from database import init_db, insert_person, list_people, delete_person, person_exists
from database import get_person_selfies, add_person_selfies
from database import insert_place, list_places, delete_place, place_exists
from database import get_place_photos, add_place_photos
from database import insert_object, list_objects, delete_object, object_exists
from database import get_object_photos, add_object_photos
from database import insert_hedera_metadata, get_hedera_metadata
import hedera_service

# Import KPEG engine from Tooling/
_TOOLING_DIR = Path(__file__).resolve().parent.parent / 'Tooling'
if str(_TOOLING_DIR) not in sys.path:
    sys.path.insert(0, str(_TOOLING_DIR))
from kpeg.encoder import encode as kpeg_encode
from kpeg.decoder import decode as kpeg_decode, inspect as kpeg_inspect
from kpeg.format import unpack_kpeg, pack_kpeg, FLAG_HAS_PEOPLE
from kpeg.compression import decompress_json, compress_json

app = Flask(__name__)

LIBRARY_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'library')
KPEG_DIR = os.path.join(LIBRARY_DIR, '_kpeg')

MAX_UPDATE_UNKNOWNS = 5


def ensure_dir(path):
    os.makedirs(path, exist_ok=True)
    return path


# ══════════════════════════════════════
# HEALTH
# ══════════════════════════════════════

@app.route('/health', methods=['GET'])
def health():
    return jsonify({'status': 'ok', 'version': '1.0.0'})


# ══════════════════════════════════════
# ENCODE / DECODE — real KPEG engine
# ══════════════════════════════════════

@app.route('/encode', methods=['POST'])
def encode():
    """
    Real KPEG encode: photo + metadata → ≤2KB .kpeg binary.
    Pipeline: palette + bitmap + Claude Vision scene JSON + library refs + Brotli.
    Returns JSON with base64-encoded .kpeg + Hedera registration info.
    """
    if 'image' not in request.files:
        return jsonify({'error': 'No image provided'}), 422

    image_file = request.files['image']
    metadata_str = request.form.get('metadata', '{}')

    try:
        metadata = json.loads(metadata_str)
    except json.JSONDecodeError:
        return jsonify({'error': 'Invalid metadata JSON'}), 422

    try:
        image_bytes = image_file.read()
        kpeg_binary = kpeg_encode(image_bytes, metadata)
    except Exception as e:
        print(f'❌ Encode failed: {e}')
        return jsonify({'error': f'Encode failed: {e}'}), 500

    # Persist the .kpeg file on disk for inspection/batch updates later
    ensure_dir(KPEG_DIR)
    kpeg_id = str(uuid.uuid4())[:8]
    kpeg_path = os.path.join(KPEG_DIR, f'{kpeg_id}.kpeg')
    with open(kpeg_path, 'wb') as f:
        f.write(kpeg_binary)

    print(f'📦 Encoded: {kpeg_id} ({len(kpeg_binary)} bytes)')

    # Registrar en Hedera (best-effort — si falla, el encode sigue funcionando)
    hedera_info = None
    if hedera_service.is_available():
        try:
            hedera_info = hedera_service.register_image(kpeg_binary, kpeg_id)
            if hedera_info:
                insert_hedera_metadata(kpeg_id, hedera_info)
        except Exception as e:
            print(f'⚠️  Hedera registration failed: {e}')

    # Devolver JSON con kpeg en base64 (la Flutter app lo espera así)
    return jsonify({
        'kpeg_base64': base64.b64encode(kpeg_binary).decode('ascii'),
        'image_id': kpeg_id,
        'hedera': hedera_info,
    })


@app.route('/decode', methods=['POST'])
def decode():
    """
    Real KPEG decode: .kpeg binary → reconstructed JPEG via FLUX.
    quality: "fast" | "balanced" | "high".
    """
    if 'kpeg_file' not in request.files:
        return jsonify({'error': 'No kpeg_file provided'}), 422

    quality = request.form.get('quality', 'balanced')
    if quality not in ('fast', 'balanced', 'high'):
        return jsonify({'error': 'quality must be fast|balanced|high'}), 422

    kpeg_data = request.files['kpeg_file'].read()

    try:
        jpeg_bytes = kpeg_decode(kpeg_data, quality=quality)
    except ValueError as e:
        return jsonify({'error': f'Invalid .kpeg file: {e}'}), 422
    except Exception as e:
        print(f'❌ Decode failed: {e}')
        return jsonify({'error': f'Decode failed: {e}'}), 500

    print(f'🖼️  Decoded: {len(kpeg_data)}B -> {len(jpeg_bytes)}B JPEG (quality={quality})')
    return jpeg_bytes, 200, {'Content-Type': 'image/jpeg'}


@app.route('/update_people', methods=['POST'])
def update_people():
    """Batch re-tag unknown persons in a .kpeg without re-processing the image."""
    if 'kpeg_file' not in request.files:
        return jsonify({'error': 'No kpeg_file provided'}), 422

    mapping_raw = request.form.get('mapping', '{}')
    try:
        mapping = json.loads(mapping_raw)
    except json.JSONDecodeError:
        return jsonify({'error': 'Invalid mapping JSON'}), 422

    if not isinstance(mapping, dict) or not mapping:
        return jsonify({'error': 'mapping must be a non-empty object'}), 422
    if len(mapping) > MAX_UPDATE_UNKNOWNS:
        return jsonify({
            'error': f'Too many mappings: {len(mapping)} (max {MAX_UPDATE_UNKNOWNS})'
        }), 422

    kpeg_data = request.files['kpeg_file'].read()

    try:
        kpeg = unpack_kpeg(kpeg_data)
        scene = decompress_json(kpeg.compressed_json)
    except ValueError as e:
        return jsonify({'error': f'Invalid .kpeg file: {e}'}), 422

    updated = 0
    for obj in scene.get('o', []):
        current = obj.get('ref', '')
        if current in mapping:
            obj['ref'] = mapping[current]
            updated += 1

    if updated == 0:
        return jsonify({'error': 'No matching unknowns found in .kpeg'}), 422

    new_compressed = compress_json(scene)
    try:
        new_kpeg = pack_kpeg(
            bitmap_data=kpeg.bitmap_data,
            compressed_json=new_compressed,
            flags=kpeg.flags | FLAG_HAS_PEOPLE,
            aspect_w=kpeg.aspect_w,
            aspect_h=kpeg.aspect_h,
        )
    except ValueError as e:
        return jsonify({'error': f'Updated .kpeg exceeds size limit: {e}'}), 422

    print(f'🔁 Updated: {updated}/{len(mapping)} mappings applied, {len(kpeg_data)}B -> {len(new_kpeg)}B')
    return new_kpeg, 200, {
        'Content-Type': 'application/octet-stream',
        'X-KPEG-Updated': str(updated),
        'X-KPEG-Size': str(len(new_kpeg)),
    }


@app.route('/inspect', methods=['POST'])
def inspect_kpeg():
    """Debug helper: return KPEG header + scene summary as JSON."""
    if 'kpeg_file' not in request.files:
        return jsonify({'error': 'No kpeg_file provided'}), 422
    kpeg_data = request.files['kpeg_file'].read()
    try:
        info = kpeg_inspect(kpeg_data)
    except ValueError as e:
        return jsonify({'error': f'Invalid .kpeg file: {e}'}), 422
    return jsonify(info)


# ══════════════════════════════════════
# PEOPLE LIBRARY
# ══════════════════════════════════════

@app.route('/library/people', methods=['POST'])
def register_person():
    user_id = request.form.get('user_id')
    name = request.form.get('name')

    if not user_id or not name:
        return jsonify({'error': 'user_id and name are required'}), 422

    if person_exists(user_id):
        return jsonify({'error': f'Person {user_id} already exists'}), 422

    selfies = request.files.getlist('selfies')
    if not selfies:
        return jsonify({'error': 'At least one selfie is required'}), 422

    timestamps_raw = request.form.get('selfie_timestamps', '[]')
    try:
        timestamps = json.loads(timestamps_raw)
    except json.JSONDecodeError:
        timestamps = []

    while len(timestamps) < len(selfies):
        timestamps.append(0)

    person_dir = ensure_dir(os.path.join(LIBRARY_DIR, 'people', user_id))
    saved_paths = []
    for i, selfie in enumerate(selfies):
        filename = f'selfie_{i}.jpg'
        path = os.path.join(person_dir, filename)
        selfie.save(path)
        saved_paths.append(path)

    insert_person(user_id, name, saved_paths, timestamps)

    print(f'✅ Person registered: {user_id} ({name}) — {len(selfies)} selfies')
    return jsonify({'user_id': user_id, 'status': 'registered'})


@app.route('/library/people', methods=['GET'])
def get_people():
    return jsonify(list_people())


@app.route('/library/people/<user_id>', methods=['DELETE'])
def remove_person(user_id):
    if not person_exists(user_id):
        return jsonify({'error': f'Person {user_id} not found'}), 404

    person_dir = os.path.join(LIBRARY_DIR, 'people', user_id)
    if os.path.exists(person_dir):
        shutil.rmtree(person_dir)

    delete_person(user_id)

    print(f'🗑️  Person deleted: {user_id}')
    return jsonify({'status': 'deleted'})


@app.route('/library/people/<user_id>/selfies', methods=['GET'])
def list_person_selfies(user_id):
    if not person_exists(user_id):
        return jsonify({'error': f'Person {user_id} not found'}), 404
    selfies = get_person_selfies(user_id)
    return jsonify({
        'user_id': user_id,
        'selfie_count': len(selfies),
        'selfies': [{'index': i, 'timestamp': s['timestamp']} for i, s in enumerate(selfies)]
    })


@app.route('/library/people/<user_id>/selfie/<int:idx>', methods=['GET'])
def serve_person_selfie(user_id, idx):
    if not person_exists(user_id):
        return jsonify({'error': f'Person {user_id} not found'}), 404
    selfies = get_person_selfies(user_id)
    if idx < 0 or idx >= len(selfies):
        return jsonify({'error': f'Selfie index {idx} out of range (0-{len(selfies)-1})'}), 404
    path = selfies[idx]['file_path']
    if not os.path.exists(path):
        return jsonify({'error': 'Selfie file not found on disk'}), 404
    return send_file(path, mimetype='image/jpeg')


@app.route('/library/people/<user_id>/selfies', methods=['POST'])
def add_person_selfies_endpoint(user_id):
    if not person_exists(user_id):
        return jsonify({'error': f'Person {user_id} not found'}), 404

    selfies = request.files.getlist('selfies')
    if not selfies:
        return jsonify({'error': 'At least one selfie is required'}), 422

    timestamps_raw = request.form.get('selfie_timestamps', '[]')
    try:
        timestamps = json.loads(timestamps_raw)
    except json.JSONDecodeError:
        timestamps = []
    while len(timestamps) < len(selfies):
        timestamps.append(0)

    existing = get_person_selfies(user_id)
    start_idx = len(existing)

    person_dir = ensure_dir(os.path.join(LIBRARY_DIR, 'people', user_id))
    saved_paths = []
    for i, selfie in enumerate(selfies):
        filename = f'selfie_{start_idx + i}.jpg'
        path = os.path.join(person_dir, filename)
        selfie.save(path)
        saved_paths.append(path)

    add_person_selfies(user_id, saved_paths, timestamps)

    print(f'📸 Added {len(selfies)} selfies to {user_id}')
    return jsonify({'user_id': user_id, 'added': len(selfies), 'total': start_idx + len(selfies)})


# ══════════════════════════════════════
# PLACES LIBRARY
# ══════════════════════════════════════

@app.route('/library/places', methods=['POST'])
def register_place():
    place_id = request.form.get('place_id')
    name = request.form.get('name')

    if not place_id or not name:
        return jsonify({'error': 'place_id and name are required'}), 422

    if place_exists(place_id):
        return jsonify({'error': f'Place {place_id} already exists'}), 422

    photos = request.files.getlist('photos')
    if not photos:
        return jsonify({'error': 'At least one photo is required'}), 422

    metadata_raw = request.form.get('photos_metadata', '[]')
    try:
        photos_metadata = json.loads(metadata_raw)
    except json.JSONDecodeError:
        photos_metadata = []

    while len(photos_metadata) < len(photos):
        photos_metadata.append({})

    place_dir = ensure_dir(os.path.join(LIBRARY_DIR, 'places', place_id))
    saved_paths = []
    for i, photo in enumerate(photos):
        filename = f'photo_{i}.jpg'
        path = os.path.join(place_dir, filename)
        photo.save(path)
        saved_paths.append(path)

    insert_place(place_id, name, saved_paths, photos_metadata)

    print(f'✅ Place registered: {place_id} ({name}) — {len(photos)} photos')
    return jsonify({'place_id': place_id, 'status': 'registered'})


@app.route('/library/places', methods=['GET'])
def get_places():
    return jsonify(list_places())


@app.route('/library/places/<place_id>', methods=['DELETE'])
def remove_place(place_id):
    if not place_exists(place_id):
        return jsonify({'error': f'Place {place_id} not found'}), 404

    place_dir = os.path.join(LIBRARY_DIR, 'places', place_id)
    if os.path.exists(place_dir):
        shutil.rmtree(place_dir)

    delete_place(place_id)

    print(f'🗑️  Place deleted: {place_id}')
    return jsonify({'status': 'deleted'})


@app.route('/library/places/<place_id>/photos', methods=['GET'])
def list_place_photos(place_id):
    if not place_exists(place_id):
        return jsonify({'error': f'Place {place_id} not found'}), 404
    photos = get_place_photos(place_id)
    return jsonify({
        'place_id': place_id,
        'photo_count': len(photos),
        'photos': [{'index': i, 'lat': p['lat'], 'lng': p['lng'],
                     'compass_heading': p['compass_heading'], 'camera_tilt': p['camera_tilt'],
                     'timestamp': p['timestamp']} for i, p in enumerate(photos)]
    })


@app.route('/library/places/<place_id>/photo/<int:idx>', methods=['GET'])
def serve_place_photo(place_id, idx):
    if not place_exists(place_id):
        return jsonify({'error': f'Place {place_id} not found'}), 404
    photos = get_place_photos(place_id)
    if idx < 0 or idx >= len(photos):
        return jsonify({'error': f'Photo index {idx} out of range (0-{len(photos)-1})'}), 404
    path = photos[idx]['file_path']
    if not os.path.exists(path):
        return jsonify({'error': 'Photo file not found on disk'}), 404
    return send_file(path, mimetype='image/jpeg')


@app.route('/library/places/<place_id>/photos', methods=['POST'])
def add_place_photos_endpoint(place_id):
    if not place_exists(place_id):
        return jsonify({'error': f'Place {place_id} not found'}), 404

    photos = request.files.getlist('photos')
    if not photos:
        return jsonify({'error': 'At least one photo is required'}), 422

    metadata_raw = request.form.get('photos_metadata', '[]')
    try:
        photos_metadata = json.loads(metadata_raw)
    except json.JSONDecodeError:
        photos_metadata = []
    while len(photos_metadata) < len(photos):
        photos_metadata.append({})

    existing = get_place_photos(place_id)
    start_idx = len(existing)

    place_dir = ensure_dir(os.path.join(LIBRARY_DIR, 'places', place_id))
    saved_paths = []
    for i, photo in enumerate(photos):
        filename = f'photo_{start_idx + i}.jpg'
        path = os.path.join(place_dir, filename)
        photo.save(path)
        saved_paths.append(path)

    add_place_photos(place_id, saved_paths, photos_metadata)

    print(f'📸 Added {len(photos)} photos to place {place_id}')
    return jsonify({'place_id': place_id, 'added': len(photos), 'total': start_idx + len(photos)})


# ══════════════════════════════════════
# OBJECTS LIBRARY
# ══════════════════════════════════════

@app.route('/library/objects', methods=['POST'])
def register_object():
    object_id = request.form.get('object_id')
    name = request.form.get('name')
    category = request.form.get('category', 'other')

    if not object_id or not name:
        return jsonify({'error': 'object_id and name are required'}), 422

    valid_categories = ['furniture', 'decoration', 'electronics', 'clothing', 'other']
    if category not in valid_categories:
        return jsonify({'error': f'category must be one of: {valid_categories}'}), 422

    if object_exists(object_id):
        return jsonify({'error': f'Object {object_id} already exists'}), 422

    photos = request.files.getlist('photos')
    if not photos:
        return jsonify({'error': 'At least one photo is required'}), 422

    object_dir = ensure_dir(os.path.join(LIBRARY_DIR, 'objects', object_id))
    saved_paths = []
    for i, photo in enumerate(photos):
        filename = f'photo_{i}.jpg'
        path = os.path.join(object_dir, filename)
        photo.save(path)
        saved_paths.append(path)

    insert_object(object_id, name, category, saved_paths)

    print(f'✅ Object registered: {object_id} ({name}) [{category}] — {len(photos)} photos')
    return jsonify({'object_id': object_id, 'status': 'registered'})


@app.route('/library/objects', methods=['GET'])
def get_objects():
    return jsonify(list_objects())


@app.route('/library/objects/<object_id>', methods=['DELETE'])
def remove_object(object_id):
    if not object_exists(object_id):
        return jsonify({'error': f'Object {object_id} not found'}), 404

    object_dir = os.path.join(LIBRARY_DIR, 'objects', object_id)
    if os.path.exists(object_dir):
        shutil.rmtree(object_dir)

    delete_object(object_id)

    print(f'🗑️  Object deleted: {object_id}')
    return jsonify({'status': 'deleted'})


@app.route('/library/objects/<object_id>/photos', methods=['GET'])
def list_object_photos(object_id):
    if not object_exists(object_id):
        return jsonify({'error': f'Object {object_id} not found'}), 404
    photos = get_object_photos(object_id)
    return jsonify({
        'object_id': object_id,
        'photo_count': len(photos),
        'photos': [{'index': i} for i in range(len(photos))]
    })


@app.route('/library/objects/<object_id>/photo/<int:idx>', methods=['GET'])
def serve_object_photo(object_id, idx):
    if not object_exists(object_id):
        return jsonify({'error': f'Object {object_id} not found'}), 404
    photos = get_object_photos(object_id)
    if idx < 0 or idx >= len(photos):
        return jsonify({'error': f'Photo index {idx} out of range (0-{len(photos)-1})'}), 404
    path = photos[idx]['file_path']
    if not os.path.exists(path):
        return jsonify({'error': 'Photo file not found on disk'}), 404
    return send_file(path, mimetype='image/jpeg')


@app.route('/library/objects/<object_id>/photos', methods=['POST'])
def add_object_photos_endpoint(object_id):
    if not object_exists(object_id):
        return jsonify({'error': f'Object {object_id} not found'}), 404

    photos = request.files.getlist('photos')
    if not photos:
        return jsonify({'error': 'At least one photo is required'}), 422

    existing = get_object_photos(object_id)
    start_idx = len(existing)

    object_dir = ensure_dir(os.path.join(LIBRARY_DIR, 'objects', object_id))
    saved_paths = []
    for i, photo in enumerate(photos):
        filename = f'photo_{start_idx + i}.jpg'
        path = os.path.join(object_dir, filename)
        photo.save(path)
        saved_paths.append(path)

    add_object_photos(object_id, saved_paths)

    print(f'📸 Added {len(photos)} photos to object {object_id}')
    return jsonify({'object_id': object_id, 'added': len(photos), 'total': start_idx + len(photos)})


# ══════════════════════════════════════
# HEDERA
# ══════════════════════════════════════

@app.route('/hedera/setup', methods=['POST'])
def hedera_setup():
    """Crear topic HCS + colección NFT (llamar una vez al inicio)."""
    result = hedera_service.setup()
    if 'error' in result:
        return jsonify(result), 500
    return jsonify(result)


@app.route('/hedera/status', methods=['GET'])
def hedera_status():
    """Estado actual de la integración Hedera."""
    return jsonify(hedera_service.get_state())


@app.route('/hedera/info/<image_id>', methods=['GET'])
def hedera_info(image_id):
    """Obtener metadatos Hedera de una imagen."""
    meta = get_hedera_metadata(image_id)
    if meta is None:
        return jsonify({'error': f'No Hedera data for {image_id}'}), 404
    return jsonify(meta)


# ══════════════════════════════════════
# STARTUP
# ══════════════════════════════════════

if __name__ == '__main__':
    init_db()
    ensure_dir(os.path.join(LIBRARY_DIR, 'people'))
    ensure_dir(os.path.join(LIBRARY_DIR, 'places'))
    ensure_dir(os.path.join(LIBRARY_DIR, 'objects'))
    ensure_dir(KPEG_DIR)
    print(f'📂 Library: {LIBRARY_DIR}')

    # Inicializar Hedera
    if hedera_service.is_available():
        state = hedera_service.get_state()
        print(f'🔗 Hedera: {state["network"]} / {state["account_id"]}')
        if state['topic_id']:
            print(f'   Topic: {state["topic_id"]}')
        if state['nft_token_id']:
            print(f'   NFT:   {state["nft_token_id"]}')
        if not state['topic_id'] or not state['nft_token_id']:
            print('   ⚠️  Call POST /hedera/setup to initialize')
    else:
        print('⚠️  Hedera: not configured (check .env)')

    print(f'🚀 KPEG API on http://0.0.0.0:8000')
    app.run(host='0.0.0.0', port=8000, debug=True)
