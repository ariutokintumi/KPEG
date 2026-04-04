"""Brotli compression for KPEG JSON metadata.

Quality 11 (maximum) is used because:
- Payloads are small (<2KB), so compression time is negligible
- Every byte saved = more room for richer scene descriptions
"""
import json as json_lib
import brotli

DEFAULT_QUALITY = 11  # Maximum compression for small payloads


def compress_json(data: dict, quality: int = DEFAULT_QUALITY) -> bytes:
    """Serialize dict -> compact JSON -> Brotli compress."""
    json_bytes = json_lib.dumps(
        data, separators=(",", ":"), ensure_ascii=False
    ).encode("utf-8")
    return brotli.compress(json_bytes, quality=quality)


def decompress_json(data: bytes) -> dict:
    """Brotli decompress -> parse JSON -> dict."""
    json_bytes = brotli.decompress(data)
    return json_lib.loads(json_bytes.decode("utf-8"))


def estimate_compressed_size(data: dict, quality: int = DEFAULT_QUALITY) -> int:
    """How many bytes would this dict take after JSON+Brotli? Useful for budget loop."""
    return len(compress_json(data, quality=quality))
