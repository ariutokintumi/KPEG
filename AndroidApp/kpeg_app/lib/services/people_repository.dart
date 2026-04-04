import 'package:sqflite/sqflite.dart';
import '../models/person.dart';
import 'database_service.dart';

/// Local cache of people registered on the server.
class PeopleRepository {
  final DatabaseService _dbService;

  PeopleRepository(this._dbService);

  Future<List<Person>> getAll() async {
    final db = await _dbService.database;
    final maps = await db.query('people', orderBy: 'name ASC');
    return maps.map((m) => Person.fromMap(m)).toList();
  }

  Future<Person?> getByUserId(String visibleUserId) async {
    final db = await _dbService.database;
    final maps = await db.query('people',
        where: 'user_id = ?', whereArgs: [visibleUserId]);
    if (maps.isEmpty) return null;
    return Person.fromMap(maps.first);
  }

  Future<void> upsert(Person person) async {
    final db = await _dbService.database;
    await db.insert('people', person.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteByUserId(String visibleUserId) async {
    final db = await _dbService.database;
    await db.delete('people', where: 'user_id = ?', whereArgs: [visibleUserId]);
  }

  /// Replace local cache with server data
  Future<void> syncFromServer(List<Person> serverPeople) async {
    final db = await _dbService.database;
    await db.delete('people'); // Clear cache
    for (final person in serverPeople) {
      await db.insert('people', person.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }
}
