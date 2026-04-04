"""Shared pytest fixtures: real test image + realistic library + plausible scene JSON.

The `cannes_venue` fixture represents a production-like photo (ETHGlobal Cannes
venue, Palais des Festivals). The `library_catalog` fixture simulates the target
production state where most visible objects are already registered in the library.
"""
from pathlib import Path
import pytest
from PIL import Image

SAMPLE_DIR = Path(__file__).parent.parent / "sample_photos"
CANNES_IMAGE = SAMPLE_DIR / "cannes_venue.jpg"


@pytest.fixture
def cannes_venue() -> Image.Image:
    """Load the real Cannes venue test photo (1280x960, indoor, 1 person + many objects)."""
    if not CANNES_IMAGE.exists():
        pytest.skip(f"Sample image not found: {CANNES_IMAGE}")
    return Image.open(CANNES_IMAGE)


@pytest.fixture
def cannes_library_catalog() -> list[dict]:
    """Realistic objects library matching items visible in cannes_venue.jpg.

    Simulates production state: most objects in photos will have library refs.
    """
    return [
        {"id": "obj_bistro_chair_blk", "name": "Black bistro chair", "category": "furniture"},
        {"id": "obj_deck_chair_wood", "name": "Wooden deck chair", "category": "furniture"},
        {"id": "obj_service_cart_gsf", "name": "GSF service cart", "category": "equipment"},
        {"id": "obj_palm_tropical", "name": "Tropical palm plant", "category": "decor"},
        {"id": "obj_banana_plant", "name": "Banana leaf plant", "category": "decor"},
        {"id": "obj_olive_potted", "name": "Potted olive tree", "category": "decor"},
        {"id": "obj_table_linen_blk", "name": "Black-skirted table", "category": "furniture"},
        {"id": "obj_fire_ext_red", "name": "Red fire extinguisher", "category": "equipment"},
        {"id": "obj_wicker_chair", "name": "Wicker lounge chair", "category": "furniture"},
    ]


@pytest.fixture
def cannes_metadata() -> dict:
    """App metadata matching cannes_venue.jpg capture context."""
    return {
        "orientation": "landscape",
        "timestamp": 1743724800,
        "timezone": "Europe/Paris",
        "device_model": "Pixel 8 Pro",
        "is_outdoor": False,
        "lens_info": {"focal_length_mm": 6.9, "aperture": 1.8, "zoom_level": 1.0},
        "flash_used": False,
        "lat": 43.5528,
        "lng": 7.0174,
        "compass_heading": 145.0,
        "camera_tilt": 0.0,
        "people": [
            {"user_id": "unknown_0", "bbox": [0.47, 0.03, 0.62, 0.90]},
        ],
        "scene_hint": "venue setup, Palais des Festivals Cannes",
        "tags": ["ethglobal", "cannes", "venue"],
        "indoor_place_id": "place_palais_festivals",
        "indoor_description": "main hall, near glass doors",
        "session_id": "sess_20260404_1800",
    }


@pytest.fixture
def cannes_realistic_scene() -> dict:
    """Plausible Claude Haiku 4.5 scene JSON for cannes_venue.jpg.

    Written as a FLUX prompt blueprint (prompt-ready phrases, not prose).
    Approximates realistic token volume for testing the budget-fill loop.
    """
    return {
        "s": {
            "d": "indoor venue hall, staff member pushing service cart past black bistro chair, "
                 "tropical plants and wooden deck chairs in background, green carpet, glass entrance doors",
            "mood": "professional",
            "light": {"dir": "above", "type": "artificial", "warmth": "neutral"},
            "depth": "fg chair and table, mg staff with cart, bg plants and doors",
            "style": "candid documentary photography",
        },
        "o": [
            {"n": "person", "b": [0.47, 0.03, 0.62, 0.90],
             "d": "woman mid-40s, brown ponytail, white blouse, black buttoned vest, pushing cart, looking left, professional expression",
             "ref": "unknown1"},
            {"n": "cart", "b": [0.58, 0.50, 0.82, 0.97],
             "d": "black plastic service cart with GSF branding, wheeled",
             "ref": "obj_service_cart_gsf"},
            {"n": "chair", "b": [0.19, 0.58, 0.38, 0.98],
             "d": "black bistro chair with curved backrest",
             "ref": "obj_bistro_chair_blk"},
            {"n": "table", "b": [0.00, 0.65, 0.22, 0.95],
             "d": "round table with long black linen skirt",
             "ref": "obj_table_linen_blk"},
            {"n": "plant", "b": [0.42, 0.00, 0.78, 0.55],
             "d": "large banana leaf plant, bright green",
             "ref": "obj_banana_plant"},
            {"n": "plant", "b": [0.72, 0.20, 1.00, 0.78],
             "d": "tropical palm fronds",
             "ref": "obj_palm_tropical"},
            {"n": "chair", "b": [0.15, 0.45, 0.35, 0.70],
             "d": "wooden beach deck chair with white cushion",
             "ref": "obj_deck_chair_wood"},
            {"n": "chair", "b": [0.85, 0.55, 1.00, 0.80],
             "d": "wicker lounge chair",
             "ref": "obj_wicker_chair"},
            {"n": "fire_extinguisher", "b": [0.32, 0.45, 0.36, 0.55],
             "d": "red wall-mounted fire extinguisher",
             "ref": "obj_fire_ext_red"},
            {"n": "doors", "b": [0.00, 0.15, 0.28, 0.65],
             "d": "blue-framed glass double doors"},
        ],
        "t": [
            {"text": "GSF", "b": [0.64, 0.62, 0.72, 0.68], "type": "logo"},
            {"text": "PALAIS DES FESTIVALS", "b": [0.62, 0.78, 0.78, 0.83], "type": "label"},
            {"text": "Cannes", "b": [0.66, 0.83, 0.74, 0.86], "type": "label"},
        ],
        "colors": ["#2E5939", "#F0F0F0", "#1A1A1A", "#5FA863", "#8B6F47"],
    }
