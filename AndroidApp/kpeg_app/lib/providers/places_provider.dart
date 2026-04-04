import 'dart:io';
import 'package:flutter/material.dart';
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
        final serverPlaces = serverList.map((j) => Place.fromApiJson(j)).toList();
        await _repo.syncFromServer(serverPlaces);
      }
      await loadPlaces();
    } catch (_) {
      await loadPlaces();
    }
  }

  /// Register place on server + cache locally
  Future<Place> addPlace({
    required String name,
    String? building,
    String? floor,
    String? description,
    double? lat,
    double? lng,
    required List<File> photos,
  }) async {
    final placeId = Place.generatePlaceId(name, building: building, floor: floor);

    await _api.registerPlace(
      placeId: placeId,
      name: name,
      building: building,
      floor: floor,
      photos: photos,
    );

    final place = Place(
      placeId: placeId,
      name: name,
      building: building,
      floor: floor,
      description: description,
      lat: lat,
      lng: lng,
      photoCount: photos.length,
    );
    await _repo.upsert(place);
    await loadPlaces();
    return place;
  }

  Future<void> deletePlace(String placeId) async {
    try {
      await _api.deletePlace(placeId);
    } catch (_) {}
    await _repo.deleteByPlaceId(placeId);
    await loadPlaces();
  }

  /// Find places near coordinates
  Future<List<Place>> findNearby(double lat, double lng) async {
    return _repo.findNearby(lat, lng);
  }
}
