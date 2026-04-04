"""Configuration loader for KPEG.

Loads environment variables from .env file at repo root.
Model selection (Haiku/Sonnet, Schnell/Pro) is controlled via env vars.
"""
import os
from pathlib import Path
from dotenv import load_dotenv

# Repo root = two levels up from this file (Tooling/kpeg/config.py → repo root)
REPO_ROOT = Path(__file__).resolve().parent.parent.parent
ENV_PATH = REPO_ROOT / ".env"

load_dotenv(ENV_PATH, override=True)


# ═══ API Keys ═══
ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY", "")
FAL_KEY = os.getenv("FAL_KEY", "")


# ═══ Model Selection (test vs demo tier) ═══
VISION_MODEL = os.getenv("KPEG_VISION_MODEL", "claude-haiku-4-5-20251001")
IMAGE_MODEL = os.getenv("KPEG_IMAGE_MODEL", "fal-ai/flux/schnell")


# ═══ Format Settings ═══
# KPEG payload: bitmap carries the color DNA, JSON carries the scene prompt.
# We aim to fill the bitmap fully (spatial color fidelity) and keep JSON tight.
BITMAP_TARGET_SIZE = int(os.getenv("KPEG_BITMAP_TARGET", "1500"))  # ~1.5 KB color guide
JSON_MAX_SIZE = int(os.getenv("KPEG_JSON_MAX", "1000"))            # ~1 KB compressed JSON
# Derived totals (header 12B + bitmap + JSON + CRC 2B). Narrative: "~1-2 KB".
TARGET_SIZE = int(os.getenv("KPEG_TARGET_SIZE", "2500"))
MAX_SIZE = int(os.getenv("KPEG_MAX_SIZE", "2514"))


# ═══ Paths ═══
API_DIR = REPO_ROOT / "API"
LIBRARY_DIR = API_DIR / "library"
DATABASE_PATH = API_DIR / "kpeg_library.db"


def validate_config() -> list[str]:
    """Returns list of missing/invalid config items. Empty list = all good."""
    errors = []
    if not ANTHROPIC_API_KEY or ANTHROPIC_API_KEY.startswith("sk-ant-api03-YOUR"):
        errors.append("ANTHROPIC_API_KEY not set in .env")
    if not FAL_KEY or FAL_KEY.startswith("YOUR_KEY"):
        errors.append("FAL_KEY not set in .env")
    if not ENV_PATH.exists():
        errors.append(f".env file not found at {ENV_PATH}")
    return errors


def print_config_status():
    """Prints the current config (keys masked) for debugging."""
    print(f"KPEG Config loaded from: {ENV_PATH}")
    print(f"  REPO_ROOT: {REPO_ROOT}")
    print(f"  ANTHROPIC_API_KEY: {'set (' + ANTHROPIC_API_KEY[:15] + '...)' if ANTHROPIC_API_KEY else 'NOT SET'}")
    print(f"  FAL_KEY: {'set (' + FAL_KEY[:12] + '...)' if FAL_KEY else 'NOT SET'}")
    print(f"  VISION_MODEL: {VISION_MODEL}")
    print(f"  IMAGE_MODEL: {IMAGE_MODEL}")
    print(f"  BITMAP_TARGET_SIZE: {BITMAP_TARGET_SIZE} bytes")
    print(f"  JSON_MAX_SIZE: {JSON_MAX_SIZE} bytes")
    print(f"  TARGET_SIZE: {TARGET_SIZE} bytes")
    print(f"  MAX_SIZE: {MAX_SIZE} bytes")
    errors = validate_config()
    if errors:
        print(f"  ISSUES: {errors}")
    else:
        print(f"  STATUS: OK")
