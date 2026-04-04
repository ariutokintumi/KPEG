import sqlite3
import os

DB_PATH = os.path.join(os.path.dirname(__file__), 'kpeg_library.db')


def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute('PRAGMA foreign_keys = ON')
    return conn


def init_db():
    conn = get_db()
    conn.executescript('''
        CREATE TABLE IF NOT EXISTS people (
            user_id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            selfie_count INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS people_selfies (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            file_path TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            FOREIGN KEY (user_id) REFERENCES people(user_id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS places (
            place_id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            photo_count INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS place_photos (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            place_id TEXT NOT NULL,
            file_path TEXT NOT NULL,
            lat REAL,
            lng REAL,
            compass_heading REAL,
            camera_tilt REAL,
            timestamp INTEGER NOT NULL,
            FOREIGN KEY (place_id) REFERENCES places(place_id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS objects (
            object_id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            category TEXT NOT NULL DEFAULT 'other',
            photo_count INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS object_photos (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            object_id TEXT NOT NULL,
            file_path TEXT NOT NULL,
            FOREIGN KEY (object_id) REFERENCES objects(object_id) ON DELETE CASCADE
        );
    ''')
    conn.commit()
    conn.close()


# ── People ──

def insert_person(user_id, name, selfie_paths, selfie_timestamps):
    conn = get_db()
    now = __import__('datetime').datetime.now().isoformat()
    conn.execute(
        'INSERT INTO people (user_id, name, selfie_count, created_at) VALUES (?, ?, ?, ?)',
        (user_id, name, len(selfie_paths), now)
    )
    for path, ts in zip(selfie_paths, selfie_timestamps):
        conn.execute(
            'INSERT INTO people_selfies (user_id, file_path, timestamp) VALUES (?, ?, ?)',
            (user_id, path, ts)
        )
    conn.commit()
    conn.close()


def list_people():
    conn = get_db()
    rows = conn.execute('SELECT user_id, name, selfie_count FROM people ORDER BY name').fetchall()
    conn.close()
    return [{'user_id': r['user_id'], 'name': r['name'], 'photo_count': r['selfie_count']} for r in rows]


def delete_person(user_id):
    conn = get_db()
    conn.execute('DELETE FROM people WHERE user_id = ?', (user_id,))
    conn.commit()
    conn.close()


def person_exists(user_id):
    conn = get_db()
    row = conn.execute('SELECT 1 FROM people WHERE user_id = ?', (user_id,)).fetchone()
    conn.close()
    return row is not None


# ── Places ──

def insert_place(place_id, name, photo_paths, photos_metadata):
    conn = get_db()
    now = __import__('datetime').datetime.now().isoformat()
    conn.execute(
        'INSERT INTO places (place_id, name, photo_count, created_at) VALUES (?, ?, ?, ?)',
        (place_id, name, len(photo_paths), now)
    )
    for i, path in enumerate(photo_paths):
        meta = photos_metadata[i] if i < len(photos_metadata) else {}
        conn.execute(
            'INSERT INTO place_photos (place_id, file_path, lat, lng, compass_heading, camera_tilt, timestamp) '
            'VALUES (?, ?, ?, ?, ?, ?, ?)',
            (place_id, path,
             meta.get('lat'), meta.get('lng'),
             meta.get('compass_heading'), meta.get('camera_tilt'),
             meta.get('timestamp', 0))
        )
    conn.commit()
    conn.close()


def list_places():
    conn = get_db()
    rows = conn.execute('SELECT place_id, name, photo_count FROM places ORDER BY name').fetchall()
    conn.close()
    return [{'place_id': r['place_id'], 'name': r['name'], 'photo_count': r['photo_count']} for r in rows]


def delete_place(place_id):
    conn = get_db()
    conn.execute('DELETE FROM places WHERE place_id = ?', (place_id,))
    conn.commit()
    conn.close()


def place_exists(place_id):
    conn = get_db()
    row = conn.execute('SELECT 1 FROM places WHERE place_id = ?', (place_id,)).fetchone()
    conn.close()
    return row is not None


# ── Objects ──

def insert_object(object_id, name, category, photo_paths):
    conn = get_db()
    now = __import__('datetime').datetime.now().isoformat()
    conn.execute(
        'INSERT INTO objects (object_id, name, category, photo_count, created_at) VALUES (?, ?, ?, ?, ?)',
        (object_id, name, category, len(photo_paths), now)
    )
    for path in photo_paths:
        conn.execute(
            'INSERT INTO object_photos (object_id, file_path) VALUES (?, ?)',
            (object_id, path)
        )
    conn.commit()
    conn.close()


def list_objects():
    conn = get_db()
    rows = conn.execute('SELECT object_id, name, category, photo_count FROM objects ORDER BY name').fetchall()
    conn.close()
    return [{'object_id': r['object_id'], 'name': r['name'], 'category': r['category'], 'photo_count': r['photo_count']} for r in rows]


def delete_object(object_id):
    conn = get_db()
    conn.execute('DELETE FROM objects WHERE object_id = ?', (object_id,))
    conn.commit()
    conn.close()


def object_exists(object_id):
    conn = get_db()
    row = conn.execute('SELECT 1 FROM objects WHERE object_id = ?', (object_id,)).fetchone()
    conn.close()
    return row is not None
