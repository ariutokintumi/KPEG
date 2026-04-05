"""Adaptive-density bitmap for KPEG: grid + Sobel-weighted keypoints + edge map.

Structure (packed bytes):
  48 bytes   Custom palette (16 RGB triplets)
  1 byte     Grid dimension N (typically 8, giving 8x8 = 64 cells)
  N*N bytes  Grid: dominant palette index per cell
  2 bytes    Keypoint count K (uint16 LE, 0-65535)
  3*K bytes  Keypoints: (x_255, y_255, palette_index) per keypoint
  [optional, added v2]:
  1 byte     Edge map dimension E (typically 32)
  E*E/8 bytes  Edge map: 1-bit per pixel, packed as bitfield (Canny edges)

Design rationale:
  - Grid gives baseline spatial color layout (~65 bytes for 8x8)
  - Keypoints add detail at high-gradient locations (edges, faces, text)
  - Edge map (128 bytes for 32x32) tells FLUX WHERE object boundaries are
  - Combined: colors + structure + edges = comprehensive spatial guide
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
DEFAULT_EDGE_SIZE = 32  # 32x32 = 128 bytes como bitfield
# 48 (palette) + 1 (grid_size) + 64 (8x8 grid) + 2 (kp_count) + 3*K keypoints + 1 (edge_size) + 128 (edge map)
# Con 80 keypoints: 48 + 1 + 64 + 2 + 240 + 1 + 128 = 484 bytes
# Con MAX keypoints ajustado: ~1500B target
MAX_KEYPOINTS = 420  # reducido para dejar espacio al edge map


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

    # Sample at higher resolution to support more keypoints (bitmap target up to ~1500B)
    sample_size = 256
    img_small = image.convert("RGB").resize((sample_size, sample_size), Image.Resampling.LANCZOS)
    arr = np.array(img_small)

    # Sobel gradient magnitude on blurred grayscale
    gray = arr.mean(axis=2)
    if sobel_blur_sigma > 0:
        gray = ndimage.gaussian_filter(gray, sigma=sobel_blur_sigma)
    gx = ndimage.sobel(gray, axis=1)
    gy = ndimage.sobel(gray, axis=0)
    grad_mag = np.sqrt(gx ** 2 + gy ** 2)

    # Non-max suppression: keep local maxima above 50% of mean for denser coverage
    neighborhood = max(3, sample_size // 48)
    local_max = ndimage.maximum_filter(grad_mag, size=neighborhood)
    peaks_mask = (grad_mag == local_max) & (grad_mag > grad_mag.mean() * 0.5)

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


def extract_edge_map(
    image: Image.Image,
    edge_size: int = DEFAULT_EDGE_SIZE,
    canny_sigma: float = 1.5,
    threshold_ratio: float = 0.3,
) -> bytes:
    """Extract binary edge map from image.

    Returns packed bitfield of edge_size x edge_size (1 bit per pixel).
    32x32 = 128 bytes. Marks object boundaries, siluetas, bordes de muebles, etc.
    """
    img_small = image.convert("L").resize((edge_size, edge_size), Image.Resampling.LANCZOS)
    arr = np.array(img_small, dtype=np.float64)

    # Sobel edge detection (simulating Canny without OpenCV)
    if canny_sigma > 0:
        arr = ndimage.gaussian_filter(arr, sigma=canny_sigma)
    gx = ndimage.sobel(arr, axis=1)
    gy = ndimage.sobel(arr, axis=0)
    magnitude = np.sqrt(gx ** 2 + gy ** 2)

    # Threshold: top percentage of gradients
    threshold = magnitude.max() * threshold_ratio
    edges = (magnitude > threshold).astype(np.uint8)

    # Pack as bitfield (8 pixels per byte, row-major)
    flat = edges.flatten()
    # Pad to multiple of 8
    padded = np.pad(flat, (0, (8 - len(flat) % 8) % 8))
    packed = np.packbits(padded)
    return bytes(packed)


def unpack_edge_map(data: bytes, edge_size: int) -> np.ndarray:
    """Unpack bitfield edge map back to 2D binary array."""
    bits = np.unpackbits(np.frombuffer(data, dtype=np.uint8))
    total = edge_size * edge_size
    return bits[:total].reshape(edge_size, edge_size)


def pack_bitmap(
    custom_palette: np.ndarray,
    grid: np.ndarray,
    keypoints: list[tuple[int, int, int]],
    edge_map: bytes = b"",
    edge_size: int = DEFAULT_EDGE_SIZE,
) -> bytes:
    """Serialize custom palette + grid + keypoints + optional edge map."""
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
    # Keypoint count as uint16 LE
    kp_count = len(keypoints)
    out.append(kp_count & 0xFF)
    out.append((kp_count >> 8) & 0xFF)
    for x, y, idx in keypoints:
        out.append(x & 0xFF)
        out.append(y & 0xFF)
        out.append(idx & 0xFF)

    # Edge map (optional section — backward compatible)
    if edge_map:
        out.append(edge_size)
        out.extend(edge_map)

    return bytes(out)


def unpack_bitmap(data: bytes) -> tuple[np.ndarray, np.ndarray, list[tuple[int, int, int]]]:
    """Parse bitmap bytes back into (custom_palette, grid, keypoints).

    Also extracts edge map if present (backward compatible — old files return None).
    Edge map accessible via unpack_bitmap_full().
    """
    result = unpack_bitmap_full(data)
    return result[0], result[1], result[2]


def unpack_bitmap_full(data: bytes) -> tuple[np.ndarray, np.ndarray, list[tuple[int, int, int]], np.ndarray | None]:
    """Parse bitmap bytes → (custom_palette, grid, keypoints, edge_map_or_None)."""
    if len(data) < CUSTOM_PALETTE_BYTES + 2:
        raise ValueError(f"Bitmap too short: {len(data)} bytes")

    offset = 0
    custom_palette = decode_custom_palette(data[offset:offset + CUSTOM_PALETTE_BYTES])
    offset += CUSTOM_PALETTE_BYTES

    grid_size = data[offset]
    offset += 1
    grid_bytes = grid_size * grid_size
    if offset + grid_bytes + 2 > len(data):
        raise ValueError("Bitmap truncated at grid section")

    grid = np.frombuffer(data[offset:offset + grid_bytes], dtype=np.uint8).reshape(grid_size, grid_size).copy()
    offset += grid_bytes

    # Keypoint count: uint16 LE
    kp_count = data[offset] | (data[offset + 1] << 8)
    offset += 2
    if offset + kp_count * 3 > len(data):
        raise ValueError("Bitmap truncated at keypoints section")

    keypoints = []
    for i in range(kp_count):
        x = data[offset + i * 3]
        y = data[offset + i * 3 + 1]
        idx = data[offset + i * 3 + 2]
        keypoints.append((x, y, idx))
    offset += kp_count * 3

    # Edge map (optional — backward compatible)
    edge_map = None
    if offset < len(data):
        edge_size = data[offset]
        offset += 1
        edge_bytes = (edge_size * edge_size + 7) // 8
        if offset + edge_bytes <= len(data):
            edge_map = unpack_edge_map(data[offset:offset + edge_bytes], edge_size)

    return custom_palette, grid, keypoints, edge_map


def compute_bitmap_size(grid_size: int, num_keypoints: int) -> int:
    """Total bitmap bytes: 48 (palette) + 1 (grid_size) + G*G + 2 (kp_count uint16) + 3*K."""
    return CUSTOM_PALETTE_BYTES + 1 + grid_size * grid_size + 2 + 3 * num_keypoints


def render_bitmap(
    custom_palette: np.ndarray,
    grid: np.ndarray,
    keypoints: list[tuple[int, int, int]],
    width: int = 512,
    height: int = 512,
    edge_map: np.ndarray | None = None,
) -> Image.Image:
    """Render bitmap into a PIL image (upscaled grid + keypoint dots + edge overlay).

    Used by the decoder to produce a color/structure guide image for FLUX.
    Edge overlay draws white lines where object boundaries are, giving FLUX
    spatial structure information alongside the color layout.
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

    # Overlay edge map as semi-transparent white lines
    if edge_map is not None:
        edge_h, edge_w = edge_map.shape
        # Upscale edge map to output size
        edge_upscaled = np.array(
            Image.fromarray((edge_map * 255).astype(np.uint8)).resize(
                (width, height), Image.Resampling.NEAREST
            )
        )
        # Blend edges as white with 60% opacity where edges exist
        edge_mask = edge_upscaled > 128
        arr[edge_mask] = (arr[edge_mask] * 0.4 + np.array([255, 255, 255]) * 0.6).astype(np.uint8)

    return Image.fromarray(arr)
