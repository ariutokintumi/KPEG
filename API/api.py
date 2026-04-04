import json
import os
import shutil
import uuid
from flask import Flask, request, jsonify
from database import init_db, insert_person, list_people, delete_person, person_exists
from database import insert_place, list_places, delete_place, place_exists
from database import insert_object, list_objects, delete_object, object_exists

app = Flask(__name__)

LIBRARY_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'library')


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
# ENCODE / DECODE — stubs for teammate
# ══════════════════════════════════════

@app.route('/encode', methods=['POST'])
def encode():
    """
    MOCKUP: saves the original image and returns a fake .kpeg binary.
    The .kpeg contains a header + metadata + reference to the saved original.
    Replace this with the real AI encoding when ready.
    """
    if 'image' not in request.files:
        return jsonify({'error': 'No image provided'}), 422

    image = request.files['image']
    metadata_str = request.form.get('metadata', '{}')

    try:
        metadata = json.loads(metadata_str)
    except json.JSONDecodeError:
        metadata = {}

    # Save original image for decode mockup
    originals_dir = ensure_dir(os.path.join(LIBRARY_DIR, '_originals'))
    image_id = str(uuid.uuid4())[:8]
    original_path = os.path.join(originals_dir, f'{image_id}.jpg')
    image.save(original_path)

    # Build fake .kpeg binary: header + JSON payload (kept under 2KB)
    # Trim metadata to fit in 2KB
    kpeg_payload = {
        '_mockup': True,
        '_image_id': image_id,
        'orientation': metadata.get('orientation', 'portrait'),
        'timestamp': metadata.get('timestamp', 0),
        'device_model': metadata.get('device_model', ''),
        'people': metadata.get('people', []),
        'scene_hint': metadata.get('scene_hint', ''),
        'session_id': metadata.get('session_id', ''),
    }
    payload_bytes = json.dumps(kpeg_payload, separators=(',', ':')).encode('utf-8')

    # KPEG header (6 bytes) + payload
    kpeg_binary = b'KPEG\x01\x00' + payload_bytes

    # Ensure ≤2KB
    if len(kpeg_binary) > 2048:
        kpeg_binary = kpeg_binary[:2048]

    print(f'📦 Encoded: {image_id} ({len(kpeg_binary)} bytes) — MOCKUP')
    return kpeg_binary, 200, {'Content-Type': 'application/octet-stream'}


@app.route('/decode', methods=['POST'])
def decode():
    """
    MOCKUP: reads the .kpeg, extracts the image_id, returns the original photo.
    Replace this with the real AI reconstruction when ready.
    """
    if 'kpeg_file' not in request.files:
        return jsonify({'error': 'No kpeg_file provided'}), 422

    quality = request.form.get('quality', 'balanced')
    kpeg_data = request.files['kpeg_file'].read()

    # Parse .kpeg mockup: skip 6-byte header, rest is JSON
    try:
        payload = json.loads(kpeg_data[6:].decode('utf-8'))
        image_id = payload.get('_image_id')
    except (json.JSONDecodeError, UnicodeDecodeError):
        return jsonify({'error': 'Invalid .kpeg file'}), 422

    if not image_id:
        return jsonify({'error': 'Cannot decode — not a mockup .kpeg'}), 422

    original_path = os.path.join(LIBRARY_DIR, '_originals', f'{image_id}.jpg')
    if not os.path.exists(original_path):
        return jsonify({'error': f'Original image not found: {image_id}'}), 422

    # Return the original image as "reconstructed" (mockup)
    with open(original_path, 'rb') as f:
        image_bytes = f.read()

    print(f'🖼️  Decoded: {image_id} (quality={quality}) — MOCKUP')
    return image_bytes, 200, {'Content-Type': 'image/jpeg'}


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

    # Parse selfie timestamps
    timestamps_raw = request.form.get('selfie_timestamps', '[]')
    try:
        timestamps = json.loads(timestamps_raw)
    except json.JSONDecodeError:
        timestamps = []

    while len(timestamps) < len(selfies):
        timestamps.append(0)

    # Save selfie files
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

    # Parse per-photo metadata
    metadata_raw = request.form.get('photos_metadata', '[]')
    try:
        photos_metadata = json.loads(metadata_raw)
    except json.JSONDecodeError:
        photos_metadata = []

    while len(photos_metadata) < len(photos):
        photos_metadata.append({})

    # Save photo files
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

    # Save photo files
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


# ══════════════════════════════════════
# STARTUP
# ══════════════════════════════════════

if __name__ == '__main__':
    init_db()
    ensure_dir(os.path.join(LIBRARY_DIR, 'people'))
    ensure_dir(os.path.join(LIBRARY_DIR, 'places'))
    ensure_dir(os.path.join(LIBRARY_DIR, 'objects'))
    print(f'📂 Library: {LIBRARY_DIR}')
    print(f'🚀 KPEG API on http://0.0.0.0:8000')
    app.run(host='0.0.0.0', port=8000, debug=True)
