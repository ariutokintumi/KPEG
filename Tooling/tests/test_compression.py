"""Tests for Brotli JSON compression."""
from kpeg.compression import compress_json, decompress_json, estimate_compressed_size


def test_round_trip_simple():
    """Simple dict compresses + decompresses losslessly."""
    data = {"hello": "world", "n": 42, "arr": [1, 2, 3]}
    compressed = compress_json(data)
    assert isinstance(compressed, bytes)
    decoded = decompress_json(compressed)
    assert decoded == data


def test_round_trip_unicode():
    """Non-ASCII strings preserved (ensure_ascii=False)."""
    data = {"name": "José María", "city": "Madrid", "emoji": "camera"}
    compressed = compress_json(data)
    decoded = decompress_json(compressed)
    assert decoded == data


def test_round_trip_nested():
    """Nested dicts and lists round-trip correctly."""
    data = {
        "v": 1,
        "s": {"d": "scene", "mood": "warm"},
        "o": [
            {"n": "person", "b": [0.1, 0.2, 0.3, 0.4], "ref": "usr_01"},
            {"n": "desk", "b": [0.0, 0.5, 1.0, 1.0]},
        ],
    }
    compressed = compress_json(data)
    decoded = decompress_json(compressed)
    assert decoded == data


def test_compression_is_compact():
    """Compact JSON is used (no whitespace)."""
    data = {"a": 1, "b": 2}
    compressed = compress_json(data)
    # Compressed output should be smaller than pretty-printed JSON
    import json as json_lib
    pretty = json_lib.dumps(data, indent=2).encode("utf-8")
    assert len(compressed) < len(pretty)


def test_compression_reduces_repetitive():
    """Brotli should aggressively compress repetitive content."""
    data = {"text": "hello " * 500}
    compressed = compress_json(data)
    raw = str(data).encode("utf-8")
    ratio = len(compressed) / len(raw)
    assert ratio < 0.1  # Better than 10:1 on repetitive text


def test_estimate_matches_actual():
    """estimate_compressed_size returns exact length of compress_json."""
    data = {"test": "data", "num": [1, 2, 3, 4, 5]}
    estimated = estimate_compressed_size(data)
    actual = len(compress_json(data))
    assert estimated == actual


def test_realistic_kpeg_scene_fits():
    """A realistic KPEG scene JSON compresses well under 1200 bytes."""
    data = {
        "v": 1,
        "s": {
            "d": "Three people in a meeting room, walnut desk, window light",
            "mood": "professional",
            "light": {"dir": "above-left", "type": "natural", "warmth": "warm"},
        },
        "o": [
            {"n": "person", "b": [0.20, 0.15, 0.45, 0.90],
             "d": "man mid-30s, short beard, blue cap, smiling", "ref": "usr_carlos_02"},
            {"n": "person", "b": [0.55, 0.12, 0.78, 0.88],
             "d": "woman mid-20s, dark ponytail, red blouse", "ref": "unknown1"},
            {"n": "desk", "b": [0.10, 0.60, 0.90, 0.95], "d": "walnut"},
        ],
        "p": {"place": "place_hq_2f", "indoor": "meeting room"},
        "colors": ["#8B4513", "#87CEEB", "#F5F5DC"],
        "tags": ["office", "team"],
    }
    compressed = compress_json(data)
    assert len(compressed) < 1200
