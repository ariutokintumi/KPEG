import 'detected_face.dart';

class CaptureMetadata {
  // Required
  final String orientation;
  final int timestamp;
  final String timezone;
  final String deviceModel;
  final bool isOutdoor;

  // Location (optional)
  final double? lat;
  final double? lng;
  final double? compassHeading;
  final double? cameraTilt;

  // People detected
  final List<DetectedFace> people;

  // User context (optional)
  final String? sceneHint;
  final List<String> tags;

  // Camera (optional)
  final Map<String, dynamic>? lensInfo;
  final bool? flashUsed;

  // Indoor (only if !isOutdoor)
  final String? indoorPlaceId;
  final String? indoorDescription;

  // Session
  final String? sessionId;

  CaptureMetadata({
    required this.orientation,
    required this.timestamp,
    required this.timezone,
    required this.deviceModel,
    required this.isOutdoor,
    this.lat,
    this.lng,
    this.compassHeading,
    this.cameraTilt,
    this.people = const [],
    this.sceneHint,
    this.tags = const [],
    this.lensInfo,
    this.flashUsed,
    this.indoorPlaceId,
    this.indoorDescription,
    this.sessionId,
  });

  /// Build JSON for POST /encode. Omits null fields.
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
      if (indoorDescription != null && indoorDescription!.isNotEmpty) {
        json['indoor_description'] = indoorDescription;
      }
    }

    if (sessionId != null) json['session_id'] = sessionId;

    return json;
  }
}
