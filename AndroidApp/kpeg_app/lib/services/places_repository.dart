import 'package:sqflite/sqflite.dart';
import '../models/place.dart';
import 'database_service.dart';

class PlacesRepository {
  final DatabaseService _dbService;

  PlacesRepository(this._dbService);

  Future<List<Place>> getAll() async {
    final db = await _dbService.database;
    final maps = await db.query('places', orderBy: 'name ASC');
    return maps.map((m) => Place.fromMap(m)).toList();
  }

  Future<void> upsert(Place place) async {
    final db = await _dbService.database;
    await db.insert('places', place.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteByPlaceId(String placeId) async {
    final db = await _dbService.database;
    await db.delete('places', where: 'place_id = ?', whereArgs: [placeId]);
  }

  /// Find places near given coordinates (simple distance filter)
  Future<List<Place>> findNearby(double lat, double lng, {double radiusKm = 0.5}) async {
    final all = await getAll();
    return all.where((p) {
      if (p.lat == null || p.lng == null) return false;
      final dlat = (p.lat! - lat).abs();
      final dlng = (p.lng! - lng).abs();
      // Rough degree-to-km: 1 degree ≈ 111km lat, ~80km lng at mid-latitudes
      final distKm = dlat * 111 + dlng * 80;
      return distKm < radiusKm;
    }).toList();
  }

  Future<void> syncFromServer(List<Place> serverPlaces) async {
    final db = await _dbService.database;
    for (final place in serverPlaces) {
      await db.insert('places', place.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }
}
