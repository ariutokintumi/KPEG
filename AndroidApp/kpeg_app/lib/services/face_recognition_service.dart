import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../models/person.dart';
import 'people_repository.dart';

/// On-device face recognition using simple pixel-based embeddings.
/// Privacy-first: no biometric data ever leaves the device.
class FaceRecognitionService {
  final PeopleRepository _peopleRepo;

  /// Cached embeddings for fast matching
  List<({int personId, String personName, Uint8List embedding})> _cachedEmbeddings = [];

  FaceRecognitionService(this._peopleRepo);

  /// Load all embeddings into memory for fast matching
  Future<void> loadEmbeddings() async {
    _cachedEmbeddings = await _peopleRepo.getAllEmbeddings();
  }

  /// Extract a face embedding from an image file + bounding box.
  /// Crops the face, resizes to 64x64 grayscale, returns flat pixel array.
  Future<Uint8List> extractEmbedding(
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

    // Pixel coordinates with padding (10% extra around face)
    final padX = (right - left) * 0.1;
    final padY = (bottom - top) * 0.1;
    final x = (left - padX).clamp(0, imageWidth - 1).toInt();
    final y = (top - padY).clamp(0, imageHeight - 1).toInt();
    final w = ((right - left) + padX * 2).toInt().clamp(1, imageWidth - x);
    final h = ((bottom - top) + padY * 2).toInt().clamp(1, imageHeight - y);

    // Crop face region
    final cropped = img.copyCrop(image, x: x, y: y, width: w, height: h);

    // Resize to 64x64
    final resized = img.copyResize(cropped, width: 64, height: 64);

    // Convert to grayscale and flatten to byte array
    final grayscale = img.grayscale(resized);
    final embedding = Uint8List(64 * 64);
    for (int py = 0; py < 64; py++) {
      for (int px = 0; px < 64; px++) {
        final pixel = grayscale.getPixel(px, py);
        embedding[py * 64 + px] = pixel.r.toInt();
      }
    }

    return embedding;
  }

  /// Extract embedding from a selfie file (assumes single face, centered)
  Future<Uint8List> extractSelfieEmbedding(File selfieFile) async {
    final bytes = await selfieFile.readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) throw Exception('Failed to decode image');

    // For selfies, use center crop (face should be centered)
    final size = min(image.width, image.height);
    final x = (image.width - size) ~/ 2;
    final y = (image.height - size) ~/ 2;

    final cropped = img.copyCrop(image, x: x, y: y, width: size, height: size);
    final resized = img.copyResize(cropped, width: 64, height: 64);
    final grayscale = img.grayscale(resized);

    final embedding = Uint8List(64 * 64);
    for (int py = 0; py < 64; py++) {
      for (int px = 0; px < 64; px++) {
        final pixel = grayscale.getPixel(px, py);
        embedding[py * 64 + px] = pixel.r.toInt();
      }
    }

    return embedding;
  }

  /// Find best matching person for a face embedding.
  /// Returns (Person, confidence) or (null, 0.0) if no match.
  ({Person? person, double confidence}) findMatch(Uint8List faceEmbedding) {
    if (_cachedEmbeddings.isEmpty) return (person: null, confidence: 0.0);

    double bestSimilarity = -1;
    int? bestPersonId;
    String? bestPersonName;

    for (final record in _cachedEmbeddings) {
      final similarity = _cosineSimilarity(faceEmbedding, record.embedding);
      if (similarity > bestSimilarity) {
        bestSimilarity = similarity;
        bestPersonId = record.personId;
        bestPersonName = record.personName;
      }
    }

    if (bestPersonId == null || bestSimilarity < 0.3) {
      return (person: null, confidence: 0.0);
    }

    return (
      person: Person(id: bestPersonId, name: bestPersonName!),
      confidence: bestSimilarity.clamp(0.0, 1.0),
    );
  }

  /// Cosine similarity between two byte arrays (treated as vectors)
  double _cosineSimilarity(Uint8List a, Uint8List b) {
    if (a.length != b.length) return 0.0;

    double dotProduct = 0;
    double normA = 0;
    double normB = 0;

    for (int i = 0; i < a.length; i++) {
      final va = a[i].toDouble();
      final vb = b[i].toDouble();
      dotProduct += va * vb;
      normA += va * va;
      normB += vb * vb;
    }

    if (normA == 0 || normB == 0) return 0.0;
    return dotProduct / (sqrt(normA) * sqrt(normB));
  }
}
