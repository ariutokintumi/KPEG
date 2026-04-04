"""Color palette for KPEG bitmap encoding.

Total palette: 256 colors
  - Indices 0-15:  Custom colors extracted per-image via k-means (48 bytes stored)
  - Indices 16-255: Standard 240-color photographic palette (hard-coded, no storage)

The custom 16 capture image-specific tones (skin, sky, branded colors).
The standard 240 cover the general color space (6x6x6 RGB cube + 24 grays).
"""
import numpy as np
from PIL import Image
from sklearn.cluster import KMeans

CUSTOM_PALETTE_SIZE = 16
STANDARD_PALETTE_SIZE = 240
TOTAL_PALETTE_SIZE = CUSTOM_PALETTE_SIZE + STANDARD_PALETTE_SIZE  # 256
CUSTOM_PALETTE_BYTES = CUSTOM_PALETTE_SIZE * 3  # 48 bytes (RGB triplets)


def _build_standard_palette() -> np.ndarray:
    """Build the 240-color photographic palette.

    216 colors: 6x6x6 RGB cube (levels 0, 51, 102, 153, 204, 255)
    24 colors:  grayscale values that don't appear in the cube
    """
    colors = []
    # 6x6x6 RGB cube = 216 colors
    levels = [0, 51, 102, 153, 204, 255]
    for r in levels:
        for g in levels:
            for b in levels:
                colors.append([r, g, b])
    # 24 grayscale values, interleaved between cube levels (unique)
    cube_set = set(levels)
    gray_pool = [v for v in range(1, 255) if v not in cube_set]
    step = len(gray_pool) // 24
    for i in range(24):
        v = gray_pool[i * step]
        colors.append([v, v, v])
    return np.array(colors, dtype=np.uint8)


STANDARD_PALETTE = _build_standard_palette()


def extract_custom_palette(image: Image.Image, k: int = CUSTOM_PALETTE_SIZE) -> np.ndarray:
    """Extract k dominant colors from an image using k-means clustering.

    Returns: ndarray of shape (k, 3) with uint8 RGB values.
    """
    img_small = image.convert("RGB").resize((128, 128), Image.Resampling.LANCZOS)
    pixels = np.array(img_small).reshape(-1, 3)
    kmeans = KMeans(n_clusters=k, n_init=3, random_state=42)
    kmeans.fit(pixels)
    return np.round(kmeans.cluster_centers_).astype(np.uint8)


def build_full_palette(custom_colors: np.ndarray) -> np.ndarray:
    """Combine custom 16 + standard 240 into full 256-color palette."""
    if custom_colors.shape != (CUSTOM_PALETTE_SIZE, 3):
        raise ValueError(f"Expected shape ({CUSTOM_PALETTE_SIZE}, 3), got {custom_colors.shape}")
    return np.vstack([custom_colors, STANDARD_PALETTE])


def find_nearest_color_index(color, palette: np.ndarray) -> int:
    """Find the palette index closest to the given RGB color (Euclidean in RGB space)."""
    color_arr = np.array(color, dtype=np.int32)
    distances = np.sum((palette.astype(np.int32) - color_arr) ** 2, axis=1)
    return int(np.argmin(distances))


def find_nearest_color_indices(colors: np.ndarray, palette: np.ndarray) -> np.ndarray:
    """Vectorized: find nearest palette index for many colors at once.

    Args:
        colors:  ndarray (N, 3) of RGB values
        palette: ndarray (P, 3) of palette colors
    Returns:
        ndarray (N,) of uint8 indices
    """
    colors_i = colors.astype(np.int32)
    palette_i = palette.astype(np.int32)
    # Compute squared distances (N, P)
    diffs = colors_i[:, np.newaxis, :] - palette_i[np.newaxis, :, :]
    distances = np.sum(diffs ** 2, axis=2)
    return np.argmin(distances, axis=1).astype(np.uint8)


def encode_custom_palette(custom_colors: np.ndarray) -> bytes:
    """Serialize 16 custom colors to 48 bytes (RGB triplets)."""
    if custom_colors.shape != (CUSTOM_PALETTE_SIZE, 3):
        raise ValueError(f"Expected shape ({CUSTOM_PALETTE_SIZE}, 3), got {custom_colors.shape}")
    return custom_colors.astype(np.uint8).tobytes()


def decode_custom_palette(data: bytes) -> np.ndarray:
    """Deserialize 48 bytes back to 16 custom colors."""
    if len(data) != CUSTOM_PALETTE_BYTES:
        raise ValueError(f"Expected {CUSTOM_PALETTE_BYTES} bytes, got {len(data)}")
    return np.frombuffer(data, dtype=np.uint8).reshape(CUSTOM_PALETTE_SIZE, 3)
