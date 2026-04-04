import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../config/app_config.dart';
import '../models/person.dart';
import '../services/people_repository.dart';

class PeopleProvider extends ChangeNotifier {
  final PeopleRepository _repo;

  PeopleProvider({required PeopleRepository repo}) : _repo = repo;

  List<Person> people = [];

  Future<void> loadPeople() async {
    people = await _repo.getAll();
    notifyListeners();
  }

  /// Add person with multiple selfies + face embeddings
  Future<Person> addPersonWithSelfies(
    String name,
    List<({File photo, Uint8List embedding})> selfies,
  ) async {
    final appDir = await getApplicationDocumentsDirectory();
    final photosDir = Directory(p.join(appDir.path, AppConfig.peoplePhotosDir));
    if (!await photosDir.exists()) await photosDir.create(recursive: true);

    // Copy selfies to app storage and build embedding records
    final savedSelfies = <({Uint8List embedding, String selfiePath})>[];
    for (int i = 0; i < selfies.length; i++) {
      final selfie = selfies[i];
      final ext = p.extension(selfie.photo.path);
      final ts = DateTime.now().millisecondsSinceEpoch + i;
      final destPath = p.join(photosDir.path, 'selfie_$ts$ext');
      await selfie.photo.copy(destPath);
      savedSelfies.add((embedding: selfie.embedding, selfiePath: destPath));
    }

    final person = Person(name: name);
    final saved = await _repo.insertWithEmbeddings(person, savedSelfies);
    await loadPeople();
    return saved;
  }

  /// Get selfie paths for a person (for detail view)
  Future<List<String>> getSelfiePaths(int personId) async {
    return _repo.getSelfiePaths(personId);
  }

  Future<void> deletePerson(int id) async {
    await _repo.delete(id);
    await loadPeople();
  }
}
