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
      version: 10,
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
        user_id TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        selfie_count INTEGER NOT NULL DEFAULT 0,
        thumbnail_path TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE face_embeddings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        person_id INTEGER NOT NULL,
        embedding BLOB NOT NULL,
        FOREIGN KEY (person_id) REFERENCES people(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE places (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        place_id TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        description TEXT,
        lat REAL,
        lng REAL,
        photo_count INTEGER NOT NULL DEFAULT 0,
        thumbnail_path TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE objects (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        object_id TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        category TEXT NOT NULL DEFAULT 'other',
        photo_count INTEGER NOT NULL DEFAULT 0,
        thumbnail_path TEXT,
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
        scene_hint TEXT,
        thumbnail_path TEXT,
        image_id TEXT,
        hedera_file_id TEXT,
        hedera_topic_id TEXT,
        hedera_topic_tx_id TEXT,
        hedera_nft_token_id TEXT,
        hedera_nft_serial TEXT,
        hedera_network TEXT
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 10) {
      await db.execute('DROP TABLE IF EXISTS face_embeddings');
      await db.execute('DROP TABLE IF EXISTS people');
      await db.execute('DROP TABLE IF EXISTS places');
      await db.execute('DROP TABLE IF EXISTS objects');
      await db.execute('DROP TABLE IF EXISTS kpeg_files');
      await _onCreate(db, newVersion);
    }
  }
}
