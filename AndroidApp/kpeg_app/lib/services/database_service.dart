import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseService {
  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'kpeg.db');

    return openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE people (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        reference_photo_path TEXT,
        selfie_count INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE face_embeddings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        person_id INTEGER NOT NULL,
        embedding BLOB NOT NULL,
        selfie_path TEXT NOT NULL,
        FOREIGN KEY (person_id) REFERENCES people(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE kpeg_files (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        filename TEXT NOT NULL,
        file_path TEXT NOT NULL,
        captured_at TEXT NOT NULL,
        original_photo_path TEXT,
        file_size_bytes INTEGER NOT NULL,
        scene_hint TEXT
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add face_embeddings table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS face_embeddings (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          person_id INTEGER NOT NULL,
          embedding BLOB NOT NULL,
          selfie_path TEXT NOT NULL,
          FOREIGN KEY (person_id) REFERENCES people(id) ON DELETE CASCADE
        )
      ''');
      // Add selfie_count column to people
      try {
        await db.execute('ALTER TABLE people ADD COLUMN selfie_count INTEGER NOT NULL DEFAULT 0');
      } catch (_) {
        // Column might already exist
      }
    }
  }
}
