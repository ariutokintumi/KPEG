import 'detected_face.dart';

class CaptureMetadata {
  final String orientation;
  final int timestamp;
  final String timezone;
  final String deviceModel;
  final bool isOutdoor;

  final double? lat;
  final double? lng;
  final double? compassHeading;
  final double? cameraTilt;

  final List<DetectedFace> people;

  final String? sceneHint;
  final List<String> tags;

  // Lens info — mandatory (best effort)
  final Map<String, dynamic> lensInfo;
  final bool flashUsed;

  final String? indoorPlaceId;
  final String? indoorDescription;

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
    this.lensInfo = const {},
    this.flashUsed = false,
    this.indoorPlaceId,
    this.indoorDescription,
    this.sessionId,
  });

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

    // People: tagged faces keep their user_id, untagged get "unknown_N"
    // Excluded faces (user removed tag) are omitted entirely
    // unknown_N numbering: left-to-right by bbox left coordinate
    final nonExcluded =
        people.where((f) => !f.excluded).toList();
    // Sort by left coordinate for unknown_N numbering
    nonExcluded.sort(
        (a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));

    int unknownCounter = 0;
    final peopleJson = <Map<String, dynamic>>[];
    for (final face in nonExcluded) {
      final entry = face.toMetadataJson(
        unknownIndex: face.isTagged ? null : unknownCounter,
      );
      if (entry != null) {
        if (!face.isTagged) unknownCounter++;
        peopleJson.add(entry);
      }
    }
    if (peopleJson.isNotEmpty) json['people'] = peopleJson;

    if (sceneHint != null && sceneHint!.isNotEmpty) {
      json['scene_hint'] = sceneHint;
    }
    if (tags.isNotEmpty) json['tags'] = tags;

    // Lens info — always include
    if (lensInfo.isNotEmpty) json['lens_info'] = lensInfo;
    json['flash_used'] = flashUsed;

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
