"""Adaptive-density bitmap for KPEG: grid + Sobel-weighted keypoints.

Structure (packed bytes):
  48 bytes   Custom palette (16 RGB triplets)
  1 byte     Grid dimension N (typically 8, giving 8x8 = 64 cells)
  N*N bytes  Grid: dominant palette index per cell
  1 byte     Keypoint count K (0-255)
  3*K bytes  Keypoints: (x_255, y_255, palette_index) per keypoint

Design rationale:
  - Grid gives baseline spatial color layout (~65 bytes for 8x8)
  - Keypoints add detail at high-gradient locations (edges, faces, text)
  - Combined, these form a structural color guide FLUX can use during reconstruction
  - Adaptive: bitmap size scales with keypoint count, balancing against JSON budget
"""
import numpy as np
from PIL import Image
from scipy import ndimage

from .palette import (
    CUSTOM_PALETTE_BYTES,
    find_nearest_color_indices,
    encode_custom_palette,
    decode_custom_palette,
    build_full_palette,
)

DEFAULT_GRID_SIZE = 8
MAX_KEYPOINTS = 255  # stored as uint8 count


def generate_grid(
    image: Image.Image,
    full_palette: np.ndarray,
    grid_size: int = DEFAULT_GRID_SIZE,
) -> np.ndarray:
    """Compute dominant palette index for each cell of an NxN grid.

    Returns: ndarray (grid_size, grid_size) of uint8 palette indices.
    """
    # Resize to clean cell boundaries, then mean-color per cell
    k = 16  # each cell samples k*k pixels
    target = grid_size * k
    img_resized = image.convert("RGB").resize((target, target), Image.Resampling.LANCZOS)
    arr = np.array(img_resized)  # (target, target, 3)

    cells = arr.reshape(grid_size, k, grid_size, k, 3).mean(axis=(1, 3))  # (G, G, 3)
    cells_flat = cells.reshape(-1, 3).astype(np.uint8)
    indices = find_nearest_color_indices(cells_flat, full_palette)
    return indices.reshape(grid_size, grid_size)


