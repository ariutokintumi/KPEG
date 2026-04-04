"""Tests for KPEG binary container format."""
import pytest
from kpeg.format import (
    pack_kpeg,
    unpack_kpeg,
    crc16,
    compute_total_size,
    repack_with_new_json,
    FLAG_PORTRAIT,
    FLAG_HAS_PEOPLE,
    FLAG_HAS_LIB_REFS,
)
from kpeg import MAGIC_BYTES, FORMAT_VERSION, HEADER_SIZE, CRC_SIZE


def test_crc16_known_value():
    """CRC-16-CCITT of '123456789' = 0x29B1 (standard test vector)."""
    assert crc16(b"123456789") == 0x29B1


def test_crc16_empty():
    """Empty input returns the init value."""
    assert crc16(b"") == 0xFFFF


def test_pack_unpack_round_trip():
    """Pack then unpack should preserve all data."""
    bitmap = b"\x01\x02\x03\x04" * 100  # 400 bytes
    compressed_json = b"\xFF\xEE\xDD" * 200  # 600 bytes
    flags = FLAG_PORTRAIT | FLAG_HAS_PEOPLE | FLAG_HAS_LIB_REFS
    packed = pack_kpeg(bitmap, compressed_json, flags=flags, aspect_w=3, aspect_h=4)

    assert len(packed) == HEADER_SIZE + len(bitmap) + len(compressed_json) + CRC_SIZE
    assert packed[:4] == MAGIC_BYTES

    parsed = unpack_kpeg(packed)
    assert parsed.version == FORMAT_VERSION
    assert parsed.flags == flags
    assert parsed.aspect_w == 3
    assert parsed.aspect_h == 4
    assert parsed.bitmap_data == bitmap
    assert parsed.compressed_json == compressed_json
    assert parsed.is_portrait is True
    assert parsed.has_people is True
    assert parsed.has_library_refs is True
    assert parsed.is_outdoor is False


def test_pack_empty_payloads():
    """Packing empty bitmap + JSON should still produce valid file."""
    packed = pack_kpeg(b"", b"", flags=0, aspect_w=1, aspect_h=1)
    parsed = unpack_kpeg(packed)
    assert parsed.bitmap_data == b""
    assert parsed.compressed_json == b""


def test_unpack_corrupted_crc():
    """Tampered file should fail CRC check."""
    packed = pack_kpeg(b"hello", b"world", flags=0)
    tampered = packed[:-2] + b"\x00\x00"  # Overwrite CRC
    with pytest.raises(ValueError, match="CRC mismatch"):
        unpack_kpeg(tampered)


def test_unpack_bad_magic():
    """Wrong magic bytes should fail."""
    packed = pack_kpeg(b"x", b"y", flags=0)
    tampered = b"FAKE" + packed[4:]
    # Tampering with header breaks CRC first, but test with recomputed CRC:
    body = b"FAKE" + packed[4:-2]
    new_crc = crc16(body)
    import struct
    tampered = body + struct.pack("<H", new_crc)
    with pytest.raises(ValueError, match="Invalid magic"):
        unpack_kpeg(tampered)


def test_unpack_too_small():
    """File below minimum size should fail."""
    with pytest.raises(ValueError, match="File too small"):
        unpack_kpeg(b"KPEG\x01")


def test_compute_total_size():
    """Total size formula: HEADER + bitmap + json + CRC."""
    assert compute_total_size(400, 900) == HEADER_SIZE + 400 + 900 + CRC_SIZE
    assert compute_total_size(0, 0) == HEADER_SIZE + CRC_SIZE


def test_bitmap_too_large():
    """Bitmap > 65535 bytes should be rejected."""
    with pytest.raises(ValueError, match="Bitmap too large"):
        pack_kpeg(b"x" * 65536, b"", flags=0)


def test_repack_with_new_json():
    """repack_with_new_json preserves bitmap + flags, swaps JSON."""
    bitmap = b"\xAA" * 50
    original_json = b"\x11\x22\x33"
    new_json = b"\x44\x55\x66\x77\x88"

    original = pack_kpeg(bitmap, original_json, flags=FLAG_PORTRAIT, aspect_w=9, aspect_h=16)
    repacked = repack_with_new_json(original, new_json)

    parsed = unpack_kpeg(repacked)
    assert parsed.bitmap_data == bitmap
    assert parsed.compressed_json == new_json
    assert parsed.flags == FLAG_PORTRAIT
    assert parsed.aspect_w == 9
    assert parsed.aspect_h == 16


def test_realistic_kpeg_size_under_budget():
    """A realistic KPEG (400B bitmap + 900B JSON) fits in 2048 budget."""
    bitmap = b"\x00" * 400
    compressed_json = b"\x00" * 900
    packed = pack_kpeg(bitmap, compressed_json, flags=0)
    assert len(packed) == 1314
    assert len(packed) <= 2048
