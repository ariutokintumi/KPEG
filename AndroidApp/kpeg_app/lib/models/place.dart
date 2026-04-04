class Place {
  final int? id;
  final String placeId;
  final String name;
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
    this.description,
    this.lat,
    this.lng,
    this.photoCount = 0,
    this.thumbnailPath,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  static String generatePlaceId(String name) {
    final safeName = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
    final ts = DateTime.now().millisecondsSinceEpoch % 100000;
    return 'place_${safeName}_$ts';
  }

  String get displayLabel => name;

  Map<String, dynamic> toMap() {
    return {
      if (id != null && id! > 0) 'id': id,
      'place_id': placeId,
      'name': name,
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
    );
  }
}

/// Metadata for each photo of a place (sent to server for reconstruction)
class PlacePhotoMeta {
  final double? lat;
  final double? lng;
  final double? compassHeading;
  final double? cameraTilt;
  final int timestamp;

  PlacePhotoMeta({
    this.lat,
    this.lng,
    this.compassHeading,
    this.cameraTilt,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{'timestamp': timestamp};
    if (lat != null) json['lat'] = lat;
    if (lng != null) json['lng'] = lng;
    if (compassHeading != null) json['compass_heading'] = compassHeading;
    if (cameraTilt != null) json['camera_tilt'] = cameraTilt;
    return json;
  }
}
