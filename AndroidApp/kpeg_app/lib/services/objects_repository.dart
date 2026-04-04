import 'package:sqflite/sqflite.dart';
import '../models/indoor_object.dart';
import 'database_service.dart';

class ObjectsRepository {
  final DatabaseService _dbService;

  ObjectsRepository(this._dbService);

  Future<List<IndoorObject>> getAll() async {
    final db = await _dbService.database;
    final maps = await db.query('objects', orderBy: 'name ASC');
    return maps.map((m) => IndoorObject.fromMap(m)).toList();
  }

  Future<void> upsert(IndoorObject obj) async {
    final db = await _dbService.database;
    await db.insert('objects', obj.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteByObjectId(String objectId) async {
    final db = await _dbService.database;
    await db.delete('objects', where: 'object_id = ?', whereArgs: [objectId]);
  }

  Future<void> syncFromServer(List<IndoorObject> serverObjects) async {
    final db = await _dbService.database;
    for (final obj in serverObjects) {
      await db.insert('objects', obj.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }
}
