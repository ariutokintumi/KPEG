"""Integration tests for API/api.py (encode/decode/update_people).

FLUX + Anthropic are stubbed so tests hit the real Flask app but no network.
Run:  cd API && python -m pytest test_api.py -v
"""
import io
import json
import os
import sqlite3
import sys
import tempfile
from pathlib import Path
from unittest.mock import patch

import numpy as np
import pytest
from PIL import Image

# Make Tooling importable and force the API's DB into a temp location
API_DIR = Path(__file__).parent
REPO_ROOT = API_DIR.parent
sys.path.insert(0, str(REPO_ROOT / 'Tooling'))


@pytest.fixture
def client(tmp_path, monkeypatch):
    """Spin up the Flask app pointed at an isolated temp library + DB."""
    # Isolate library/DB/kpeg dirs per test
    tmp_library = tmp_path / 'library'
    tmp_db = tmp_path / 'kpeg_library.db'
    (tmp_library / 'people').mkdir(parents=True)
    (tmp_library / 'places').mkdir(parents=True)
    (tmp_library / 'objects').mkdir(parents=True)
    (tmp_library / '_kpeg').mkdir(parents=True)

    monkeypatch.setenv('KPEG_TEST_DB', str(tmp_db))
    monkeypatch.setattr('database.DB_PATH', str(tmp_db))

    # Reimport api with patched paths
    if 'api' in sys.modules:
        del sys.modules['api']
    import api as api_module
    api_module.LIBRARY_DIR = str(tmp_library)
    api_module.KPEG_DIR = str(tmp_library / '_kpeg')

    # Point the Tooling DB path at the same temp DB so library_reader sees it
    monkeypatch.setattr('kpeg.library_reader.DATABASE_PATH', tmp_db)

    from database import init_db
    init_db()

    api_module.app.config['TESTING'] = True
    with api_module.app.test_client() as c:
        yield c


def _make_jpeg_bytes(w=320, h=240) -> bytes:
    arr = np.random.randint(0, 256, size=(h, w, 3), dtype=np.uint8)
    buf = io.BytesIO()
    Image.fromarray(arr).save(buf, format='JPEG', quality=80)
    return buf.getvalue()


# ═══ /health ═══

def test_health(client):
    resp = client.get('/health')
    assert resp.status_code == 200
    assert resp.get_json()['status'] == 'ok'


# ═══ /encode ═══

def test_encode_requires_image(client):
    resp = client.post('/encode', data={})
    assert resp.status_code == 422
    assert 'image' in resp.get_json()['error'].lower()


def test_encode_invalid_metadata_returns_422(client):
    resp = client.post('/encode', data={
        'image': (io.BytesIO(_make_jpeg_bytes()), 'photo.jpg'),
        'metadata': 'not-json',
    })
    assert resp.status_code == 422


def test_encode_happy_path_returns_kpeg(client):
    fake_scene = {
        's': {'d': 'test scene', 'style': 'snapshot'},
        'o': [], 't': [], 'colors': ['#808080'],
    }
    metadata = {
        'orientation': 'landscape',
        'timestamp': 1743724800,
        'people': [],
    }

    with patch('kpeg.encoder.analyze_scene', return_value=fake_scene), \
         patch('kpeg.encoder.get_objects_catalog', return_value=[]):
        resp = client.post('/encode', data={
            'image': (io.BytesIO(_make_jpeg_bytes()), 'photo.jpg'),
            'metadata': json.dumps(metadata),
        })

    assert resp.status_code == 200
    assert resp.content_type == 'application/octet-stream'
    assert resp.data[:4] == b'KPEG'
    assert len(resp.data) <= 2514
    assert 'X-KPEG-Id' in resp.headers
    assert int(resp.headers['X-KPEG-Size']) == len(resp.data)


def test_encoded_file_saved_to_kpeg_dir(client, tmp_path):
    fake_scene = {'s': {'d': 'x'}, 'o': [], 't': [], 'colors': []}
    with patch('kpeg.encoder.analyze_scene', return_value=fake_scene), \
         patch('kpeg.encoder.get_objects_catalog', return_value=[]):
        resp = client.post('/encode', data={
            'image': (io.BytesIO(_make_jpeg_bytes()), 'photo.jpg'),
            'metadata': json.dumps({'orientation': 'landscape', 'people': []}),
        })
    assert resp.status_code == 200
    import api as api_module
    saved = list(Path(api_module.KPEG_DIR).glob('*.kpeg'))
    assert len(saved) == 1
    assert saved[0].read_bytes() == resp.data


# ═══ /decode ═══

def _encode_via_client(client, people=None):
    """Helper: post to /encode with a fake scene, return the .kpeg bytes."""
    fake_scene = {
        's': {'d': 'scene for decode'},
        'o': [
            {'n': 'person', 'b': [0, 0, 1, 1], 'd': 'unknown woman', 'ref': 'unknown1'},
        ] if people is None else people,
        't': [], 'colors': [],
    }
    metadata = {
        'orientation': 'landscape', 'people': [],
    }
    with patch('kpeg.encoder.analyze_scene', return_value=fake_scene), \
         patch('kpeg.encoder.get_objects_catalog', return_value=[]):
        resp = client.post('/encode', data={
            'image': (io.BytesIO(_make_jpeg_bytes()), 'p.jpg'),
            'metadata': json.dumps(metadata),
        })
    assert resp.status_code == 200
    return resp.data


def test_decode_requires_file(client):
    resp = client.post('/decode', data={'quality': 'fast'})
    assert resp.status_code == 422


def test_decode_invalid_quality_rejected(client):
    kpeg_bytes = _encode_via_client(client)
    resp = client.post('/decode', data={
        'kpeg_file': (io.BytesIO(kpeg_bytes), 'x.kpeg'),
        'quality': 'ultra-mega',
    })
    assert resp.status_code == 422


