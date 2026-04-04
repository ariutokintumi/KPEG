import 'dart:io';
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

  Future<Person> addPerson(String name, File referencePhoto) async {
    // Copiar foto de referencia al directorio de la app
    final appDir = await getApplicationDocumentsDirectory();
    final photosDir = Directory(p.join(appDir.path, AppConfig.peoplePhotosDir));
    if (!await photosDir.exists()) await photosDir.create(recursive: true);

    final ext = p.extension(referencePhoto.path);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final destPath = p.join(photosDir.path, 'person_$timestamp$ext');
    await referencePhoto.copy(destPath);

    final person = Person(
      name: name,
      referencePhotoPath: destPath,
    );

    final saved = await _repo.insert(person);
    await loadPeople();
    return saved;
  }

  Future<void> deletePerson(int id) async {
    await _repo.delete(id);
    await loadPeople();
  }
}
