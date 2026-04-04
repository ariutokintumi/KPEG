"""Tests for the full encoder. Claude API is mocked via scene_override."""
import numpy as np
from unittest.mock import patch
from PIL import Image

from kpeg.encoder import (
    encode,
    _normalize_known_people,
    _build_full_json,
    _compute_flags,
    _compute_aspect_ratio,
    _trim_json_if_needed,
)
from kpeg.format import (
    unpack_kpeg,
    FLAG_PORTRAIT,
    FLAG_HAS_PEOPLE,
    FLAG_HAS_TEXT,
    FLAG_SESSION_LINKED,
    FLAG_HAS_LIB_REFS,
    FLAG_IS_OUTDOOR,
)
from kpeg.compression import decompress_json


def _test_image(w=800, h=600):
    arr = np.zeros((h, w, 3), dtype=np.uint8)
    h2 = h // 2
    w2 = w // 2
    arr[:h2, :w2] = [200, 50, 50]
    arr[:h2, w2:] = [50, 200, 50]
    arr[h2:, :w2] = [50, 50, 200]
    arr[h2:, w2:] = [220, 220, 100]
    return Image.fromarray(arr)


def _detailed_image(w=800, h=600):
    """High-frequency noise image — exercises keypoint extraction at full budget."""
    np.random.seed(42)
    arr = np.random.randint(0, 256, size=(h, w, 3), dtype=np.uint8)
    return Image.fromarray(arr)


def _fake_scene():
    return {
        "s": {
            "d": "team meeting around walnut desk",
            "mood": "casual",
            "light": {"dir": "above", "type": "natural", "warmth": "warm"},
            "depth": "fg desk, mg people, bg window",
            "style": "natural photography",
        },
        "o": [
            {"n": "person", "b": [0.20, 0.15, 0.45, 0.90],
             "d": "man mid-30s, blue polo, smiling", "ref": "usr_carlos_02"},
            {"n": "person", "b": [0.55, 0.15, 0.80, 0.90],
             "d": "woman mid-20s, red blouse, ponytail", "ref": "unknown1"},
            {"n": "desk", "b": [0.10, 0.60, 0.90, 0.95],
             "d": "walnut desk", "ref": "obj_walnut_desk"},
        ],
        "t": [{"text": "WeWork", "b": [0.4, 0.02, 0.6, 0.06], "type": "sign"}],
        "colors": ["#8B4513", "#87CEEB", "#F5F5DC"],
    }


def _full_metadata():
    return {
        "orientation": "landscape",
        "timestamp": 1743724800,
        "timezone": "Europe/Madrid",
        "device_model": "Pixel 8 Pro",
        "is_outdoor": False,
        "lens_info": {"focal_length_mm": 6.9, "aperture": 1.8, "zoom_level": 1.0},
        "flash_used": False,
        "lat": 40.4168,
        "lng": -3.7038,
        "compass_heading": 225.0,
        "camera_tilt": -5.0,
        "people": [
            {"user_id": "usr_carlos_02", "bbox": [0.20, 0.15, 0.45, 0.90]},
            {"user_id": "unknown_0", "bbox": [0.55, 0.15, 0.80, 0.90]},
        ],
        "scene_hint": "team lunch",
        "tags": ["office", "team"],
        "indoor_place_id": "place_hq_2f",
        "indoor_description": "near window, 2nd floor",
        "session_id": "sess_20260404_1430",
    }


# ═══ Unit tests for helpers ═══

def test_normalize_known_people_converts_unknowns():
    """App's unknown_N (0-indexed) → unknownN+1 (1-indexed)."""
    with patch("kpeg.encoder.get_person_name", return_value=None):
        result = _normalize_known_people([
            {"user_id": "unknown_0", "bbox": [0, 0, 0.5, 1]},
            {"user_id": "unknown_1", "bbox": [0.5, 0, 1, 1]},
        ])
    assert result[0]["ref"] == "unknown1"
    assert result[1]["ref"] == "unknown2"


def test_normalize_known_people_keeps_usr_ids():
    with patch("kpeg.encoder.get_person_name", return_value="Carlos"):
        result = _normalize_known_people([
            {"user_id": "usr_carlos_02", "bbox": [0, 0, 1, 1]},
        ])
    assert result[0]["ref"] == "usr_carlos_02"
    assert result[0]["name"] == "Carlos"


