import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/person.dart';
import '../services/api_service.dart';
import '../services/face_recognition_service.dart';
import '../services/people_repository.dart';

class PeopleProvider extends ChangeNotifier {
  final PeopleRepository _repo;
  final ApiService _api;
  final FaceCropService _faceCrop;

  PeopleProvider({
    required PeopleRepository repo,
    required ApiService api,
    required FaceCropService faceCrop,
  })  : _repo = repo,
        _api = api,
        _faceCrop = faceCrop;

  List<Person> people = [];

  Future<void> loadPeople() async {
    people = await _repo.getAll();
    notifyListeners();
  }

  Future<void> syncFromServer() async {
    try {
      final serverList = await _api.listPeople();
      if (serverList.isNotEmpty) {
        final serverPeople =
            serverList.map((j) => Person.fromApiJson(j)).toList();
        await _repo.syncFromServer(serverPeople);
      }
      await loadPeople();
    } catch (_) {
      await loadPeople();
    }
  }

  /// Register person: extract embeddings locally + send selfies to server
  Future<Person> addPerson(
    String name,
    List<File> selfieFiles, {
    String? thumbnailPath,
  }) async {
    final visibleUserId = Person.generateUserId(name);

    // Extract face embeddings from each selfie (for local identification)
    final embeddings = <Uint8List>[];
    for (final file in selfieFiles) {
      try {
        final emb = await _faceCrop.extractSelfieEmbedding(file);
        embeddings.add(emb);
      } catch (_) {
        // Skip selfies where embedding extraction fails
      }
    }

    // Save locally with embeddings (privacy-first identification)
    final person = Person(
      visibleUserId: visibleUserId,
      name: name,
      selfieCount: selfieFiles.length,
      thumbnailPath: thumbnailPath,
    );
    final saved = await _repo.insertWithEmbeddings(person, embeddings);

    // Also register on server (for reconstruction purposes)
    try {
      await _api.registerPerson(
        userId: visibleUserId,
        name: name,
        selfies: selfieFiles,
      );
    } catch (_) {
      // Server registration can fail — local data is the priority
    }

    // Reload embeddings cache for immediate identification
    await _faceCrop.loadEmbeddings();
    await loadPeople();
    return saved;
  }

  Future<void> deletePerson(String visibleUserId) async {
    await _repo.deleteByUserId(visibleUserId);
    try {
      await _api.deletePerson(visibleUserId);
    } catch (_) {}
    await _faceCrop.loadEmbeddings();
    await loadPeople();
  }
}
