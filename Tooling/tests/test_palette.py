"""Tests for the KPEG color palette system."""
import numpy as np
import pytest
from PIL import Image
from kpeg.palette import (
    STANDARD_PALETTE,
    CUSTOM_PALETTE_SIZE,
    STANDARD_PALETTE_SIZE,
    TOTAL_PALETTE_SIZE,
    CUSTOM_PALETTE_BYTES,
    extract_custom_palette,
    build_full_palette,
    find_nearest_color_index,
    find_nearest_color_indices,
    encode_custom_palette,
    decode_custom_palette,
)


def test_standard_palette_size():
    """Standard palette has exactly 240 unique colors."""
    assert STANDARD_PALETTE.shape == (240, 3)
    assert STANDARD_PALETTE.dtype == np.uint8


def test_standard_palette_unique():
    """All 240 standard colors are unique (no duplicates between cube and grays)."""
    unique = np.unique(STANDARD_PALETTE, axis=0)
    assert unique.shape[0] == 240


def test_standard_palette_has_extremes():
    """Standard palette includes black and white."""
    colors = STANDARD_PALETTE.tolist()
    assert [0, 0, 0] in colors
    assert [255, 255, 255] in colors


def test_constants_consistent():
    """Palette size constants add up correctly."""
    assert CUSTOM_PALETTE_SIZE + STANDARD_PALETTE_SIZE == TOTAL_PALETTE_SIZE
    assert TOTAL_PALETTE_SIZE == 256
    assert CUSTOM_PALETTE_BYTES == 48


def test_extract_custom_palette_shape():
    """K-means extraction returns (16, 3) uint8."""
    # Build a test image
    arr = np.zeros((128, 128, 3), dtype=np.uint8)
    arr[:64, :64] = [255, 0, 0]  # Red quadrant
    arr[:64, 64:] = [0, 255, 0]  # Green
    arr[64:, :64] = [0, 0, 255]  # Blue
    arr[64:, 64:] = [255, 255, 0]  # Yellow
    img = Image.fromarray(arr)
    custom = extract_custom_palette(img, k=16)
    assert custom.shape == (16, 3)
    assert custom.dtype == np.uint8


def test_build_full_palette():
    """Full palette combines custom 16 + standard 240 = 256 colors."""
    custom = np.ones((16, 3), dtype=np.uint8) * 128
    full = build_full_palette(custom)
    assert full.shape == (256, 3)
    np.testing.assert_array_equal(full[:16], custom)
    np.testing.assert_array_equal(full[16:], STANDARD_PALETTE)


def test_build_full_palette_wrong_shape():
    """Wrong shape raises ValueError."""
    with pytest.raises(ValueError):
        build_full_palette(np.zeros((10, 3), dtype=np.uint8))


def test_find_nearest_color_exact():
    """Exact color match returns correct index."""
    palette = np.array([[0, 0, 0], [255, 0, 0], [0, 255, 0]], dtype=np.uint8)
    assert find_nearest_color_index([255, 0, 0], palette) == 1
    assert find_nearest_color_index([0, 255, 0], palette) == 2
    assert find_nearest_color_index([0, 0, 0], palette) == 0


def test_find_nearest_color_approximate():
    """Nearest-match picks closest palette entry."""
    palette = np.array([[0, 0, 0], [255, 255, 255]], dtype=np.uint8)
    assert find_nearest_color_index([10, 10, 10], palette) == 0  # Closer to black
    assert find_nearest_color_index([200, 200, 200], palette) == 1  # Closer to white


def test_find_nearest_color_indices_vectorized():
    """Vectorized version matches scalar version."""
    palette = np.array([[0, 0, 0], [255, 0, 0], [0, 255, 0], [0, 0, 255]], dtype=np.uint8)
    colors = np.array([
        [200, 20, 20],  # near red
        [20, 200, 20],  # near green
        [5, 5, 5],      # near black
        [20, 20, 200],  # near blue
    ], dtype=np.uint8)
    indices = find_nearest_color_indices(colors, palette)
    assert indices.tolist() == [1, 2, 0, 3]
    assert indices.dtype == np.uint8


def test_encode_decode_custom_palette():
    """Encoding + decoding 16 colors round-trips exactly."""
    custom = np.random.randint(0, 256, size=(16, 3), dtype=np.uint8)
    encoded = encode_custom_palette(custom)
    assert isinstance(encoded, bytes)
    assert len(encoded) == 48
    decoded = decode_custom_palette(encoded)
    np.testing.assert_array_equal(decoded, custom)


def test_encode_custom_palette_wrong_shape():
    """Encoding wrong shape raises."""
    with pytest.raises(ValueError):
        encode_custom_palette(np.zeros((10, 3), dtype=np.uint8))


def test_decode_custom_palette_wrong_bytes():
    """Decoding wrong byte count raises."""
    with pytest.raises(ValueError):
        decode_custom_palette(b"\x00" * 47)
    with pytest.raises(ValueError):
        decode_custom_palette(b"\x00" * 49)
