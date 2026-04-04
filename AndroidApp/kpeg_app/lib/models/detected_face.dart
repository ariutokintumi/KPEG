import 'dart:typed_data';
import 'dart:ui';

class DetectedFace {
  /// Bounding box in image pixel coordinates
  final Rect boundingBox;

  /// Original image dimensions (for normalization)
  final int imageWidth;
  final int imageHeight;

  /// Assigned person (null if not tagged)
  int? personId;
  String? userId;
  String? personName;

  /// Match confidence from face recognition (0.0-1.0)
  double confidence;

  /// Face embedding extracted from the crop
  Uint8List? embedding;

  DetectedFace({
    required this.boundingBox,
    required this.imageWidth,
    required this.imageHeight,
    this.personId,
    this.userId,
    this.personName,
    this.confidence = 0.0,
    this.embedding,
  });

  /// Normalized bbox 0.0-1.0 [left, top, right, bottom]
  List<double> get normalizedBbox {
    return [
      (boundingBox.left / imageWidth).clamp(0.0, 1.0),
      (boundingBox.top / imageHeight).clamp(0.0, 1.0),
      (boundingBox.right / imageWidth).clamp(0.0, 1.0),
      (boundingBox.bottom / imageHeight).clamp(0.0, 1.0),
    ];
  }

  bool get isTagged => personId != null;

  /// Confidence tier for UI color-coding
  ConfidenceTier get tier {
    if (!isTagged) return ConfidenceTier.unknown;
    if (confidence >= 0.8) return ConfidenceTier.high;
    if (confidence >= 0.5) return ConfidenceTier.medium;
    return ConfidenceTier.low;
  }

  /// For metadata JSON
  Map<String, dynamic>? toMetadataJson() {
    if (!isTagged) return null;
    return {
      'user_id': userId,
      'bbox': normalizedBbox.map((v) => double.parse(v.toStringAsFixed(2))).toList(),
    };
  }
}

enum ConfidenceTier { high, medium, low, unknown }
