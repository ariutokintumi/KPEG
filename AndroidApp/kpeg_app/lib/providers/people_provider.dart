import 'dart:io';
import 'package:flutter/material.dart';
import '../models/person.dart';
import '../services/api_service.dart';
import '../services/people_repository.dart';

class PeopleProvider extends ChangeNotifier {
  final PeopleRepository _repo;
  final ApiService _api;

  PeopleProvider({required PeopleRepository repo, required ApiService api})
      : _repo = repo,
        _api = api;

  List<Person> people = [];

  /// Load people from local cache
  Future<void> loadPeople() async {
    people = await _repo.getAll();
    notifyListeners();
  }

  /// Sync people list from server, update local cache
  Future<void> syncFromServer() async {
    try {
      final serverList = await _api.listPeople();
      // Only overwrite local cache if server returned data
      if (serverList.isNotEmpty) {
        final serverPeople = serverList.map((j) => Person.fromApiJson(j)).toList();
        await _repo.syncFromServer(serverPeople);
      }
      await loadPeople();
    } catch (_) {
      // If server unavailable, keep local cache
      await loadPeople();
    }
  }

  /// Register person on server + cache locally
  Future<Person> addPerson(String name, List<File> selfies, {String? thumbnailPath}) async {
    final visibleUserId = Person.generateUserId(name);

    // Register on server
    await _api.registerPerson(
      userId: visibleUserId,
      name: name,
      selfies: selfies,
    );

    // Cache locally
    final person = Person(
      visibleUserId: visibleUserId,
      name: name,
      selfieCount: selfies.length,
      thumbnailPath: thumbnailPath,
    );
    await _repo.upsert(person);
    await loadPeople();
    return person;
  }

  /// Delete person from server + local cache
  Future<void> deletePerson(String visibleUserId) async {
    try {
      await _api.deletePerson(visibleUserId);
    } catch (_) {
      // Continue with local delete even if server fails
    }
    await _repo.deleteByUserId(visibleUserId);
    await loadPeople();
  }
}