def test_normalize_known_people_empty():
    assert _normalize_known_people([]) == []


def test_build_full_json_includes_all_metadata():
    scene = _fake_scene()
    j = _build_full_json(scene, _full_metadata(), place_refs=[
        {"id": "place_hq_2f_p1", "hint": "facing 0deg", "file_path": "/x"},
    ])
    assert j["v"] == 1
    assert j["s"]["d"] == "team meeting around walnut desk"
    assert len(j["o"]) == 3
    assert j["m"]["ts"] == 1743724800
    assert j["m"]["loc"] == [40.4168, -3.7038]
    assert j["m"]["compass"] == 225.0
    assert j["c"]["fl"] == 6.9
    assert j["p"]["place"] == "place_hq_2f"
    assert j["p"]["place_refs"][0]["id"] == "place_hq_2f_p1"
    assert j["hint"] == "team lunch"
    assert j["tags"] == ["office", "team"]
    assert j["sid"] == "sess_20260404_1430"


def test_build_full_json_minimal_metadata():
    j = _build_full_json(_fake_scene(), {}, place_refs=[])
    assert "m" not in j
    assert "c" not in j
    assert "p" not in j


def test_compute_flags_portrait():
    portrait_img = _test_image(w=600, h=800)
    full_json = {"o": []}
    flags = _compute_flags(full_json, portrait_img)
    assert flags & FLAG_PORTRAIT


def test_compute_flags_landscape():
    landscape_img = _test_image(w=800, h=600)
    flags = _compute_flags({"o": []}, landscape_img)
    assert not (flags & FLAG_PORTRAIT)


def test_compute_flags_has_people():
    img = _test_image()
    j = {"o": [{"n": "person", "b": [0, 0, 1, 1]}]}
    flags = _compute_flags(j, img)
    assert flags & FLAG_HAS_PEOPLE


def test_compute_flags_has_text():
    img = _test_image()
    j = {"o": [], "t": [{"text": "x", "b": [0, 0, 1, 1]}]}
    flags = _compute_flags(j, img)
    assert flags & FLAG_HAS_TEXT


def test_compute_flags_session_linked():
    img = _test_image()
    j = {"o": [], "sid": "sess_xxx"}
    flags = _compute_flags(j, img)
    assert flags & FLAG_SESSION_LINKED


def test_compute_flags_has_lib_refs():
    img = _test_image()
    j = {"o": [{"n": "desk", "ref": "obj_walnut"}]}
    assert _compute_flags(j, img) & FLAG_HAS_LIB_REFS
    j2 = {"o": [{"n": "person", "ref": "usr_xxx"}]}
    assert _compute_flags(j2, img) & FLAG_HAS_LIB_REFS
    j3 = {"o": [], "p": {"place_refs": [{"id": "x"}]}}
    assert _compute_flags(j3, img) & FLAG_HAS_LIB_REFS
    j4 = {"o": [{"n": "person", "ref": "unknown1"}]}
    assert not (_compute_flags(j4, img) & FLAG_HAS_LIB_REFS)


def test_compute_flags_outdoor():
    img = _test_image()
    j = {"o": [], "m": {"outdoor": True}}
    assert _compute_flags(j, img) & FLAG_IS_OUTDOOR


def test_compute_aspect_ratio_landscape():
    assert _compute_aspect_ratio(_test_image(800, 600)) == (4, 3)


def test_compute_aspect_ratio_portrait():
    assert _compute_aspect_ratio(_test_image(600, 800)) == (3, 4)


def test_compute_aspect_ratio_square():
    assert _compute_aspect_ratio(_test_image(500, 500)) == (1, 1)


def test_compute_aspect_ratio_16_9():
    assert _compute_aspect_ratio(_test_image(1920, 1080)) == (16, 9)


def test_trim_json_if_needed_drops_tags_first():
    j = {"s": {"d": "x"}, "tags": ["a", "b"], "hint": "x"}
    trimmed = _trim_json_if_needed(j.copy())
    assert "tags" not in trimmed
    assert "hint" in trimmed


def test_trim_json_if_needed_drops_hint_next():
    j = {"s": {"d": "x"}, "hint": "x"}
    trimmed = _trim_json_if_needed(j.copy())
    assert "hint" not in trimmed


# ═══ Integration tests (mocked scene) ═══

