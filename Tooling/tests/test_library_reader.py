"""Tests for library_reader against a temp SQLite DB mimicking Jose's schema."""
import os
import sqlite3
import tempfile
from pathlib import Path
from unittest.mock import patch
import pytest


@pytest.fixture
def temp_db():
    """Create temp DB with Jose's schema + seed data, patch DATABASE_PATH."""
    fd, path = tempfile.mkstemp(suffix=".db")
    os.close(fd)
    conn = sqlite3.connect(path)
    conn.executescript("""
        CREATE TABLE people (user_id TEXT PRIMARY KEY, name TEXT NOT NULL,
                             selfie_count INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL);
        CREATE TABLE people_selfies (id INTEGER PRIMARY KEY AUTOINCREMENT, user_id TEXT NOT NULL,
                                     file_path TEXT NOT NULL, timestamp INTEGER NOT NULL);
        CREATE TABLE places (place_id TEXT PRIMARY KEY, name TEXT NOT NULL,
                             photo_count INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL);
        CREATE TABLE place_photos (id INTEGER PRIMARY KEY AUTOINCREMENT, place_id TEXT NOT NULL,
                                    file_path TEXT NOT NULL, lat REAL, lng REAL,
                                    compass_heading REAL, camera_tilt REAL, timestamp INTEGER NOT NULL);
        CREATE TABLE objects (object_id TEXT PRIMARY KEY, name TEXT NOT NULL,
                              category TEXT NOT NULL DEFAULT 'other',
                              photo_count INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL);
        CREATE TABLE object_photos (id INTEGER PRIMARY KEY AUTOINCREMENT, object_id TEXT NOT NULL,
                                    file_path TEXT NOT NULL);
    """)
    conn.executemany(
        "INSERT INTO objects VALUES (?, ?, ?, ?, ?)",
        [
            ("obj_walnut_desk", "Walnut desk", "furniture", 2, "2026-04-04"),
            ("obj_brass_lamp", "Brass pendant lamp", "lighting", 1, "2026-04-04"),
            ("obj_red_couch", "Red velvet couch", "furniture", 3, "2026-04-04"),
        ],
    )
    conn.executemany(
        "INSERT INTO places VALUES (?, ?, ?, ?)",
        [("place_hq_2f", "HQ 2nd floor", 3, "2026-04-04")],
    )
    conn.executemany(
        "INSERT INTO place_photos (place_id, file_path, lat, lng, compass_heading, camera_tilt, timestamp) "
        "VALUES (?, ?, ?, ?, ?, ?, ?)",
        [
            ("place_hq_2f", "/lib/a.jpg", 40.0, -3.0, 0.0, 0.0, 1000),
            ("place_hq_2f", "/lib/b.jpg", 40.0, -3.0, 90.0, -5.0, 1001),
            ("place_hq_2f", "/lib/c.jpg", 40.0, -3.0, 180.0, 10.0, 1002),
        ],
    )
    conn.executemany(
        "INSERT INTO people VALUES (?, ?, ?, ?)",
        [("usr_carlos_02", "Carlos", 3, "2026-04-04")],
    )
    conn.executemany(
        "INSERT INTO people_selfies (user_id, file_path, timestamp) VALUES (?, ?, ?)",
        [("usr_carlos_02", "/lib/c1.jpg", 1000), ("usr_carlos_02", "/lib/c2.jpg", 1001)],
    )
    conn.commit()
    conn.close()

    with patch("kpeg.library_reader.DATABASE_PATH", Path(path)):
        yield path
    os.unlink(path)


def test_get_objects_catalog(temp_db):
    from kpeg.library_reader import get_objects_catalog
    objects = get_objects_catalog()
    assert len(objects) == 3
    ids = [o["id"] for o in objects]
    assert "obj_walnut_desk" in ids
    assert "obj_brass_lamp" in ids


def test_get_objects_catalog_limit(temp_db):
    from kpeg.library_reader import get_objects_catalog
    objects = get_objects_catalog(limit=2)
    assert len(objects) == 2


def test_format_objects_catalog_for_prompt(temp_db):
    from kpeg.library_reader import get_objects_catalog, format_objects_catalog_for_prompt
    text = format_objects_catalog_for_prompt(get_objects_catalog())
    assert "obj_walnut_desk" in text
    assert "Walnut desk" in text
    assert "furniture" in text
    assert text.count("\n") == 2  # 3 entries, 2 newlines


def test_format_objects_catalog_empty():
    from kpeg.library_reader import format_objects_catalog_for_prompt
    assert "empty" in format_objects_catalog_for_prompt([]).lower()


def test_get_object_info(temp_db):
    from kpeg.library_reader import get_object_info
    info = get_object_info("obj_walnut_desk")
    assert info == {"name": "Walnut desk", "category": "furniture"}
    assert get_object_info("does_not_exist") is None


def test_select_best_place_refs_by_compass(temp_db):
    from kpeg.library_reader import select_best_place_refs
    # Target 85° → nearest is 90° photo
    refs = select_best_place_refs("place_hq_2f", target_compass=85.0, max_refs=1)
    assert len(refs) == 1
    assert "90deg" in refs[0]["hint"]


def test_select_best_place_refs_circular_distance(temp_db):
    from kpeg.library_reader import select_best_place_refs
    # Target 350° → nearest is 0° (distance 10, not 350)
    refs = select_best_place_refs("place_hq_2f", target_compass=350.0, max_refs=1)
    assert len(refs) == 1
    assert "0deg" in refs[0]["hint"]


def test_select_best_place_refs_no_target(temp_db):
    from kpeg.library_reader import select_best_place_refs
    refs = select_best_place_refs("place_hq_2f", max_refs=3)
    assert len(refs) == 3


def test_select_best_place_refs_max_limit(temp_db):
    from kpeg.library_reader import select_best_place_refs
    refs = select_best_place_refs("place_hq_2f", max_refs=2)
    assert len(refs) == 2


def test_select_best_place_refs_nonexistent(temp_db):
    from kpeg.library_reader import select_best_place_refs
    assert select_best_place_refs("does_not_exist") == []


def test_get_place_name(temp_db):
    from kpeg.library_reader import get_place_name
    assert get_place_name("place_hq_2f") == "HQ 2nd floor"
    assert get_place_name("nope") is None


def test_get_person_photos(temp_db):
    from kpeg.library_reader import get_person_photos
    photos = get_person_photos("usr_carlos_02")
    assert len(photos) == 2
    assert "/lib/c1.jpg" in photos


def test_get_person_name(temp_db):
    from kpeg.library_reader import get_person_name
    assert get_person_name("usr_carlos_02") == "Carlos"
    assert get_person_name("nope") is None


def test_no_database_returns_empty():
    """When DB file doesn't exist, all queries return safely."""
    from kpeg.library_reader import (
        get_objects_catalog, get_place_photos, get_person_photos,
        get_object_info, select_best_place_refs,
    )
    with patch("kpeg.library_reader.DATABASE_PATH", Path("/nonexistent/foo.db")):
        assert get_objects_catalog() == []
        assert get_place_photos("x") == []
        assert get_person_photos("x") == []
        assert get_object_info("x") is None
        assert select_best_place_refs("x") == []