def test_decode_invalid_kpeg_returns_422(client):
    resp = client.post('/decode', data={
        'kpeg_file': (io.BytesIO(b'not-a-kpeg'), 'x.kpeg'),
        'quality': 'fast',
    })
    assert resp.status_code == 422


def test_decode_returns_jpeg_stub_mode(client):
    """With FAL_KEY empty, decoder falls back to stub — still returns a JPEG."""
    kpeg_bytes = _encode_via_client(client)
    with patch('kpeg.image_generator.FAL_KEY', ''):
        resp = client.post('/decode', data={
            'kpeg_file': (io.BytesIO(kpeg_bytes), 'x.kpeg'),
            'quality': 'fast',
        })
    assert resp.status_code == 200
    assert resp.content_type == 'image/jpeg'
    assert resp.data[:2] == b'\xff\xd8'  # JPEG SOI


# ═══ /update_people ═══

def test_update_people_swaps_refs(client):
    kpeg_bytes = _encode_via_client(client, people=[
        {'n': 'person', 'b': [0, 0, 1, 1], 'd': 'woman', 'ref': 'unknown1'},
        {'n': 'person', 'b': [0.3, 0, 0.6, 1], 'd': 'man', 'ref': 'unknown2'},
    ])
    mapping = {'unknown1': 'usr_maria', 'unknown2': 'usr_judge'}

    resp = client.post('/update_people', data={
        'kpeg_file': (io.BytesIO(kpeg_bytes), 'x.kpeg'),
        'mapping': json.dumps(mapping),
    })
    assert resp.status_code == 200
    assert resp.data[:4] == b'KPEG'
    assert resp.headers['X-KPEG-Updated'] == '2'

    # Verify refs really got swapped in the returned file
    from kpeg.format import unpack_kpeg
    from kpeg.compression import decompress_json
    updated = unpack_kpeg(resp.data)
    scene = decompress_json(updated.compressed_json)
    refs = [o['ref'] for o in scene['o']]
    assert 'usr_maria' in refs
    assert 'usr_judge' in refs
    assert 'unknown1' not in refs
    assert 'unknown2' not in refs


def test_update_people_partial_match(client):
    kpeg_bytes = _encode_via_client(client, people=[
        {'n': 'person', 'b': [0, 0, 1, 1], 'd': 'woman', 'ref': 'unknown1'},
    ])
    resp = client.post('/update_people', data={
        'kpeg_file': (io.BytesIO(kpeg_bytes), 'x.kpeg'),
        'mapping': json.dumps({'unknown1': 'usr_a', 'unknown5': 'usr_b'}),
    })
    assert resp.status_code == 200
    assert resp.headers['X-KPEG-Updated'] == '1'


def test_update_people_empty_mapping_rejected(client):
    kpeg_bytes = _encode_via_client(client)
    resp = client.post('/update_people', data={
        'kpeg_file': (io.BytesIO(kpeg_bytes), 'x.kpeg'),
        'mapping': '{}',
    })
    assert resp.status_code == 422


def test_update_people_invalid_mapping_json(client):
    kpeg_bytes = _encode_via_client(client)
    resp = client.post('/update_people', data={
        'kpeg_file': (io.BytesIO(kpeg_bytes), 'x.kpeg'),
        'mapping': 'not json',
    })
    assert resp.status_code == 422


def test_update_people_no_match_returns_422(client):
    kpeg_bytes = _encode_via_client(client, people=[
        {'n': 'person', 'b': [0, 0, 1, 1], 'd': 'w', 'ref': 'unknown1'},
    ])
    resp = client.post('/update_people', data={
        'kpeg_file': (io.BytesIO(kpeg_bytes), 'x.kpeg'),
        'mapping': json.dumps({'unknown9': 'usr_x'}),
    })
    assert resp.status_code == 422


def test_update_people_cap(client):
    kpeg_bytes = _encode_via_client(client)
    mapping = {f'unknown{i}': f'usr_{i}' for i in range(1, 7)}
    resp = client.post('/update_people', data={
        'kpeg_file': (io.BytesIO(kpeg_bytes), 'x.kpeg'),
        'mapping': json.dumps(mapping),
    })
    assert resp.status_code == 422
    assert 'max' in resp.get_json()['error'].lower()


def test_update_people_invalid_kpeg(client):
    resp = client.post('/update_people', data={
        'kpeg_file': (io.BytesIO(b'junk'), 'x.kpeg'),
        'mapping': json.dumps({'unknown1': 'usr_a'}),
    })
    assert resp.status_code == 422


# ═══ /inspect ═══

def test_inspect_returns_summary(client):
    kpeg_bytes = _encode_via_client(client)
    resp = client.post('/inspect', data={
        'kpeg_file': (io.BytesIO(kpeg_bytes), 'x.kpeg'),
    })
    assert resp.status_code == 200
    info = resp.get_json()
    assert info['size_bytes'] == len(kpeg_bytes)
    assert info['version'] == 1
    assert 'flags' in info
    assert 'scene' in info


def test_inspect_invalid_kpeg(client):
    resp = client.post('/inspect', data={
        'kpeg_file': (io.BytesIO(b'garbage'), 'x.kpeg'),
    })
    assert resp.status_code == 422


# ═══ Library routes still work (regression) ═══

def test_library_people_list_empty(client):
    resp = client.get('/library/people')
    assert resp.status_code == 200
    assert resp.get_json() == []


def test_library_places_list_empty(client):
    resp = client.get('/library/places')
    assert resp.status_code == 200
    assert resp.get_json() == []


def test_library_objects_list_empty(client):
    resp = client.get('/library/objects')
    assert resp.status_code == 200
    assert resp.get_json() == []
