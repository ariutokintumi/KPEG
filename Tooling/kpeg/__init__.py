"""KPEG - Kilobyte Photographic Experts Group.

A ~2KB binary container that stores enough "DNA" for AI to reconstruct a photo.
Not compression - a reconstruction seed.
"""

__version__ = "0.1.0"
__author__ = "German Abal, Jose M Avila"

MAGIC_BYTES = b"KPEG"
FORMAT_VERSION = 0x01
HEADER_SIZE = 12
CRC_SIZE = 2
