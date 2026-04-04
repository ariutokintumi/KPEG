import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/indoor_object.dart';
import '../services/api_service.dart';
import '../services/objects_repository.dart';

class ObjectsProvider extends ChangeNotifier {
  final ObjectsRepository _repo;
  final ApiService _api;

  ObjectsProvider({required ObjectsRepository repo, required ApiService api})
      : _repo = repo,
        _api = api;

  List<IndoorObject> objects = [];

  Future<void> loadObjects() async {
    objects = await _repo.getAll();
    notifyListeners();
  }

  Future<void> syncFromServer() async {
    try {
      final serverList = await _api.listObjects();
      if (serverList.isNotEmpty) {
        final serverObjects =
            serverList.map((j) => IndoorObject.fromApiJson(j)).toList();
        await _repo.syncFromServer(serverObjects);
      }
      await loadObjects();
    } catch (_) {
      await loadObjects();
    }
  }

  Future<IndoorObject> addObject({
    required String name,
    required String category,
    required List<File> photos,
  }) async {
    final objectId = IndoorObject.generateObjectId(name);

    await _api.registerObject(
      objectId: objectId,
      name: name,
      category: category,
      photos: photos,
    );

    String? thumbnailPath;
    if (photos.isNotEmpty) {
      try {
        thumbnailPath = await _saveThumbnail(photos.first, 'obj_$objectId');
      } catch (_) {}
    }

    final obj = IndoorObject(
      objectId: objectId,
      name: name,
      category: category,
      photoCount: photos.length,
      thumbnailPath: thumbnailPath,
    );
    await _repo.upsert(obj);
    await loadObjects();
    return obj;
  }

  Future<String> _saveThumbnail(File photo, String prefix) async {
    final bytes = await photo.readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) throw Exception('decode failed');
    final resized = img.copyResize(image,
        width: image.width >= image.height ? 120 : null,
        height: image.height > image.width ? 120 : null);
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'library_thumbs'));
    if (!await dir.exists()) await dir.create(recursive: true);
    final path = p.join(
        dir.path, '${prefix}_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await File(path).writeAsBytes(img.encodeJpg(resized, quality: 60));
    return path;
  }

  Future<void> deleteObject(String objectId) async {
    try {
      await _api.deleteObject(objectId);
    } catch (_) {}
    await _repo.deleteByObjectId(objectId);
    await loadObjects();
  }
}
