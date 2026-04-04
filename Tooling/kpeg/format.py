"""KPEG binary container format: pack/unpack.

File layout (total <= 2048 bytes):
  0-3    Magic "KPEG" (0x4B504547)
  4      Version (0x01)
  5      Flags (bitfield)
  6-7    Bitmap length (uint16 LE)
  8-9    JSON length (uint16 LE)
  10     Aspect ratio width (uint8)
  11     Aspect ratio height (uint8)
  12..N  Bitmap data (adaptive, grid + keypoints)
  N..M   Brotli-compressed JSON
  last 2 CRC-16 of all preceding bytes
"""
import struct
from dataclasses import dataclass

from . import MAGIC_BYTES, FORMAT_VERSION, HEADER_SIZE, CRC_SIZE


# Flag bit positions
FLAG_PORTRAIT = 0x01         # bit 0: 0=landscape, 1=portrait
FLAG_HAS_LIB_REFS = 0x02     # bit 1
FLAG_HAS_PEOPLE = 0x04       # bit 2
FLAG_IS_OUTDOOR = 0x08       # bit 3
FLAG_HAS_TEXT = 0x10         # bit 4
FLAG_SESSION_LINKED = 0x20   # bit 5
FLAG_ENCRYPTED = 0x40        # bit 6 (future)
# bit 7 reserved


@dataclass
class KPEGFile:
    """Decoded KPEG container."""
    version: int
    flags: int
    aspect_w: int
    aspect_h: int
    bitmap_data: bytes
    compressed_json: bytes

    @property
    def is_portrait(self) -> bool:
        return bool(self.flags & FLAG_PORTRAIT)

    @property
    def has_library_refs(self) -> bool:
        return bool(self.flags & FLAG_HAS_LIB_REFS)

    @property
    def has_people(self) -> bool:
        return bool(self.flags & FLAG_HAS_PEOPLE)

    @property
    def is_outdoor(self) -> bool:
        return bool(self.flags & FLAG_IS_OUTDOOR)

    @property
    def has_text(self) -> bool:
        return bool(self.flags & FLAG_HAS_TEXT)

    @property
    def session_linked(self) -> bool:
        return bool(self.flags & FLAG_SESSION_LINKED)


def crc16(data: bytes, poly: int = 0x1021, init: int = 0xFFFF) -> int:
    """CRC-16-CCITT checksum (XMODEM variant)."""
    crc = init
    for byte in data:
        crc ^= byte << 8
        for _ in range(8):
            if crc & 0x8000:
                crc = (crc << 1) ^ poly
            else:
                crc <<= 1
            crc &= 0xFFFF
    return crc


def pack_kpeg(
    bitmap_data: bytes,
    compressed_json: bytes,
    flags: int = 0,
    aspect_w: int = 4,
    aspect_h: int = 3,
) -> bytes:
    """Pack bitmap + compressed JSON into a KPEG binary container."""
    if len(bitmap_data) > 0xFFFF:
        raise ValueError(f"Bitmap too large: {len(bitmap_data)} bytes (max 65535)")
    if len(compressed_json) > 0xFFFF:
        raise ValueError(f"JSON too large: {len(compressed_json)} bytes (max 65535)")
    if not (0 < aspect_w < 256 and 0 < aspect_h < 256):
        raise ValueError(f"Invalid aspect ratio: {aspect_w}:{aspect_h}")

    header = struct.pack(
        "<4sBBHHBB",
        MAGIC_BYTES,
        FORMAT_VERSION,
        flags & 0xFF,
        len(bitmap_data),
        len(compressed_json),
        aspect_w,
        aspect_h,
    )
    body = header + bitmap_data + compressed_json
    checksum = crc16(body)
    return body + struct.pack("<H", checksum)


def unpack_kpeg(data: bytes) -> KPEGFile:
    """Parse a KPEG binary file. Raises ValueError on corruption."""
    if len(data) < HEADER_SIZE + CRC_SIZE:
        raise ValueError(f"File too small: {len(data)} bytes (min {HEADER_SIZE + CRC_SIZE})")

    # Verify CRC
    body = data[:-CRC_SIZE]
    expected_crc = struct.unpack("<H", data[-CRC_SIZE:])[0]
    actual_crc = crc16(body)
    if expected_crc != actual_crc:
        raise ValueError(f"CRC mismatch: expected 0x{expected_crc:04X}, got 0x{actual_crc:04X}")

    # Parse header
    magic, version, flags, bmp_len, json_len, asp_w, asp_h = struct.unpack(
        "<4sBBHHBB", data[:HEADER_SIZE]
    )
    if magic != MAGIC_BYTES:
        raise ValueError(f"Invalid magic bytes: {magic!r} (expected {MAGIC_BYTES!r})")
    if version != FORMAT_VERSION:
        raise ValueError(f"Unsupported version: {version} (expected {FORMAT_VERSION})")

    # Extract sections
    bitmap_start = HEADER_SIZE
    bitmap_end = bitmap_start + bmp_len
    json_end = bitmap_end + json_len

    if json_end != len(body):
        raise ValueError(
            f"Payload size mismatch: header declares {bmp_len}+{json_len}={bmp_len + json_len} "
            f"bytes, got {len(body) - HEADER_SIZE}"
        )

    return KPEGFile(
        version=version,
        flags=flags,
        aspect_w=asp_w,
        aspect_h=asp_h,
        bitmap_data=data[bitmap_start:bitmap_end],
        compressed_json=data[bitmap_end:json_end],
    )


def compute_total_size(bitmap_len: int, json_len: int) -> int:
    """Calculate total KPEG file size given payload lengths."""
    return HEADER_SIZE + bitmap_len + json_len + CRC_SIZE


def repack_with_new_json(original: bytes, new_compressed_json: bytes) -> bytes:
    """Create a new KPEG with same bitmap but different JSON (for /update_people).

    Reads existing KPEG, swaps the compressed JSON, repacks with updated CRC.
    """
    kpeg = unpack_kpeg(original)
    return pack_kpeg(
        bitmap_data=kpeg.bitmap_data,
        compressed_json=new_compressed_json,
        flags=kpeg.flags,
        aspect_w=kpeg.aspect_w,
        aspect_h=kpeg.aspect_h,
    )
