import 'dart:io';

class Place {
  final int? id;
  final String placeId; // "place_hq_2f_livingroom"
  final String name;
  final String? building;
  final String? floor;
  final String? description;
  final double? lat;
  final double? lng;
  final int photoCount;
  final String? thumbnailPath;
  final DateTime createdAt;

  Place({
    this.id,
    required this.placeId,
    required this.name,
    this.building,
    this.floor,
    this.description,
    this.lat,
    this.lng,
    this.photoCount = 0,
    this.thumbnailPath,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  static String generatePlaceId(String name, {String? building, String? floor}) {
    final parts = ['place'];
    if (building != null && building.isNotEmpty) {
      parts.add(building.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ''));
    }
    if (floor != null && floor.isNotEmpty) {
      parts.add(floor.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ''));
    }
    parts.add(name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_'));
    return parts.join('_');
  }

  /// Full display label
  String get displayLabel {
    final parts = <String>[name];
    if (floor != null && floor!.isNotEmpty) parts.add(floor!);
    if (building != null && building!.isNotEmpty) parts.add(building!);
    return parts.join(', ');
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null && id! > 0) 'id': id,
      'place_id': placeId,
      'name': name,
      'building': building,
      'floor': floor,
      'description': description,
      'lat': lat,
      'lng': lng,
      'photo_count': photoCount,
      'thumbnail_path': thumbnailPath,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Place.fromMap(Map<String, dynamic> map) {
    return Place(
      id: map['id'] as int,
      placeId: map['place_id'] as String,
      name: map['name'] as String,
      building: map['building'] as String?,
      floor: map['floor'] as String?,
      description: map['description'] as String?,
      lat: map['lat'] as double?,
      lng: map['lng'] as double?,
      photoCount: (map['photo_count'] as int?) ?? 0,
      thumbnailPath: map['thumbnail_path'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  factory Place.fromApiJson(Map<String, dynamic> json) {
    return Place(
      placeId: json['place_id'] as String,
      name: json['name'] as String,
      building: json['building'] as String?,
      floor: json['floor'] as String?,
    );
  }
}

/// Photo metadata for a place photo
class PlacePhoto {
  final File file;
  final double? lat;
  final double? lng;
  final double? compassHeading;
  final double? cameraTilt;
  final int timestamp;

  PlacePhoto({
    required this.file,
    this.lat,
    this.lng,
    this.compassHeading,
    this.cameraTilt,
    required this.timestamp,
  });
}