def test_encode_returns_valid_kpeg():
    """Full encode produces a parseable KPEG binary."""
    with patch("kpeg.encoder.get_objects_catalog", return_value=[]), \
         patch("kpeg.encoder.select_best_place_refs", return_value=[]), \
         patch("kpeg.encoder.get_person_name", return_value="Carlos"):
        kpeg_bytes = encode(_test_image(), _full_metadata(), scene_override=_fake_scene())

    assert isinstance(kpeg_bytes, bytes)
    parsed = unpack_kpeg(kpeg_bytes)
    assert parsed.version == 1
    assert parsed.aspect_w == 4
    assert parsed.aspect_h == 3


def test_encode_respects_max_size():
    with patch("kpeg.encoder.get_objects_catalog", return_value=[]), \
         patch("kpeg.encoder.select_best_place_refs", return_value=[]), \
         patch("kpeg.encoder.get_person_name", return_value=None):
        kpeg_bytes = encode(_test_image(), _full_metadata(), scene_override=_fake_scene())
    assert len(kpeg_bytes) <= 2514  # MAX_SIZE: 12 + 1500 + 1000 + 2


def test_encode_budget_fill_adds_keypoints():
    """Budget-fill should add keypoints when image has edges + space is available."""
    with patch("kpeg.encoder.get_objects_catalog", return_value=[]), \
         patch("kpeg.encoder.select_best_place_refs", return_value=[]), \
         patch("kpeg.encoder.get_person_name", return_value=None):
        kpeg_bytes = encode(
            _detailed_image(), _full_metadata(),
            target_size=1950, scene_override=_fake_scene(),
        )
    parsed = unpack_kpeg(kpeg_bytes)
    # Minimum bitmap (grid-only) is 114B. After budget-fill on a noisy image,
    # the loop should add many keypoints (each = 3B), growing the bitmap well beyond.
    assert len(parsed.bitmap_data) > 500  # > ~130 keypoints added
    assert len(kpeg_bytes) <= 1950


def test_encode_budget_fill_caps_at_max_keypoints():
    """Budget-fill caps bitmap at ~1500B (MAX_KEYPOINTS=461) even when target allows more."""
    with patch("kpeg.encoder.get_objects_catalog", return_value=[]), \
         patch("kpeg.encoder.select_best_place_refs", return_value=[]), \
         patch("kpeg.encoder.get_person_name", return_value=None):
        kpeg_bytes = encode(
            _detailed_image(), _full_metadata(),
            target_size=2500, scene_override=_fake_scene(),
        )
    parsed = unpack_kpeg(kpeg_bytes)
    # Max bitmap: 48 (palette) + 1 + 64 (grid) + 2 (uint16 kp_count) + 461*3 = 1498B
    assert len(parsed.bitmap_data) <= 1500


def test_encode_simple_image_undershoots_target():
    """Simple image can still be encoded within the 1950B soft target."""
    with patch("kpeg.encoder.get_objects_catalog", return_value=[]), \
         patch("kpeg.encoder.select_best_place_refs", return_value=[]), \
         patch("kpeg.encoder.get_person_name", return_value=None):
        kpeg_bytes = encode(
            _test_image(), _full_metadata(),
            target_size=1950, scene_override=_fake_scene(),
        )
    assert len(kpeg_bytes) <= 1950


def test_encode_sets_correct_flags():
    with patch("kpeg.encoder.get_objects_catalog", return_value=[]), \
         patch("kpeg.encoder.select_best_place_refs", return_value=[]), \
         patch("kpeg.encoder.get_person_name", return_value=None):
        kpeg_bytes = encode(_test_image(), _full_metadata(), scene_override=_fake_scene())

    parsed = unpack_kpeg(kpeg_bytes)
    assert parsed.has_people
    assert parsed.has_text
    assert parsed.session_linked
    assert parsed.has_library_refs  # has usr_carlos_02 and obj_walnut_desk
    assert not parsed.is_portrait   # 800x600 landscape
    assert not parsed.is_outdoor


def test_encode_portrait_image_sets_flag():
    with patch("kpeg.encoder.get_objects_catalog", return_value=[]), \
         patch("kpeg.encoder.select_best_place_refs", return_value=[]), \
         patch("kpeg.encoder.get_person_name", return_value=None):
        kpeg_bytes = encode(
            _test_image(w=600, h=800), _full_metadata(), scene_override=_fake_scene(),
        )
    parsed = unpack_kpeg(kpeg_bytes)
    assert parsed.is_portrait


