"""Tests for adaptive-density bitmap engine."""
import numpy as np
import pytest
from PIL import Image
from kpeg.bitmap import (
    generate_grid,
    extract_keypoints,
    pack_bitmap,
    unpack_bitmap,
    compute_bitmap_size,
    render_bitmap,
    DEFAULT_GRID_SIZE,
    MAX_KEYPOINTS,
)
from kpeg.palette import (
    build_full_palette,
    extract_custom_palette,
    CUSTOM_PALETTE_BYTES,
)


def _make_test_image(size=256):
    """4-quadrant synthetic test image: red / green / blue / yellow."""
    arr = np.zeros((size, size, 3), dtype=np.uint8)
    h = size // 2
    arr[:h, :h] = [200, 50, 50]
    arr[:h, h:] = [50, 200, 50]
    arr[h:, :h] = [50, 50, 200]
    arr[h:, h:] = [220, 220, 100]
    return Image.fromarray(arr)


def test_generate_grid_shape():
    img = _make_test_image()
    full = build_full_palette(np.zeros((16, 3), dtype=np.uint8))
    grid = generate_grid(img, full, grid_size=8)
    assert grid.shape == (8, 8)
    assert grid.dtype == np.uint8


def test_generate_grid_custom_size():
    img = _make_test_image()
    full = build_full_palette(np.zeros((16, 3), dtype=np.uint8))
    grid = generate_grid(img, full, grid_size=4)
    assert grid.shape == (4, 4)


def test_generate_grid_spatial_layout():
    """Different quadrants should map to different palette indices."""
    img = _make_test_image()
    custom = extract_custom_palette(img, k=16)
    full = build_full_palette(custom)
    grid = generate_grid(img, full, grid_size=8)
    # Top-left (red) should differ from bottom-right (yellow)
    tl_color = full[grid[0, 0]]
    br_color = full[grid[7, 7]]
    assert not np.array_equal(tl_color, br_color)


def test_extract_keypoints_returns_list():
    img = _make_test_image()
    full = build_full_palette(np.zeros((16, 3), dtype=np.uint8))
    kps = extract_keypoints(img, full, max_count=20)
    assert isinstance(kps, list)
    assert len(kps) <= 20
    for x, y, idx in kps:
        assert 0 <= x <= 255
        assert 0 <= y <= 255
        assert 0 <= idx <= 255


def test_extract_keypoints_zero_count():
    img = _make_test_image()
    full = build_full_palette(np.zeros((16, 3), dtype=np.uint8))
    assert extract_keypoints(img, full, max_count=0) == []


def test_extract_keypoints_respects_max():
    img = _make_test_image()
    full = build_full_palette(np.zeros((16, 3), dtype=np.uint8))
    kps = extract_keypoints(img, full, max_count=5)
    assert len(kps) <= 5


def test_extract_keypoints_finds_edges():
    """Hard quadrant boundaries should produce keypoints."""
    img = _make_test_image(size=256)
    full = build_full_palette(np.zeros((16, 3), dtype=np.uint8))
    kps = extract_keypoints(img, full, max_count=50)
    assert len(kps) > 3


def test_extract_keypoints_flat_image():
    """A flat (no-edge) image should return few or no keypoints."""
    flat = Image.fromarray(np.full((256, 256, 3), 128, dtype=np.uint8))
    full = build_full_palette(np.zeros((16, 3), dtype=np.uint8))
    kps = extract_keypoints(flat, full, max_count=50)
    # No edges → no keypoints (or very few)
    assert len(kps) < 10


def test_pack_unpack_round_trip():
    custom = np.random.randint(0, 256, size=(16, 3), dtype=np.uint8)
    grid = np.random.randint(0, 256, size=(8, 8), dtype=np.uint8)
    keypoints = [(10, 20, 30), (100, 150, 200), (255, 0, 128)]

    packed = pack_bitmap(custom, grid, keypoints)
    custom_out, grid_out, kps_out = unpack_bitmap(packed)

    np.testing.assert_array_equal(custom, custom_out)
    np.testing.assert_array_equal(grid, grid_out)
    assert kps_out == keypoints


