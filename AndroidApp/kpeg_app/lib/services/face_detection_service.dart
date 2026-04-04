import 'dart:io';
import 'dart:ui';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../models/detected_face.dart';

class FaceDetectionService {
  final FaceDetector _detector;

  FaceDetectionService()
      : _detector = FaceDetector(
          options: FaceDetectorOptions(
            enableContours: false,
            enableClassification: false,
            enableTracking: false,
            performanceMode: FaceDetectorMode.fast,
          ),
        );

  /// Detecta caras en una imagen. Devuelve lista de DetectedFace con bbox normalizados.
  Future<List<DetectedFace>> detectFaces(
    File imageFile, {
    required int imageWidth,
    required int imageHeight,
  }) async {
    final inputImage = InputImage.fromFilePath(imageFile.path);
    final faces = await _detector.processImage(inputImage);

    return faces.map((face) {
      return DetectedFace(
        boundingBox: Rect.fromLTRB(
          face.boundingBox.left,
          face.boundingBox.top,
          face.boundingBox.right,
          face.boundingBox.bottom,
        ),
        imageWidth: imageWidth,
        imageHeight: imageHeight,
      );
    }).toList();
  }

  void dispose() {
    _detector.close();
  }
}
