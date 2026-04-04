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
      version: 5,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // People: local cache of server-side people library
    await db.execute('''
      CREATE TABLE people (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        selfie_count INTEGER NOT NULL DEFAULT 0,
        thumbnail_path TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE places (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        place_id TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        building TEXT,
        floor TEXT,
        description TEXT,
        lat REAL,
        lng REAL,
        photo_count INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
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
    // Rebuild from scratch for hackathon — data is on server anyway
    if (oldVersion < 5) {
      await db.execute('DROP TABLE IF EXISTS face_embeddings');
      await db.execute('DROP TABLE IF EXISTS people');
      await db.execute('''
        CREATE TABLE people (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id TEXT NOT NULL UNIQUE,
          name TEXT NOT NULL,
          selfie_count INTEGER NOT NULL DEFAULT 0,
          thumbnail_path TEXT,
          created_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS places (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          place_id TEXT NOT NULL UNIQUE,
          name TEXT NOT NULL,
          building TEXT,
          floor TEXT,
          description TEXT,
          lat REAL,
          lng REAL,
          photo_count INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL
        )
      ''');
    }
  }
}
