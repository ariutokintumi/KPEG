import 'dart:io';
import 'dart:typed_data';
import '../models/person.dart';
import 'database_service.dart';

class FaceEmbeddingRecord {
  final int? id;
  final int personId;
  final Uint8List embedding;
  final String selfiePath;

  FaceEmbeddingRecord({
    this.id,
    required this.personId,
    required this.embedding,
    required this.selfiePath,
  });
}

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

  /// Insert person with face embeddings from selfies
  Future<Person> insertWithEmbeddings(
    Person person,
    List<({Uint8List embedding, String selfiePath})> selfies,
  ) async {
    final db = await _dbService.database;

    final personWithCount = Person(
      name: person.name,
      referencePhotoPath: selfies.isNotEmpty ? selfies.first.selfiePath : null,
      selfieCount: selfies.length,
    );

    final id = await db.insert('people', personWithCount.toMap());

    // Insert all embeddings
    for (final selfie in selfies) {
      await db.insert('face_embeddings', {
        'person_id': id,
        'embedding': selfie.embedding,
        'selfie_path': selfie.selfiePath,
      });
    }

    return personWithCount.copyWith(id: id);
  }

  /// Get all embeddings for face matching
  Future<List<({int personId, String personName, Uint8List embedding})>> getAllEmbeddings() async {
    final db = await _dbService.database;
    final maps = await db.rawQuery('''
      SELECT fe.embedding, fe.person_id, p.name
      FROM face_embeddings fe
      JOIN people p ON p.id = fe.person_id
    ''');

    return maps.map((m) => (
      personId: m['person_id'] as int,
      personName: m['name'] as String,
      embedding: m['embedding'] as Uint8List,
    )).toList();
  }

  /// Get selfie paths for a person
  Future<List<String>> getSelfiePaths(int personId) async {
    final db = await _dbService.database;
    final maps = await db.query('face_embeddings',
        columns: ['selfie_path'],
        where: 'person_id = ?',
        whereArgs: [personId]);
    return maps.map((m) => m['selfie_path'] as String).toList();
  }

  Future<void> update(Person person) async {
    final db = await _dbService.database;
    await db.update('people', person.toMap(),
        where: 'id = ?', whereArgs: [person.id]);
  }

  Future<void> delete(int id) async {
    final db = await _dbService.database;

    // Delete selfie files from disk
    final selfiePaths = await getSelfiePaths(id);
    for (final path in selfiePaths) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }

    // Delete reference photo
    final person = await getById(id);
    if (person?.referencePhotoPath != null) {
      final file = File(person!.referencePhotoPath!);
      if (await file.exists()) await file.delete();
    }

    // DB cascade deletes face_embeddings
    await db.delete('people', where: 'id = ?', whereArgs: [id]);
  }
}
