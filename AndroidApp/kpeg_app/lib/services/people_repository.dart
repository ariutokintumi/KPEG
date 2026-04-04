import 'dart:io';
import '../models/person.dart';
import 'database_service.dart';

class PeopleRepository {
  final DatabaseService _dbService;

  PeopleRepository(this._dbService);

  Future<List<Person>> getAll() async {
    final db = await _dbService.database;
    final maps = await db.query('people', orderBy: 'name ASC');
    return maps.map((m) => Person.fromMap(m)).toList();
  }

  Future<Person?> getById(int id) async {
    final db = await _dbService.database;
    final maps = await db.query('people', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Person.fromMap(maps.first);
  }

  Future<Person> insert(Person person) async {
    final db = await _dbService.database;
    final id = await db.insert('people', person.toMap());
    return person.copyWith(id: id);
  }

  Future<void> update(Person person) async {
    final db = await _dbService.database;
    await db.update('people', person.toMap(),
        where: 'id = ?', whereArgs: [person.id]);
  }

  Future<void> delete(int id) async {
    final db = await _dbService.database;
    // Borrar foto de referencia del disco
    final person = await getById(id);
    if (person?.referencePhotoPath != null) {
      final file = File(person!.referencePhotoPath!);
      if (await file.exists()) await file.delete();
    }
    await db.delete('people', where: 'id = ?', whereArgs: [id]);
  }
}