def test_pack_bitmap_no_keypoints():
    custom = np.zeros((16, 3), dtype=np.uint8)
    grid = np.zeros((8, 8), dtype=np.uint8)
    packed = pack_bitmap(custom, grid, keypoints=[])
    assert len(packed) == 48 + 1 + 64 + 2  # 115 bytes (uint16 kp_count)
    _, _, kps_out = unpack_bitmap(packed)
    assert kps_out == []


def test_pack_bitmap_different_grid_sizes():
    custom = np.zeros((16, 3), dtype=np.uint8)
    for g in [4, 6, 10, 16]:
        grid = np.zeros((g, g), dtype=np.uint8)
        packed = pack_bitmap(custom, grid, [])
        _, grid_out, _ = unpack_bitmap(packed)
        assert grid_out.shape == (g, g)


def test_compute_bitmap_size():
    assert compute_bitmap_size(8, 0) == 115    # 48 + 1 + 64 + 2
    assert compute_bitmap_size(8, 100) == 415  # 115 + 300
    assert compute_bitmap_size(10, 50) == 301  # 48 + 1 + 100 + 2 + 150


def test_pack_bitmap_too_many_keypoints():
    custom = np.zeros((16, 3), dtype=np.uint8)
    grid = np.zeros((8, 8), dtype=np.uint8)
    with pytest.raises(ValueError, match="Too many keypoints"):
        pack_bitmap(custom, grid, [(0, 0, 0)] * (MAX_KEYPOINTS + 1))


def test_pack_bitmap_non_square_grid():
    custom = np.zeros((16, 3), dtype=np.uint8)
    with pytest.raises(ValueError, match="square"):
        pack_bitmap(custom, np.zeros((4, 8), dtype=np.uint8), [])


def test_unpack_bitmap_too_short():
    with pytest.raises(ValueError, match="too short"):
        unpack_bitmap(b"\x00" * 10)


def test_unpack_bitmap_truncated_grid():
    custom = np.zeros((16, 3), dtype=np.uint8)
    grid = np.zeros((8, 8), dtype=np.uint8)
    packed = pack_bitmap(custom, grid, [])
    with pytest.raises(ValueError, match="truncated"):
        unpack_bitmap(packed[:100])


def test_render_bitmap_returns_image():
    custom = extract_custom_palette(_make_test_image(), k=16)
    grid = np.random.randint(0, 256, size=(8, 8), dtype=np.uint8)
    keypoints = [(50, 50, 0), (200, 200, 100)]
    img = render_bitmap(custom, grid, keypoints, width=256, height=256)
    assert isinstance(img, Image.Image)
    assert img.size == (256, 256)
    assert img.mode == "RGB"


def test_full_pipeline_from_image():
    """End-to-end: image → palette → grid → keypoints → pack → unpack."""
    img = _make_test_image()
    custom = extract_custom_palette(img, k=16)
    full = build_full_palette(custom)
    grid = generate_grid(img, full, grid_size=8)
    keypoints = extract_keypoints(img, full, max_count=30)

    packed = pack_bitmap(custom, grid, keypoints)
    assert len(packed) < 500  # comfortably within budget

    custom_out, grid_out, kps_out = unpack_bitmap(packed)
    np.testing.assert_array_equal(custom, custom_out)
    np.testing.assert_array_equal(grid, grid_out)
    assert kps_out == keypoints


def test_budget_sizes_match_plan():
    """Verify size math for the ~1.5 KB bitmap target budget."""
    # Minimal bitmap (no keypoints) = ~115 bytes
    assert compute_bitmap_size(8, 0) == 115
    # Typical bitmap with modest fill: 45 keypoints
    assert compute_bitmap_size(8, 45) < 260
    # Target fill at 1500B: ~461 keypoints
    assert compute_bitmap_size(8, 461) == 1498
    # MAX_KEYPOINTS caps the bitmap under ~1500B
    assert compute_bitmap_size(8, MAX_KEYPOINTS) <= 1500
