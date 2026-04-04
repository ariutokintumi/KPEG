import 'dart:typed_data';
import 'package:sqflite/sqflite.dart';
import '../models/person.dart';
import 'database_service.dart';

/// Local storage for people + face embeddings (privacy-first identification).
/// Also serves as cache for server-synced people data.
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

  /// Insert person + face embeddings for local identification
  Future<Person> insertWithEmbeddings(
    Person person,
    List<Uint8List> embeddings,
  ) async {
    final db = await _dbService.database;
    final id = await db.insert('people', person.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);

    for (final embedding in embeddings) {
      await db.insert('face_embeddings', {
        'person_id': id,
        'embedding': embedding,
      });
    }

    return person.copyWith(id: id);
  }

  /// Get all embeddings for on-device face matching
  Future<List<({int personId, String personName, Uint8List embedding})>>
      getAllEmbeddings() async {
    final db = await _dbService.database;
    final maps = await db.rawQuery('''
      SELECT fe.embedding, fe.person_id, p.name
      FROM face_embeddings fe
      JOIN people p ON p.id = fe.person_id
    ''');

    return maps
        .map((m) => (
              personId: m['person_id'] as int,
              personName: m['name'] as String,
              embedding: m['embedding'] as Uint8List,
            ))
        .toList();
  }

  Future<void> upsert(Person person) async {
    final db = await _dbService.database;
    await db.insert('people', person.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteByUserId(String visibleUserId) async {
    final db = await _dbService.database;
    // Get person id first to cascade delete embeddings
    final maps = await db.query('people',
        where: 'user_id = ?', whereArgs: [visibleUserId]);
    if (maps.isNotEmpty) {
      final id = maps.first['id'] as int;
      await db.delete('face_embeddings',
          where: 'person_id = ?', whereArgs: [id]);
    }
    await db.delete('people', where: 'user_id = ?', whereArgs: [visibleUserId]);
  }

  /// Merge server data without destroying local embeddings.
  /// Adds new people from server, updates names, but keeps local embeddings intact.
  Future<void> syncFromServer(List<Person> serverPeople) async {
    final db = await _dbService.database;
    for (final person in serverPeople) {
      final existing = await db.query('people',
          where: 'user_id = ?', whereArgs: [person.visibleUserId]);
      if (existing.isEmpty) {
        // New person from server — insert without embeddings
        await db.insert('people', person.toMap(),
            conflictAlgorithm: ConflictAlgorithm.ignore);
      } else {
        // Existing person — update name/selfie_count but keep id + embeddings
        await db.update(
          'people',
          {'name': person.name, 'selfie_count': person.selfieCount},
          where: 'user_id = ?',
          whereArgs: [person.visibleUserId],
        );
      }
    }
  }
}
