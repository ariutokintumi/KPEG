"""Create stub JPEG files in API/library/ matching the DB entries.

Used to test decoder reference resolution without Jose's real photos.
"""
import sqlite3
from pathlib import Path
from PIL import Image

DB = Path(__file__).resolve().parent.parent / "API" / "kpeg_library.db"
LIB = Path(__file__).resolve().parent.parent / "API" / "library"
LIB.mkdir(parents=True, exist_ok=True)


def main():
    conn = sqlite3.connect(DB)
    paths = set()
    for row in conn.execute("SELECT file_path FROM people_selfies").fetchall():
        paths.add(row[0])
    for row in conn.execute("SELECT file_path FROM object_photos").fetchall():
        paths.add(row[0])
    for row in conn.execute("SELECT file_path FROM place_photos").fetchall():
        paths.add(row[0])
    conn.close()

    print(f"DB contains {len(paths)} unique file paths.")

    created = 0
    skipped = 0
    for stored in paths:
        norm = stored.replace("\\", "/")
        idx = norm.rfind("/library/")
        if idx < 0:
            continue
        tail = norm[idx + len("/library/"):]
        target = LIB / tail
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.exists():
            skipped += 1
            continue
        # Solid-color stub image based on path hash
        h = abs(hash(str(target))) & 0xFFFFFF
        color = (h >> 16 & 0xFF, h >> 8 & 0xFF, h & 0xFF)
        Image.new("RGB", (256, 256), color).save(target, "JPEG", quality=85)
        created += 1

    print(f"Created {created} new stubs, {skipped} already existed.")


if __name__ == "__main__":
    main()
