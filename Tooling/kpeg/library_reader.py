"""Library reader: read-only access to Jose's SQLite library DB.

Used by:
  - scene_analyzer: injects objects catalog into Claude's system prompt for smart matching
  - decoder: resolves library refs (people/places/objects) to photo file paths for FLUX

Schema owned by Jose in API/database.py. This module must NOT modify it.
"""
import sqlite3
from pathlib import Path
from typing import Optional

from .config import DATABASE_PATH, LIBRARY_DIR


def _connect():
    """Open read-only connection to library DB."""
    conn = sqlite3.connect(DATABASE_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def _normalize_library_path(stored_path: str) -> str:
    """Rewrite a stored path to the local LIBRARY_DIR if it doesn't resolve.

    The DB stores ABSOLUTE paths from whichever machine did the registration
    (e.g. `/home/jmaria/PROYECTOS/KPEG/API/library/people/usr_xxx/selfie_0.jpg`
    from Jose's Linux box). When the decoder runs on any other machine, those
    absolute paths don't exist and FLUX would receive no references.

    This helper finds the `library/` segment in the stored path and rebases
    the tail against the local `LIBRARY_DIR` from config. It's a read-time
    rewrite — the DB itself is never mutated.

    Examples:
      /home/jmaria/PROYECTOS/KPEG/API/library/people/usr_X/s.jpg
        -> {LIBRARY_DIR}/people/usr_X/s.jpg
      D:/…/KPEG/API/library/objects/obj_Y/photo_0.jpg
        -> {LIBRARY_DIR}/objects/obj_Y/photo_0.jpg
    """
    if not stored_path:
        return stored_path
    # Fast path: path resolves as-is (e.g. running on the same machine)
    if Path(stored_path).exists():
        return stored_path

    norm = stored_path.replace("\\", "/")
    marker = "/library/"
    idx = norm.rfind(marker)  # rfind so we match the LAST segment (handles nesting)
    if idx < 0:
        return stored_path  # no rewrite possible
    tail = norm[idx + len(marker):]
    return str(Path(LIBRARY_DIR) / tail)


# ═══ Objects ═══

def get_objects_catalog(limit: int = 100) -> list[dict]:
    """Return all objects in library as [{id, name, category}, ...]."""
    if not Path(DATABASE_PATH).exists():
        return []
    conn = _connect()
    rows = conn.execute(
        "SELECT object_id, name, category FROM objects ORDER BY category, name LIMIT ?",
        (limit,),
    ).fetchall()
    conn.close()
    return [{"id": r["object_id"], "name": r["name"], "category": r["category"]} for r in rows]


def format_objects_catalog_for_prompt(objects: list[dict]) -> str:
    """Compact catalog for Claude's system prompt. One line per object: 'id | name | category'."""
    if not objects:
        return "(empty library)"
    return "\n".join(f"{o['id']} | {o['name']} | {o['category']}" for o in objects)


def get_object_photos(object_id: str) -> list[str]:
    """Return file paths for an object's reference photos, rebased to local LIBRARY_DIR."""
    if not Path(DATABASE_PATH).exists():
        return []
    conn = _connect()
    rows = conn.execute(
        "SELECT file_path FROM object_photos WHERE object_id = ?", (object_id,),
    ).fetchall()
    conn.close()
    return [_normalize_library_path(r["file_path"]) for r in rows]


def get_object_info(object_id: str) -> Optional[dict]:
    """Lookup object name + category."""
    if not Path(DATABASE_PATH).exists():
        return None
    conn = _connect()
    row = conn.execute(
        "SELECT name, category FROM objects WHERE object_id = ?", (object_id,),
    ).fetchone()
    conn.close()
    return {"name": row["name"], "category": row["category"]} if row else None


# ═══ Places ═══

def get_place_photos(place_id: str) -> list[dict]:
    """Return all photos for a place with per-photo metadata."""
    if not Path(DATABASE_PATH).exists():
        return []
    conn = _connect()
    rows = conn.execute(
        "SELECT id, place_id, file_path, lat, lng, compass_heading, camera_tilt "
        "FROM place_photos WHERE place_id = ?",
        (place_id,),
    ).fetchall()
    conn.close()
    return [dict(r) for r in rows]


def select_best_place_refs(
    place_id: str,
    target_compass: Optional[float] = None,
    target_tilt: Optional[float] = None,
    max_refs: int = 3,
) -> list[dict]:
    """Pick up to max_refs place photos closest to the target camera angle.

    Scoring: circular angular distance (compass) + weighted absolute tilt delta.
    Returns: [{"id", "hint", "file_path"}, ...] sorted by proximity.
    """
    photos = get_place_photos(place_id)
    if not photos:
        return []

    def distance(photo):
        d = 0.0
        if target_compass is not None and photo["compass_heading"] is not None:
            diff = abs(photo["compass_heading"] - target_compass) % 360
            d += min(diff, 360 - diff)  # circular
        if target_tilt is not None and photo["camera_tilt"] is not None:
            d += abs(photo["camera_tilt"] - target_tilt) * 2  # weight modestly
        return d

    if target_compass is not None or target_tilt is not None:
        photos.sort(key=distance)

    refs = []
    for p in photos[:max_refs]:
        hint_parts = []
        if p["compass_heading"] is not None:
            hint_parts.append(f"facing {int(p['compass_heading'])}deg")
        if p["camera_tilt"] is not None:
            hint_parts.append(f"tilt {int(p['camera_tilt'])}deg")
        refs.append({
            "id": f"{place_id}_p{p['id']}",
            "hint": ", ".join(hint_parts) if hint_parts else "reference view",
            "file_path": _normalize_library_path(p["file_path"]),
        })
    return refs


def get_place_name(place_id: str) -> Optional[str]:
    if not Path(DATABASE_PATH).exists():
        return None
    conn = _connect()
    row = conn.execute("SELECT name FROM places WHERE place_id = ?", (place_id,)).fetchone()
    conn.close()
    return row["name"] if row else None


# ═══ People ═══

def get_person_photos(user_id: str) -> list[str]:
    """Return file paths for a person's selfies, rebased to local LIBRARY_DIR."""
    if not Path(DATABASE_PATH).exists():
        return []
    conn = _connect()
    rows = conn.execute(
        "SELECT file_path FROM people_selfies WHERE user_id = ?", (user_id,),
    ).fetchall()
    conn.close()
    return [_normalize_library_path(r["file_path"]) for r in rows]


def get_person_name(user_id: str) -> Optional[str]:
    if not Path(DATABASE_PATH).exists():
        return None
    conn = _connect()
    row = conn.execute("SELECT name FROM people WHERE user_id = ?", (user_id,)).fetchone()
    conn.close()
    return row["name"] if row else None
