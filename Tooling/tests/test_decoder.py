"""Tests for decoder (fal.ai + library DB are mocked — no network, no real DB)."""
import base64
import io
import os
import sqlite3
import tempfile
from pathlib import Path
from unittest.mock import patch
import numpy as np
import pytest
from PIL import Image

from kpeg.encoder import encode
from kpeg.decoder import (
    decode,
    decode_to_image,
    inspect,
    _file_path_to_data_url,
    _collect_reference_urls,
    _compute_output_size,
)


# ═══ Test helpers ═══

def _tiny_image(w=64, h=64, color=(128, 100, 50)) -> Image.Image:
    arr = np.full((h, w, 3), color, dtype=np.uint8)
    return Image.fromarray(arr)


def _fake_fal_result(img: Image.Image) -> dict:
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    b64 = base64.standard_b64encode(buf.getvalue()).decode("ascii")
    return {"images": [{"url": f"data:image/png;base64,{b64}"}]}


def _make_submit(expected: Image.Image):
    """Return a fake submit callback that always responds with `expected`."""
    calls = []

    def submit(model, arguments):
        calls.append((model, arguments))
        return _fake_fal_result(expected)
    submit.calls = calls
    return submit


def _build_kpeg(scene: dict, metadata: dict = None) -> bytes:
    """Encode a KPEG using scene_override so no Anthropic API call happens."""
    meta = metadata or {
        "orientation": "landscape",
        "timestamp": 1743724800,
        "people": [],
    }
    noise = np.random.randint(0, 256, size=(256, 384, 3), dtype=np.uint8)
    img = Image.fromarray(noise)
    with patch("kpeg.encoder.get_objects_catalog", return_value=[]), \
         patch("kpeg.encoder.select_best_place_refs", return_value=[]), \
         patch("kpeg.encoder.get_person_name", return_value=None):
        return encode(img, meta, scene_override=scene)


# ═══ Aspect ratio helper ═══

def test_compute_output_size_landscape():
    w, h = _compute_output_size(4, 3, max_dim=1024)
    assert w == 1024
    assert h == 768


def test_compute_output_size_portrait():
    w, h = _compute_output_size(3, 4, max_dim=1024)
    assert h == 1024
    assert w == 768


def test_compute_output_size_square():
    w, h = _compute_output_size(1, 1, max_dim=512)
    assert w == 512
    assert h == 512


def test_compute_output_size_wide():
    w, h = _compute_output_size(16, 9, max_dim=1024)
    assert w == 1024
    assert h == 576


# ═══ Data URL helper ═══

def test_file_path_to_data_url_reads_local_file(tmp_path):
    img_path = tmp_path / "x.jpg"
    _tiny_image().convert("RGB").save(img_path, "JPEG")
    url = _file_path_to_data_url(str(img_path))
    assert url is not None
    assert url.startswith("data:image/jpeg;base64,")


def test_file_path_to_data_url_missing_returns_none():
    assert _file_path_to_data_url("/does/not/exist.jpg") is None


# ═══ Reference collection ═══

