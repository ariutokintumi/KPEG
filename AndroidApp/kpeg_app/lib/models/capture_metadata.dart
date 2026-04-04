import 'detected_face.dart';

class CaptureMetadata {
  // Requeridos
  final String orientation;
  final int timestamp;
  final String timezone;
  final String deviceModel;
  final bool isOutdoor;

  // Ubicación (opcionales)
  final double? lat;
  final double? lng;
  final double? altitude;
  final double? compassHeading;
  final double? cameraTilt;

  // Personas detectadas
  final List<DetectedFace> people;

  // Contexto del usuario (opcionales)
  final String? sceneHint;
  final List<String> tags;

  // Cámara (opcionales)
  final Map<String, dynamic>? lensInfo;
  final bool? flashUsed;

  // Interior (solo si !isOutdoor)
  final String? indoorPlaceId;
  final String? indoorDescription;

  CaptureMetadata({
    required this.orientation,
    required this.timestamp,
    required this.timezone,
    required this.deviceModel,
    required this.isOutdoor,
    this.lat,
    this.lng,
    this.altitude,
    this.compassHeading,
    this.cameraTilt,
    this.people = const [],
    this.sceneHint,
    this.tags = const [],
    this.lensInfo,
    this.flashUsed,
    this.indoorPlaceId,
    this.indoorDescription,
  });

  /// Genera el JSON que espera POST /encode.
  /// Omite campos null automáticamente.
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'orientation': orientation,
      'timestamp': timestamp,
      'timezone': timezone,
      'device_model': deviceModel,
      'is_outdoor': isOutdoor,
    };

    if (lat != null) json['lat'] = lat;
    if (lng != null) json['lng'] = lng;
    if (altitude != null) json['altitude'] = altitude;
    if (compassHeading != null) json['compass_heading'] = compassHeading;
    if (cameraTilt != null) json['camera_tilt'] = cameraTilt;

    final taggedPeople = people
        .where((f) => f.isTagged)
        .map((f) => f.toMetadataJson())
        .whereType<Map<String, dynamic>>()
        .toList();
    if (taggedPeople.isNotEmpty) json['people'] = taggedPeople;

    if (sceneHint != null && sceneHint!.isNotEmpty) json['scene_hint'] = sceneHint;
    if (tags.isNotEmpty) json['tags'] = tags;

    if (lensInfo != null) json['lens_info'] = lensInfo;
    if (flashUsed != null) json['flash_used'] = flashUsed;

    if (!isOutdoor) {
      if (indoorPlaceId != null) json['indoor_place_id'] = indoorPlaceId;
      if (indoorDescription != null) json['indoor_description'] = indoorDescription;
    }

    return json;
  }
}