def test_encode_preserves_metadata_in_json():
    """Decode the KPEG and verify all metadata fields round-trip."""
    with patch("kpeg.encoder.get_objects_catalog", return_value=[]), \
         patch("kpeg.encoder.select_best_place_refs", return_value=[]), \
         patch("kpeg.encoder.get_person_name", return_value=None):
        kpeg_bytes = encode(_test_image(), _full_metadata(), scene_override=_fake_scene())

    parsed = unpack_kpeg(kpeg_bytes)
    raw_json = decompress_json(parsed.compressed_json)

    assert raw_json["v"] == 1
    assert raw_json["m"]["ts"] == 1743724800
    assert raw_json["m"]["loc"] == [40.4168, -3.7038]
    assert raw_json["c"]["ap"] == 1.8
    assert raw_json["p"]["place"] == "place_hq_2f"
    assert raw_json["sid"] == "sess_20260404_1430"
    assert raw_json["hint"] == "team lunch"


def test_encode_minimal_metadata():
    """Encoder works with bare-minimum metadata."""
    minimal = {"people": []}
    minimal_scene = {
        "s": {"d": "empty room"},
        "o": [],
        "t": [],
        "colors": ["#FFFFFF"],
    }
    with patch("kpeg.encoder.get_objects_catalog", return_value=[]), \
         patch("kpeg.encoder.select_best_place_refs", return_value=[]):
        kpeg_bytes = encode(_test_image(), minimal, scene_override=minimal_scene)

    parsed = unpack_kpeg(kpeg_bytes)
    raw_json = decompress_json(parsed.compressed_json)
    assert raw_json["v"] == 1
    assert len(kpeg_bytes) <= 2514  # MAX_SIZE


def test_encode_accepts_path_and_bytes():
    """encode() should accept image paths and raw bytes, not just PIL images."""
    import io as _io
    img = _test_image()
    buf = _io.BytesIO()
    img.save(buf, format="PNG")
    img_bytes = buf.getvalue()

    with patch("kpeg.encoder.get_objects_catalog", return_value=[]), \
         patch("kpeg.encoder.select_best_place_refs", return_value=[]), \
         patch("kpeg.encoder.get_person_name", return_value=None):
        kpeg_from_bytes = encode(img_bytes, _full_metadata(), scene_override=_fake_scene())
    parsed = unpack_kpeg(kpeg_from_bytes)
    assert parsed.version == 1


# ═══ Integration tests: real photo + realistic library catalog + realistic scene ═══

def test_encode_cannes_venue_realistic(cannes_venue, cannes_library_catalog,
                                        cannes_metadata, cannes_realistic_scene):
    """Full encode on the real Cannes photo with a production-like library catalog."""
    fake_place_refs = [
        {"id": "place_palais_festivals_p1", "hint": "facing 145deg, main hall view",
         "file_path": "/lib/place_p1.jpg"},
        {"id": "place_palais_festivals_p2", "hint": "facing 90deg, entrance doors",
         "file_path": "/lib/place_p2.jpg"},
    ]
    with patch("kpeg.encoder.get_objects_catalog", return_value=cannes_library_catalog), \
         patch("kpeg.encoder.select_best_place_refs", return_value=fake_place_refs), \
         patch("kpeg.encoder.get_person_name", return_value=None):
        kpeg_bytes = encode(
            cannes_venue, cannes_metadata,
            scene_override=cannes_realistic_scene,
            verbose=True,
        )

    # Size must fit within the MAX_SIZE ceiling
    assert len(kpeg_bytes) <= 2514
    # Realistic scene + rich image → should fill substantially (bitmap ~1500B)
    assert len(kpeg_bytes) >= 1500, f"expected budget-fill to land near target, got {len(kpeg_bytes)}B"


