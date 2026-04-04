import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/place.dart';
import '../services/api_service.dart';
import '../services/places_repository.dart';

class PlacesProvider extends ChangeNotifier {
  final PlacesRepository _repo;
  final ApiService _api;

  PlacesProvider({required PlacesRepository repo, required ApiService api})
      : _repo = repo,
        _api = api;

  List<Place> places = [];

  Future<void> loadPlaces() async {
    places = await _repo.getAll();
    notifyListeners();
  }

  Future<void> syncFromServer() async {
    try {
      final serverList = await _api.listPlaces();
      if (serverList.isNotEmpty) {
        final serverPlaces =
            serverList.map((j) => Place.fromApiJson(j)).toList();
        await _repo.syncFromServer(serverPlaces);
      }
      await loadPlaces();
    } catch (_) {
      await loadPlaces();
    }
  }

  /// Register place with photos + per-photo metadata (coords, angle, timestamp)
  Future<Place> addPlace({
    required String name,
    String? description,
    double? lat,
    double? lng,
    required List<File> photos,
    List<PlacePhotoMeta>? photosMeta,
  }) async {
    final placeId = Place.generatePlaceId(name);

    await _api.registerPlace(
      placeId: placeId,
      name: name,
      photos: photos,
      photosMetadata: photosMeta?.map((m) => m.toJson()).toList(),
    );

    String? thumbnailPath;
    if (photos.isNotEmpty) {
      try {
        thumbnailPath = await _saveThumbnail(photos.first, 'place_$placeId');
      } catch (_) {}
    }

    final place = Place(
      placeId: placeId,
      name: name,
      description: description,
      lat: lat,
      lng: lng,
      photoCount: photos.length,
      thumbnailPath: thumbnailPath,
    );
    await _repo.upsert(place);
    await loadPlaces();
    return place;
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

  Future<void> deletePlace(String placeId) async {
    try {
      await _api.deletePlace(placeId);
    } catch (_) {}
    await _repo.deleteByPlaceId(placeId);
    await loadPlaces();
  }

  Future<List<Place>> findNearby(double lat, double lng) async {
    return _repo.findNearby(lat, lng);
  }
}