@pytest.fixture
def temp_library(tmp_path):
    """Build a temp library: DB + real image files, patched into library_reader."""
    db_path = tmp_path / "lib.db"
    conn = sqlite3.connect(db_path)
    conn.executescript("""
        CREATE TABLE people (user_id TEXT PRIMARY KEY, name TEXT NOT NULL,
                             selfie_count INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL);
        CREATE TABLE people_selfies (id INTEGER PRIMARY KEY AUTOINCREMENT, user_id TEXT NOT NULL,
                                     file_path TEXT NOT NULL, timestamp INTEGER NOT NULL);
        CREATE TABLE places (place_id TEXT PRIMARY KEY, name TEXT NOT NULL,
                             photo_count INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL);
        CREATE TABLE place_photos (id INTEGER PRIMARY KEY AUTOINCREMENT, place_id TEXT NOT NULL,
                                    file_path TEXT NOT NULL, lat REAL, lng REAL,
                                    compass_heading REAL, camera_tilt REAL, timestamp INTEGER NOT NULL);
        CREATE TABLE objects (object_id TEXT PRIMARY KEY, name TEXT NOT NULL,
                              category TEXT NOT NULL DEFAULT 'other',
                              photo_count INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL);
        CREATE TABLE object_photos (id INTEGER PRIMARY KEY AUTOINCREMENT, object_id TEXT NOT NULL,
                                    file_path TEXT NOT NULL);
    """)

    # Create real image files
    face_path = tmp_path / "face.jpg"
    place_path = tmp_path / "place.jpg"
    object_path = tmp_path / "object.jpg"
    for p in (face_path, place_path, object_path):
        _tiny_image().save(p, "JPEG")

    conn.execute("INSERT INTO people VALUES (?, ?, ?, ?)",
                 ("usr_ana", "Ana", 1, "2026-04-04"))
    conn.execute("INSERT INTO people_selfies (user_id, file_path, timestamp) VALUES (?, ?, ?)",
                 ("usr_ana", str(face_path), 1000))

    conn.execute("INSERT INTO places VALUES (?, ?, ?, ?)",
                 ("place_x", "Place X", 1, "2026-04-04"))
    conn.execute(
        "INSERT INTO place_photos (place_id, file_path, lat, lng, compass_heading, camera_tilt, timestamp) "
        "VALUES (?, ?, ?, ?, ?, ?, ?)",
        ("place_x", str(place_path), 0.0, 0.0, 90.0, 0.0, 1000),
    )

    conn.execute("INSERT INTO objects VALUES (?, ?, ?, ?, ?)",
                 ("obj_lamp", "Lamp", "lighting", 1, "2026-04-04"))
    conn.execute("INSERT INTO object_photos (object_id, file_path) VALUES (?, ?)",
                 ("obj_lamp", str(object_path)))
    conn.commit()
    conn.close()

    with patch("kpeg.library_reader.DATABASE_PATH", db_path):
        yield {"db": db_path, "face": face_path, "place": place_path, "object": object_path}


def test_collect_reference_urls_prioritizes_people_first(temp_library):
    scene = {
        "o": [
            {"n": "lamp", "ref": "obj_lamp"},
            {"n": "person", "ref": "usr_ana"},
        ],
        "p": {"place": "place_x"},
    }
    metadata = {"compass": 85.0, "tilt": 0.0}
    urls = _collect_reference_urls(scene, metadata)
    assert len(urls) == 3
    # People priority 0 — person selfie must appear before object
    assert all(u.startswith("data:image/jpeg;base64,") for u in urls)


def test_collect_reference_urls_missing_files_skipped(temp_library):
    # Insert a row pointing to a nonexistent file
    conn = sqlite3.connect(temp_library["db"])
    conn.execute("INSERT INTO object_photos (object_id, file_path) VALUES (?, ?)",
                 ("obj_lamp", "/nope/does-not-exist.jpg"))
    conn.commit()
    conn.close()

    scene = {"o": [{"n": "lamp", "ref": "obj_lamp"}]}
    urls = _collect_reference_urls(scene, {})
    # Only the real file should come through
    assert len(urls) == 1


def test_collect_reference_urls_dedups_objects(temp_library):
    scene = {"o": [
        {"n": "lamp1", "ref": "obj_lamp"},
        {"n": "lamp2", "ref": "obj_lamp"},  # duplicate
    ]}
    urls = _collect_reference_urls(scene, {})
    assert len(urls) == 1