def extract_keypoints(
    image: Image.Image,
    full_palette: np.ndarray,
    max_count: int = 80,
    sobel_blur_sigma: float = 1.0,
) -> list[tuple[int, int, int]]:
    """Sample color keypoints at high-gradient image locations.

    Uses Sobel edge magnitude + non-max suppression for spatial distribution.
    Each keypoint = (x_255, y_255, palette_index) where coords are normalized to 0-255.
    """
    if max_count <= 0:
        return []
    max_count = min(max_count, MAX_KEYPOINTS)

    # Lower-res sampling for speed (keypoints are spatial hints, not precise)
    sample_size = 128
    img_small = image.convert("RGB").resize((sample_size, sample_size), Image.Resampling.LANCZOS)
    arr = np.array(img_small)

    # Sobel gradient magnitude on blurred grayscale
    gray = arr.mean(axis=2)
    if sobel_blur_sigma > 0:
        gray = ndimage.gaussian_filter(gray, sigma=sobel_blur_sigma)
    gx = ndimage.sobel(gray, axis=1)
    gy = ndimage.sobel(gray, axis=0)
    grad_mag = np.sqrt(gx ** 2 + gy ** 2)

    # Non-max suppression: keep local maxima above mean
    neighborhood = max(3, sample_size // 32)
    local_max = ndimage.maximum_filter(grad_mag, size=neighborhood)
    peaks_mask = (grad_mag == local_max) & (grad_mag > grad_mag.mean())

    peak_y, peak_x = np.where(peaks_mask)
    if len(peak_x) == 0:
        return []

    # Keep top-K by gradient magnitude
    peak_vals = grad_mag[peak_y, peak_x]
    order = np.argsort(peak_vals)[::-1]
    top_y = peak_y[order[:max_count]]
    top_x = peak_x[order[:max_count]]

    # Sample colors at peaks, map to palette
    colors = arr[top_y, top_x]
    palette_indices = find_nearest_color_indices(colors, full_palette)

    # Normalize coordinates to 0-255 byte range
    x_norm = (top_x * 255.0 / (sample_size - 1)).round().astype(np.uint8)
    y_norm = (top_y * 255.0 / (sample_size - 1)).round().astype(np.uint8)

    return [
        (int(x), int(y), int(idx))
        for x, y, idx in zip(x_norm, y_norm, palette_indices)
    ]


def pack_bitmap(
    custom_palette: np.ndarray,
    grid: np.ndarray,
    keypoints: list[tuple[int, int, int]],
) -> bytes:
    """Serialize custom palette + grid + keypoints into compact bytes."""
    grid_size = grid.shape[0]
    if grid.shape != (grid_size, grid_size):
        raise ValueError(f"Grid must be square, got {grid.shape}")
    if not (1 <= grid_size <= 255):
        raise ValueError(f"Grid size must be 1-255, got {grid_size}")
    if len(keypoints) > MAX_KEYPOINTS:
        raise ValueError(f"Too many keypoints: {len(keypoints)} (max {MAX_KEYPOINTS})")

    out = bytearray()
    out.extend(encode_custom_palette(custom_palette))  # 48 bytes
    out.append(grid_size)
    out.extend(grid.astype(np.uint8).tobytes())
    out.append(len(keypoints))
    for x, y, idx in keypoints:
        out.append(x & 0xFF)
        out.append(y & 0xFF)
        out.append(idx & 0xFF)
    return bytes(out)


def unpack_bitmap(data: bytes) -> tuple[np.ndarray, np.ndarray, list[tuple[int, int, int]]]:
    """Parse bitmap bytes back into (custom_palette, grid, keypoints)."""
    if len(data) < CUSTOM_PALETTE_BYTES + 2:
        raise ValueError(f"Bitmap too short: {len(data)} bytes")

    offset = 0
    custom_palette = decode_custom_palette(data[offset:offset + CUSTOM_PALETTE_BYTES])
    offset += CUSTOM_PALETTE_BYTES

    grid_size = data[offset]
    offset += 1
    grid_bytes = grid_size * grid_size
    if offset + grid_bytes + 1 > len(data):
        raise ValueError("Bitmap truncated at grid section")

    grid = np.frombuffer(data[offset:offset + grid_bytes], dtype=np.uint8).reshape(grid_size, grid_size).copy()
    offset += grid_bytes

    kp_count = data[offset]
    offset += 1
    if offset + kp_count * 3 > len(data):
        raise ValueError("Bitmap truncated at keypoints section")

    keypoints = []
    for i in range(kp_count):
        x = data[offset + i * 3]
        y = data[offset + i * 3 + 1]
        idx = data[offset + i * 3 + 2]
        keypoints.append((x, y, idx))

    return custom_palette, grid, keypoints


def compute_bitmap_size(grid_size: int, num_keypoints: int) -> int:
    """Total bitmap bytes: 48 (palette) + 1 (grid_size) + G*G + 1 (kp_count) + 3*K."""
    return CUSTOM_PALETTE_BYTES + 1 + grid_size * grid_size + 1 + 3 * num_keypoints


def render_bitmap(
    custom_palette: np.ndarray,
    grid: np.ndarray,
    keypoints: list[tuple[int, int, int]],
    width: int = 512,
    height: int = 512,
) -> Image.Image:
    """Render bitmap into a PIL image (upscaled grid + keypoint dots).

    Used by the decoder to produce a color/structure guide image for FLUX.
    """
    full_palette = build_full_palette(custom_palette)
    grid_size = grid.shape[0]

    # Upscale palette-index grid to RGB image
    grid_img = full_palette[grid]  # (G, G, 3)
    base = Image.fromarray(grid_img.astype(np.uint8)).resize(
        (width, height), Image.Resampling.LANCZOS
    )
    arr = np.array(base)

    # Overlay keypoints as small color blocks
    dot_radius = max(2, min(width, height) // 96)
    for x_norm, y_norm, idx in keypoints:
        cx = int(x_norm * (width - 1) / 255)
        cy = int(y_norm * (height - 1) / 255)
        color = full_palette[idx]
        x0 = max(0, cx - dot_radius)
        x1 = min(width, cx + dot_radius + 1)
        y0 = max(0, cy - dot_radius)
        y1 = min(height, cy + dot_radius + 1)
        arr[y0:y1, x0:x1] = color

    return Image.fromarray(arr)
