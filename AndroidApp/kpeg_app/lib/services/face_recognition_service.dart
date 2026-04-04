import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Helper to crop faces from images for sending to the server's identify endpoint.
class FaceCropService {
  /// Crop a face from an image and return JPEG bytes for the identify API.
  Future<Uint8List> cropFaceJpeg(
    File imageFile, {
    required double left,
    required double top,
    required double right,
    required double bottom,
    required int imageWidth,
    required int imageHeight,
  }) async {
    final bytes = await imageFile.readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) throw Exception('Failed to decode image');

    // Pixel coordinates with 10% padding around face
    final padX = (right - left) * 0.1;
    final padY = (bottom - top) * 0.1;
    final x = (left - padX).clamp(0, imageWidth - 1).toInt();
    final y = (top - padY).clamp(0, imageHeight - 1).toInt();
    final w = ((right - left) + padX * 2).toInt().clamp(1, imageWidth - x);
    final h = ((bottom - top) + padY * 2).toInt().clamp(1, imageHeight - y);

    final cropped = img.copyCrop(image, x: x, y: y, width: w, height: h);
    return Uint8List.fromList(img.encodeJpg(cropped, quality: 85));
  }
}