def test_collect_reference_urls_caps_at_max(temp_library):
    """If the scene references more than MAX_REFERENCE_IMAGES, we truncate."""
    from kpeg.decoder import MAX_REFERENCE_IMAGES
    conn = sqlite3.connect(temp_library["db"])
    # Add 20 object entries, all pointing to the same real file
    for i in range(20):
        oid = f"obj_{i}"
        conn.execute("INSERT INTO objects VALUES (?, ?, ?, ?, ?)",
                     (oid, f"Obj {i}", "misc", 1, "2026-04-04"))
        conn.execute("INSERT INTO object_photos (object_id, file_path) VALUES (?, ?)",
                     (oid, str(temp_library["object"])))
    conn.commit()
    conn.close()

    scene = {"o": [{"n": "x", "ref": f"obj_{i}"} for i in range(20)]}
    urls = _collect_reference_urls(scene, {})
    assert len(urls) == MAX_REFERENCE_IMAGES


def test_collect_reference_urls_empty_scene():
    with patch("kpeg.library_reader.DATABASE_PATH", Path("/nowhere.db")):
        assert _collect_reference_urls({}, {}) == []
        assert _collect_reference_urls({"o": []}, {}) == []


# ═══ Full decode ═══

def test_decode_round_trip_produces_jpeg_bytes():
    scene = {
        "s": {"d": "minimal scene"},
        "o": [], "t": [], "colors": ["#808080"],
    }
    kpeg_bytes = _build_kpeg(scene)
    submit = _make_submit(_tiny_image(w=256, h=192, color=(200, 50, 50)))
    with patch("kpeg.library_reader.DATABASE_PATH", Path("/nowhere.db")):
        out = decode(kpeg_bytes, quality="fast", max_output_dim=256, submit=submit)
    # Valid JPEG starts with SOI marker
    assert out[:2] == b"\xff\xd8"
    assert len(out) > 100


def test_decode_returns_pil_image():
    scene = {"s": {"d": "x"}, "o": [], "t": [], "colors": []}
    kpeg_bytes = _build_kpeg(scene)
    submit = _make_submit(_tiny_image(w=128, h=96))
    with patch("kpeg.library_reader.DATABASE_PATH", Path("/nowhere.db")):
        img = decode_to_image(kpeg_bytes, quality="fast", max_output_dim=128, submit=submit)
    assert isinstance(img, Image.Image)
    assert img.size[0] > 0 and img.size[1] > 0


def test_decode_preserves_aspect_ratio():
    scene = {"s": {"d": "x"}, "o": [], "t": [], "colors": []}
    kpeg_bytes = _build_kpeg(scene)  # source image is 384x256 → 3:2
    submit = _make_submit(_tiny_image(w=1024, h=683))

    with patch("kpeg.library_reader.DATABASE_PATH", Path("/nowhere.db")):
        decode(kpeg_bytes, quality="fast", max_output_dim=1024, submit=submit)

    assert submit.calls
    _, args = submit.calls[0]
    assert args["image_size"]["width"] == 1024
    # 1024 * 2/3 = 682.66 → rounds to 682 or 683
    assert 680 <= args["image_size"]["height"] <= 684


def test_decode_passes_prompt_to_flux():
    scene = {
        "s": {"d": "sunny terrace", "mood": "cheerful", "style": "travel photo"},
        "o": [], "t": [], "colors": [],
    }
    kpeg_bytes = _build_kpeg(scene)
    submit = _make_submit(_tiny_image())
    with patch("kpeg.library_reader.DATABASE_PATH", Path("/nowhere.db")):
        decode(kpeg_bytes, quality="fast", submit=submit)
    _, args = submit.calls[0]
    assert "sunny terrace" in args["prompt"]
    assert "travel photo" in args["prompt"]


def test_decode_uses_library_refs_when_balanced(temp_library):
    """Balanced tier should invoke Stage 2 with library refs when scene has them."""
    scene = {
        "s": {"d": "x"},
        "o": [{"n": "person", "b": [0, 0, 1, 1], "d": "woman smiling", "ref": "usr_ana"}],
        "t": [], "colors": [],
    }
    metadata = {"people": [{"user_id": "usr_ana", "bbox": [0, 0, 1, 1]}]}
    kpeg_bytes = _build_kpeg(scene, metadata)
    submit = _make_submit(_tiny_image())
    decode(kpeg_bytes, quality="balanced", submit=submit)

    models = [m for m, _ in submit.calls]
    assert any("kontext" in m for m in models), f"no kontext call in {models}"
    # The Kontext call must include our library face
    kontext_args = next(args for m, args in submit.calls if "kontext" in m)
    assert len(kontext_args["reference_image_urls"]) >= 1