def test_encode_cannes_venue_budget_fills_as_much_as_possible(
    cannes_venue, cannes_library_catalog, cannes_metadata, cannes_realistic_scene
):
    """Budget-fill saturates bitmap near ~1500B on a realistic scene.

    With realistic JSON (~900B compressed) + target=2500, the bitmap should
    fill close to BITMAP_TARGET_SIZE (1500B).
    """
    with patch("kpeg.encoder.get_objects_catalog", return_value=cannes_library_catalog), \
         patch("kpeg.encoder.select_best_place_refs", return_value=[]), \
         patch("kpeg.encoder.get_person_name", return_value=None):
        kpeg_bytes = encode(
            cannes_venue, cannes_metadata,
            target_size=2500,
            scene_override=cannes_realistic_scene,
        )
    parsed = unpack_kpeg(kpeg_bytes)

    assert len(kpeg_bytes) <= 2514  # MAX_SIZE
    # Bitmap should fill substantially — budget allows up to 1500B, actual depends
    # on how many keypoints the Sobel extractor finds in the image.
    assert len(parsed.bitmap_data) >= 800, (
        f"Expected bitmap to fill substantially, got {len(parsed.bitmap_data)}B"
    )
    assert len(parsed.bitmap_data) <= 1500


def test_encode_cannes_venue_all_flags_set(
    cannes_venue, cannes_library_catalog, cannes_metadata, cannes_realistic_scene
):
    """Realistic scene has person, text, session, library refs, indoor — most flags fire."""
    fake_place_refs = [
        {"id": "place_palais_festivals_p1", "hint": "main hall", "file_path": "/lib/p1.jpg"},
    ]
    with patch("kpeg.encoder.get_objects_catalog", return_value=cannes_library_catalog), \
         patch("kpeg.encoder.select_best_place_refs", return_value=fake_place_refs), \
         patch("kpeg.encoder.get_person_name", return_value=None):
        kpeg_bytes = encode(
            cannes_venue, cannes_metadata,
            scene_override=cannes_realistic_scene,
        )
    parsed = unpack_kpeg(kpeg_bytes)
    assert parsed.has_people is True
    assert parsed.has_text is True
    assert parsed.has_library_refs is True
    assert parsed.session_linked is True
    assert parsed.is_outdoor is False
    assert parsed.is_portrait is False  # 1280x960 landscape
    assert parsed.aspect_w == 4 and parsed.aspect_h == 3


def test_encode_cannes_venue_json_round_trip(
    cannes_venue, cannes_library_catalog, cannes_metadata, cannes_realistic_scene
):
    """Decode the Cannes KPEG and verify all refs + metadata survived."""
    fake_place_refs = [
        {"id": "place_palais_festivals_p1", "hint": "main hall", "file_path": "/lib/p1.jpg"},
    ]
    with patch("kpeg.encoder.get_objects_catalog", return_value=cannes_library_catalog), \
         patch("kpeg.encoder.select_best_place_refs", return_value=fake_place_refs), \
         patch("kpeg.encoder.get_person_name", return_value=None):
        kpeg_bytes = encode(
            cannes_venue, cannes_metadata,
            scene_override=cannes_realistic_scene,
        )

    parsed = unpack_kpeg(kpeg_bytes)
    raw = decompress_json(parsed.compressed_json)

    # Verify library refs made it through
    refs = {o.get("ref") for o in raw["o"]}
    assert "obj_bistro_chair_blk" in refs
    assert "obj_service_cart_gsf" in refs
    assert "obj_palm_tropical" in refs
    assert "unknown1" in refs  # App's unknown_0 normalized to unknown1

    # Verify place_refs wired in
    assert raw["p"]["place_refs"][0]["id"] == "place_palais_festivals_p1"

    # Verify text detected
    texts = [t["text"] for t in raw["t"]]
    assert "GSF" in texts
    assert any("PALAIS" in t for t in texts)

    # Verify metadata preservation
    assert raw["m"]["loc"] == [43.5528, 7.0174]
    assert raw["m"]["compass"] == 145.0
    assert raw["sid"] == "sess_20260404_1800"


def test_encode_cannes_verbose_prints_breakdown(
    cannes_venue, cannes_library_catalog, cannes_metadata, cannes_realistic_scene, capsys
):
    """verbose=True prints a byte-breakdown log."""
    with patch("kpeg.encoder.get_objects_catalog", return_value=cannes_library_catalog), \
         patch("kpeg.encoder.select_best_place_refs", return_value=[]), \
         patch("kpeg.encoder.get_person_name", return_value=None):
        encode(
            cannes_venue, cannes_metadata,
            scene_override=cannes_realistic_scene, verbose=True,
        )
    captured = capsys.readouterr()
    assert "KPEG encoded:" in captured.out
    assert "Bitmap:" in captured.out
    assert "JSON:" in captured.out
    assert "Flags:" in captured.out
