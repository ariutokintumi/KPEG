import 'dart:ui';

class DetectedFace {
  /// Bounding box en coordenadas de píxeles de la imagen
  final Rect boundingBox;

  /// Dimensiones de la imagen original (para normalizar)
  final int imageWidth;
  final int imageHeight;

  /// Persona asignada (null si no se ha taggeado)
  int? personId;
  String? userId;
  String? personName;

  DetectedFace({
    required this.boundingBox,
    required this.imageWidth,
    required this.imageHeight,
    this.personId,
    this.userId,
    this.personName,
  });

  /// Bbox normalizado 0.0-1.0 [left, top, right, bottom]
  List<double> get normalizedBbox {
    return [
      (boundingBox.left / imageWidth).clamp(0.0, 1.0),
      (boundingBox.top / imageHeight).clamp(0.0, 1.0),
      (boundingBox.right / imageWidth).clamp(0.0, 1.0),
      (boundingBox.bottom / imageHeight).clamp(0.0, 1.0),
    ];
  }

  bool get isTagged => personId != null;

  /// Para el metadata JSON
  Map<String, dynamic>? toMetadataJson() {
    if (!isTagged) return null;
    return {
      'user_id': userId,
      'bbox': normalizedBbox.map((v) => double.parse(v.toStringAsFixed(2))).toList(),
    };
  }
}
