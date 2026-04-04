import 'dart:ui';

class DetectedFace {
  final Rect boundingBox;
  final int imageWidth;
  final int imageHeight;

  int? personId;
  String? userId;
  String? personName;
  double confidence;

  /// If true, user explicitly removed this face — omit from metadata entirely
  bool excluded;

  DetectedFace({
    required this.boundingBox,
    required this.imageWidth,
    required this.imageHeight,
    this.personId,
    this.userId,
    this.personName,
    this.confidence = 0.0,
    this.excluded = false,
  });

  List<double> get normalizedBbox {
    return [
      (boundingBox.left / imageWidth).clamp(0.0, 1.0),
      (boundingBox.top / imageHeight).clamp(0.0, 1.0),
      (boundingBox.right / imageWidth).clamp(0.0, 1.0),
      (boundingBox.bottom / imageHeight).clamp(0.0, 1.0),
    ];
  }

  bool get isTagged => personId != null;

  ConfidenceTier get tier {
    if (excluded) return ConfidenceTier.unknown;
    if (!isTagged) return ConfidenceTier.unknown;
    if (confidence >= 0.8) return ConfidenceTier.high;
    if (confidence >= 0.5) return ConfidenceTier.medium;
    return ConfidenceTier.low;
  }

  /// Build metadata JSON for this face.
  /// [unknownIndex] is the N in "unknown_N" for untagged faces.
  /// Returns null only if face is excluded.
  Map<String, dynamic>? toMetadataJson({int? unknownIndex}) {
    if (excluded) return null;
    return {
      'user_id': isTagged ? userId : 'unknown_$unknownIndex',
      'bbox': normalizedBbox
          .map((v) => double.parse(v.toStringAsFixed(2)))
          .toList(),
    };
  }
}

enum ConfidenceTier { high, medium, low, unknown }
