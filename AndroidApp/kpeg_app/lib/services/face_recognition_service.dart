import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../models/person.dart';
import 'people_repository.dart';

/// On-device face crop + recognition.
/// Privacy-first: identification happens entirely on the device.
/// Server only receives selfies for reconstruction purposes.
class FaceCropService {
  final PeopleRepository _peopleRepo;

  /// Cached embeddings for fast matching
  List<_EmbeddingRecord> _cache = [];

  FaceCropService(this._peopleRepo);

  /// Load all embeddings into memory (call on app start + after adding people)
  Future<void> loadEmbeddings() async {
    _cache = (await _peopleRepo.getAllEmbeddings())
        .map((r) => _EmbeddingRecord(r.personId, r.personName, r.embedding))
        .toList();
  }

  /// Crop a face from an image → JPEG bytes (for server registration)
  Future<Uint8List> cropFaceJpeg(
    File imageFile, {
    required double left,
    required double top,
    required double right,
    required double bottom,
    required int imageWidth,
    required int imageHeight,
  }) async {
    final image = await _decodeFile(imageFile);
    final cropped = _cropFace(image, left, top, right, bottom, imageWidth, imageHeight);
    return Uint8List.fromList(img.encodeJpg(cropped, quality: 85));
  }

  /// Extract face embedding from an image + bounding box (for matching)
  Future<Uint8List> extractEmbedding(
    File imageFile, {
    required double left,
    required double top,
    required double right,
    required double bottom,
    required int imageWidth,
    required int imageHeight,
  }) async {
    final image = await _decodeFile(imageFile);
    final cropped = _cropFace(image, left, top, right, bottom, imageWidth, imageHeight);
    return _toEmbedding(cropped);
  }

  /// Extract embedding from a selfie (face should be centered)
  Future<Uint8List> extractSelfieEmbedding(File selfieFile) async {
    final image = await _decodeFile(selfieFile);
    // Center crop for selfies
    final size = min(image.width, image.height);
    final x = (image.width - size) ~/ 2;
    final y = (image.height - size) ~/ 2;
    final cropped = img.copyCrop(image, x: x, y: y, width: size, height: size);
    return _toEmbedding(cropped);
  }

  /// Match a face embedding against the local library.
  /// Returns matched Person + confidence, or null.
  ({Person? person, double confidence}) findMatch(Uint8List embedding) {
    if (_cache.isEmpty) return (person: null, confidence: 0.0);

    double bestSim = -1;
    _EmbeddingRecord? bestRecord;

    for (final record in _cache) {
      final sim = _cosineSimilarity(embedding, record.embedding);
      if (sim > bestSim) {
        bestSim = sim;
        bestRecord = record;
      }
    }

    if (bestRecord == null || bestSim < 0.3) {
      return (person: null, confidence: 0.0);
    }

    return (
      person: Person(
        id: bestRecord.personId,
        visibleUserId: Person.generateUserId(bestRecord.personName),
        name: bestRecord.personName,
      ),
      confidence: bestSim.clamp(0.0, 1.0),
    );
  }

  // ── Private helpers ──

  Future<img.Image> _decodeFile(File file) async {
    final bytes = await file.readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) throw Exception('Failed to decode image');
    return image;
  }

  img.Image _cropFace(img.Image image, double left, double top, double right,
      double bottom, int imageWidth, int imageHeight) {
    final padX = (right - left) * 0.1;
    final padY = (bottom - top) * 0.1;
    final x = (left - padX).clamp(0, imageWidth - 1).toInt();
    final y = (top - padY).clamp(0, imageHeight - 1).toInt();
    final w = ((right - left) + padX * 2).toInt().clamp(1, imageWidth - x);
    final h = ((bottom - top) + padY * 2).toInt().clamp(1, imageHeight - y);
    return img.copyCrop(image, x: x, y: y, width: w, height: h);
  }

  /// Convert image to 64x64 grayscale embedding (4096 bytes)
  Uint8List _toEmbedding(img.Image image) {
    final resized = img.copyResize(image, width: 64, height: 64);
    final gray = img.grayscale(resized);
    final embedding = Uint8List(64 * 64);
    for (int py = 0; py < 64; py++) {
      for (int px = 0; px < 64; px++) {
        embedding[py * 64 + px] = gray.getPixel(px, py).r.toInt();
      }
    }
    return embedding;
  }

  double _cosineSimilarity(Uint8List a, Uint8List b) {
    if (a.length != b.length) return 0.0;
    double dot = 0, normA = 0, normB = 0;
    for (int i = 0; i < a.length; i++) {
      final va = a[i].toDouble();
      final vb = b[i].toDouble();
      dot += va * vb;
      normA += va * va;
      normB += vb * vb;
    }
    if (normA == 0 || normB == 0) return 0.0;
    return dot / (sqrt(normA) * sqrt(normB));
  }
}

class _EmbeddingRecord {
  final int personId;
  final String personName;
  final Uint8List embedding;
  _EmbeddingRecord(this.personId, this.personName, this.embedding);
}