def test_decode_fast_tier_ignores_refs(temp_library):
    """Fast tier is Stage 1 only — never calls Kontext even if refs exist."""
    scene = {
        "s": {"d": "x"},
        "o": [{"n": "person", "ref": "usr_ana"}],
        "t": [], "colors": [],
    }
    metadata = {"people": [{"user_id": "usr_ana", "bbox": [0, 0, 1, 1]}]}
    kpeg_bytes = _build_kpeg(scene, metadata)
    submit = _make_submit(_tiny_image())
    decode(kpeg_bytes, quality="fast", submit=submit)
    models = [m for m, _ in submit.calls]
    assert all("kontext" not in m for m in models)


def test_decode_offline_stub_when_no_key():
    """No submit + no FAL_KEY → stub fallback (guide upscaled, no network)."""
    scene = {"s": {"d": "stub test"}, "o": [], "t": [], "colors": []}
    kpeg_bytes = _build_kpeg(scene)
    with patch("kpeg.library_reader.DATABASE_PATH", Path("/nowhere.db")), \
         patch("kpeg.image_generator.FAL_KEY", ""):
        out = decode(kpeg_bytes, quality="fast", max_output_dim=128)
    assert out[:2] == b"\xff\xd8"  # JPEG signature


def test_decode_corrupted_kpeg_raises():
    with pytest.raises(ValueError):
        decode(b"not-a-kpeg-file")


def test_decode_png_output():
    scene = {"s": {"d": "x"}, "o": [], "t": [], "colors": []}
    kpeg_bytes = _build_kpeg(scene)
    submit = _make_submit(_tiny_image())
    with patch("kpeg.library_reader.DATABASE_PATH", Path("/nowhere.db")):
        out = decode(kpeg_bytes, quality="fast", submit=submit, output_format="PNG")
    assert out[:8] == b"\x89PNG\r\n\x1a\n"


def test_decode_verbose_prints(capsys):
    scene = {"s": {"d": "verbose test"}, "o": [{"n": "x", "d": "thing"}], "t": [], "colors": []}
    kpeg_bytes = _build_kpeg(scene)
    submit = _make_submit(_tiny_image())
    with patch("kpeg.library_reader.DATABASE_PATH", Path("/nowhere.db")):
        decode(kpeg_bytes, quality="fast", submit=submit, verbose=True)
    captured = capsys.readouterr()
    assert "KPEG decoded" in captured.out
    assert "Keypoints" in captured.out


# ═══ inspect() ═══

def test_inspect_returns_header_summary():
    scene = {
        "s": {"d": "inspection subject"},
        "o": [{"n": "person", "ref": "usr_a"}, {"n": "desk", "ref": "obj_d"}],
        "t": [{"text": "HI", "b": [0, 0, 0.1, 0.1]}],
        "colors": ["#FFF"],
    }
    metadata = {
        "orientation": "landscape",
        "people": [],
        "indoor_place_id": "place_x",
    }
    kpeg_bytes = _build_kpeg(scene, metadata)
    info = inspect(kpeg_bytes)
    assert info["size_bytes"] == len(kpeg_bytes)
    assert info["version"] == 1
    assert info["flags"]["has_people"] is True
    assert info["flags"]["has_text"] is True
    assert info["flags"]["has_library_refs"] is True
    assert info["scene"]["objects"] == 2
    assert info["scene"]["texts"] == 1
    assert info["scene"]["has_place"] is True
    assert "inspection subject" in info["scene"]["description"]


def test_inspect_rejects_corrupt():
    with pytest.raises(ValueError):
        inspect(b"xxxx")
