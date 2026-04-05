import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/capture_metadata.dart';

/// Resultado de la operación de encode
class EncodeResult {
  final Uint8List kpegBytes;
  final String imageId;
  final HederaInfo? hederaInfo;

  EncodeResult({
    required this.kpegBytes,
    required this.imageId,
    this.hederaInfo,
  });
}

/// Info de Hedera asociada a una imagen
class HederaInfo {
  final String? fileId;
  final String? topicId;
  final String? topicTxId;
  final String? nftTokenId;
  final String? nftSerial;
  final String? network;

  HederaInfo({
    this.fileId,
    this.topicId,
    this.topicTxId,
    this.nftTokenId,
    this.nftSerial,
    this.network,
  });
}

class ApiService {
  final String baseUrl;
  final bool useMock;

  ApiService({
    this.baseUrl = AppConfig.apiBaseUrl,
    this.useMock = AppConfig.useMock,
  });

  // ══════════════════════════════════════
  // CORE PIPELINE
  // ══════════════════════════════════════

  /// Resultado de encode: bytes .kpeg + info Hedera
  Future<EncodeResult> encode(File imageFile, CaptureMetadata metadata) async {
    if (useMock) {
      final bytes = await _mockEncode(metadata);
      return EncodeResult(kpegBytes: bytes, imageId: 'mock_${DateTime.now().millisecondsSinceEpoch}');
    }

    final uri = Uri.parse('$baseUrl/encode');
    final request = http.MultipartRequest('POST', uri);
    request.files.add(await http.MultipartFile.fromPath('image', imageFile.path));
    request.fields['metadata'] = jsonEncode(metadata.toJson());

    final response = await request.send().timeout(
      const Duration(seconds: 120),
      onTimeout: () => throw Exception('Timeout encoding image'),
    );

    final body = await response.stream.bytesToString();
    if (response.statusCode != 200) {
      final error = jsonDecode(body);
      throw Exception(error['error'] ?? 'Unknown error (${response.statusCode})');
    }

    final json = jsonDecode(body);
    final kpegBytes = base64Decode(json['kpeg_base64'] as String);
    final imageId = json['image_id'] as String?;
    final hederaJson = json['hedera'] as Map<String, dynamic>?;

    HederaInfo? hederaInfo;
    if (hederaJson != null) {
      hederaInfo = HederaInfo(
        fileId: hederaJson['file_id'] as String?,
        topicId: hederaJson['topic_id'] as String?,
        topicTxId: hederaJson['topic_tx_id'] as String?,
        nftTokenId: hederaJson['nft_token_id'] as String?,
        nftSerial: hederaJson['nft_serial'] as String?,
        network: hederaJson['network'] as String?,
      );
    }

    return EncodeResult(
      kpegBytes: kpegBytes,
      imageId: imageId ?? '',
      hederaInfo: hederaInfo,
    );
  }

  Future<Uint8List> decode(Uint8List kpegBytes, {String quality = 'balanced'}) async {
    if (useMock) return _mockDecode();

    final uri = Uri.parse('$baseUrl/decode');
    final request = http.MultipartRequest('POST', uri);
    request.files.add(
      http.MultipartFile.fromBytes('kpeg_file', kpegBytes, filename: 'file.kpeg'),
    );
    request.fields['quality'] = quality;

    final response = await request.send().timeout(
      const Duration(seconds: 120),
      onTimeout: () => throw Exception('Decode timeout (AI may take 15s+)'),
    );

    if (response.statusCode == 200) return response.stream.toBytes();
    final body = await response.stream.bytesToString();
    throw Exception('Decode error: $body');
  }

  Future<bool> healthCheck() async {
    if (useMock) return true;
    try {
      final response = await http.get(Uri.parse('$baseUrl/health')).timeout(
        const Duration(seconds: 5),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ══════════════════════════════════════
  // PEOPLE LIBRARY
  // ══════════════════════════════════════

  /// POST /library/people — register person with selfies
  /// POST /library/people — register with selfies + timestamps
  Future<Map<String, dynamic>> registerPerson({
    required String userId,
    required String name,
    required List<File> selfies,
    List<int>? selfieTimestamps,
  }) async {
    if (useMock) {
      await Future.delayed(const Duration(seconds: 1));
      return {'user_id': userId, 'status': 'registered'};
    }

    final uri = Uri.parse('$baseUrl/library/people');
    final request = http.MultipartRequest('POST', uri);
    request.fields['user_id'] = userId;
    request.fields['name'] = name;

    // Selfie timestamps as JSON array
    final timestamps = selfieTimestamps ??
        List.generate(selfies.length,
            (_) => DateTime.now().millisecondsSinceEpoch ~/ 1000);
    request.fields['selfie_timestamps'] = jsonEncode(timestamps);

    for (final selfie in selfies) {
      request.files.add(await http.MultipartFile.fromPath('selfies', selfie.path));
    }

    final response = await request.send().timeout(const Duration(seconds: 30));
    final body = await response.stream.bytesToString();

    if (response.statusCode == 200) return jsonDecode(body);
    throw Exception('Failed to register person: $body');
  }

  /// GET /library/people — list all registered people
  Future<List<Map<String, dynamic>>> listPeople() async {
    if (useMock) {
      return []; // Mock: empty list, people added via registerPerson
    }

    final response = await http.get(Uri.parse('$baseUrl/library/people')).timeout(
      const Duration(seconds: 10),
    );

    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(response.body));
    }
    throw Exception('Failed to list people: ${response.body}');
  }

  /// DELETE /library/people/{user_id}
  Future<void> deletePerson(String userId) async {
    if (useMock) {
      await Future.delayed(const Duration(milliseconds: 500));
      return;
    }

    final response = await http.delete(
      Uri.parse('$baseUrl/library/people/$userId'),
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('Failed to delete person: ${response.body}');
    }
  }

  /// POST /library/people/identify — send face crop, get match
  Future<({String? userId, double confidence})> identifyFace(Uint8List faceCropJpeg) async {
    if (useMock) {
      await Future.delayed(const Duration(milliseconds: 300));
      return (userId: null, confidence: 0.0); // Mock: no match
    }

    final uri = Uri.parse('$baseUrl/library/people/identify');
    final request = http.MultipartRequest('POST', uri);
    request.files.add(
      http.MultipartFile.fromBytes('face_crop', faceCropJpeg, filename: 'face.jpg'),
    );

    final response = await request.send().timeout(const Duration(seconds: 10));
    final body = await response.stream.bytesToString();

    if (response.statusCode == 200) {
      final json = jsonDecode(body);
      return (
        userId: json['user_id'] as String?,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      );
    }
    return (userId: null, confidence: 0.0);
  }

  // ══════════════════════════════════════
  // PLACES LIBRARY
  // ══════════════════════════════════════

  /// POST /library/places — register with photos + per-photo metadata
  Future<Map<String, dynamic>> registerPlace({
    required String placeId,
    required String name,
    required List<File> photos,
    List<Map<String, dynamic>>? photosMetadata,
  }) async {
    if (useMock) {
      await Future.delayed(const Duration(seconds: 1));
      return {'place_id': placeId, 'status': 'registered'};
    }

    final uri = Uri.parse('$baseUrl/library/places');
    final request = http.MultipartRequest('POST', uri);
    request.fields['place_id'] = placeId;
    request.fields['name'] = name;

    // Per-photo metadata (coordinates, angle, timestamp)
    if (photosMetadata != null) {
      request.fields['photos_metadata'] = jsonEncode(photosMetadata);
    }

    for (final photo in photos) {
      request.files.add(await http.MultipartFile.fromPath('photos', photo.path));
    }

    final response = await request.send().timeout(const Duration(seconds: 30));
    final body = await response.stream.bytesToString();
    if (response.statusCode == 200) return jsonDecode(body);
    throw Exception('Failed to register place: $body');
  }

  Future<List<Map<String, dynamic>>> listPlaces() async {
    if (useMock) return [];

    final response = await http.get(Uri.parse('$baseUrl/library/places')).timeout(
      const Duration(seconds: 10),
    );
    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(response.body));
    }
    throw Exception('Failed to list places: ${response.body}');
  }

  Future<void> deletePlace(String placeId) async {
    if (useMock) return;
    await http.delete(Uri.parse('$baseUrl/library/places/$placeId')).timeout(
      const Duration(seconds: 10),
    );
  }

  // ══════════════════════════════════════
  // OBJECTS LIBRARY
  // ══════════════════════════════════════

  Future<Map<String, dynamic>> registerObject({
    required String objectId,
    required String name,
    required String category,
    required List<File> photos,
  }) async {
    if (useMock) {
      await Future.delayed(const Duration(seconds: 1));
      return {'object_id': objectId, 'status': 'registered'};
    }

    final uri = Uri.parse('$baseUrl/library/objects');
    final request = http.MultipartRequest('POST', uri);
    request.fields['object_id'] = objectId;
    request.fields['name'] = name;
    request.fields['category'] = category;
    for (final photo in photos) {
      request.files.add(await http.MultipartFile.fromPath('photos', photo.path));
    }

    final response = await request.send().timeout(const Duration(seconds: 30));
    final body = await response.stream.bytesToString();
    if (response.statusCode == 200) return jsonDecode(body);
    throw Exception('Failed to register object: $body');
  }

  Future<List<Map<String, dynamic>>> listObjects() async {
    if (useMock) return [];

    final response = await http.get(Uri.parse('$baseUrl/library/objects')).timeout(
      const Duration(seconds: 10),
    );
    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(response.body));
    }
    throw Exception('Failed to list objects: ${response.body}');
  }

  Future<void> deleteObject(String objectId) async {
    if (useMock) return;
    await http.delete(Uri.parse('$baseUrl/library/objects/$objectId')).timeout(
      const Duration(seconds: 10),
    );
  }

  // ══════════════════════════════════════
  // HEDERA
  // ══════════════════════════════════════

  /// POST /hedera/setup — inicializar topic HCS + colección NFT
  Future<Map<String, dynamic>> hederaSetup() async {
    if (useMock) return {'status': 'mock'};
    final response = await http.post(Uri.parse('$baseUrl/hedera/setup')).timeout(
      const Duration(seconds: 30),
    );
    return jsonDecode(response.body);
  }

  /// GET /hedera/status
  Future<Map<String, dynamic>> hederaStatus() async {
    if (useMock) return {'available': false};
    final response = await http.get(Uri.parse('$baseUrl/hedera/status')).timeout(
      const Duration(seconds: 10),
    );
    return jsonDecode(response.body);
  }

  // ══════════════════════════════════════
  // PHOTO MANAGEMENT (view + add more)
  // ══════════════════════════════════════

  // --- People selfies ---

  /// GET /library/people/{user_id}/selfies → {"count": N}
  Future<int> getPersonSelfieCount(String userId) async {
    if (useMock) return 0;
    final response = await http.get(Uri.parse('$baseUrl/library/people/$userId/selfies')).timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) return (jsonDecode(response.body)['selfie_count'] as int?) ?? 0;
    return 0;
  }

  /// URL for GET /library/people/{user_id}/selfie/{idx} → JPEG image
  String personSelfieUrl(String userId, int index) => '$baseUrl/library/people/$userId/selfie/$index';

  /// POST /library/people/{user_id}/selfies — add more selfies
  Future<void> addPersonSelfies(String userId, List<File> selfies) async {
    if (useMock) return;
    final uri = Uri.parse('$baseUrl/library/people/$userId/selfies');
    final request = http.MultipartRequest('POST', uri);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    request.fields['selfie_timestamps'] = jsonEncode(List.generate(selfies.length, (i) => now + i));
    for (final selfie in selfies) {
      request.files.add(await http.MultipartFile.fromPath('selfies', selfie.path));
    }
    await request.send().timeout(const Duration(seconds: 30));
  }

  // --- Places photos ---

  /// GET /library/places/{place_id}/photos → {"count": N}
  Future<int> getPlacePhotoCount(String placeId) async {
    if (useMock) return 0;
    final response = await http.get(Uri.parse('$baseUrl/library/places/$placeId/photos')).timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) return (jsonDecode(response.body)['photo_count'] as int?) ?? 0;
    return 0;
  }

  /// URL for GET /library/places/{place_id}/photo/{idx} → JPEG image
  String placePhotoUrl(String placeId, int index) => '$baseUrl/library/places/$placeId/photo/$index';

  /// POST /library/places/{place_id}/photos — add more photos
  Future<void> addPlacePhotos(String placeId, List<File> photos) async {
    if (useMock) return;
    final uri = Uri.parse('$baseUrl/library/places/$placeId/photos');
    final request = http.MultipartRequest('POST', uri);
    for (final photo in photos) {
      request.files.add(await http.MultipartFile.fromPath('photos', photo.path));
    }
    await request.send().timeout(const Duration(seconds: 30));
  }

  // --- Objects photos ---

  /// GET /library/objects/{object_id}/photos → {"count": N}
  Future<int> getObjectPhotoCount(String objectId) async {
    if (useMock) return 0;
    final response = await http.get(Uri.parse('$baseUrl/library/objects/$objectId/photos')).timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) return (jsonDecode(response.body)['photo_count'] as int?) ?? 0;
    return 0;
  }

  /// URL for GET /library/objects/{object_id}/photo/{idx} → JPEG image
  String objectPhotoUrl(String objectId, int index) => '$baseUrl/library/objects/$objectId/photo/$index';

  /// POST /library/objects/{object_id}/photos — add more photos
  Future<void> addObjectPhotos(String objectId, List<File> photos) async {
    if (useMock) return;
    final uri = Uri.parse('$baseUrl/library/objects/$objectId/photos');
    final request = http.MultipartRequest('POST', uri);
    for (final photo in photos) {
      request.files.add(await http.MultipartFile.fromPath('photos', photo.path));
    }
    await request.send().timeout(const Duration(seconds: 30));
  }

  // ══════════════════════════════════════
  // MOCK IMPLEMENTATIONS
  // ══════════════════════════════════════

  Future<Uint8List> _mockEncode(CaptureMetadata metadata) async {
    await Future.delayed(const Duration(seconds: 2));
    final mockJson = jsonEncode(metadata.toJson());
    const header = 'KPEG\x01\x00';
    return Uint8List.fromList(utf8.encode(header + mockJson));
  }

  Future<Uint8List> _mockDecode() async {
    await Future.delayed(const Duration(seconds: 3));
    return _minimalJpeg();
  }

  Uint8List _minimalJpeg() {
    return Uint8List.fromList([
      0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
      0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
      0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08, 0x07, 0x07, 0x07, 0x09,
      0x09, 0x08, 0x0A, 0x0C, 0x14, 0x0D, 0x0C, 0x0B, 0x0B, 0x0C, 0x19, 0x12,
      0x13, 0x0F, 0x14, 0x1D, 0x1A, 0x1F, 0x1E, 0x1D, 0x1A, 0x1C, 0x1C, 0x20,
      0x24, 0x2E, 0x27, 0x20, 0x22, 0x2C, 0x23, 0x1C, 0x1C, 0x28, 0x37, 0x29,
      0x2C, 0x30, 0x31, 0x34, 0x34, 0x34, 0x1F, 0x27, 0x39, 0x3D, 0x38, 0x32,
      0x3C, 0x2E, 0x33, 0x34, 0x32, 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01,
      0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0xFF, 0xC4, 0x00, 0x1F, 0x00, 0x00,
      0x01, 0x05, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
      0x09, 0x0A, 0x0B, 0xFF, 0xC4, 0x00, 0xB5, 0x10, 0x00, 0x02, 0x01, 0x03,
      0x03, 0x02, 0x04, 0x03, 0x05, 0x05, 0x04, 0x04, 0x00, 0x00, 0x01, 0x7D,
      0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12, 0x21, 0x31, 0x41, 0x06,
      0x13, 0x51, 0x61, 0x07, 0x22, 0x71, 0x14, 0x32, 0x81, 0x91, 0xA1, 0x08,
      0x23, 0x42, 0xB1, 0xC1, 0x15, 0x52, 0xD1, 0xF0, 0x24, 0x33, 0x62, 0x72,
      0x82, 0x09, 0x0A, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x25, 0x26, 0x27, 0x28,
      0x29, 0x2A, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3A, 0x43, 0x44, 0x45,
      0x46, 0x47, 0x48, 0x49, 0x4A, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59,
      0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A, 0x73, 0x74, 0x75,
      0x76, 0x77, 0x78, 0x79, 0x7A, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89,
      0x8A, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9A, 0xA2, 0xA3,
      0xA4, 0xA5, 0xA6, 0xA7, 0xA8, 0xA9, 0xAA, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6,
      0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC7, 0xC8, 0xC9,
      0xCA, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA, 0xE1, 0xE2,
      0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA, 0xF1, 0xF2, 0xF3, 0xF4,
      0xF5, 0xF6, 0xF7, 0xF8, 0xF9, 0xFA, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01,
      0x00, 0x00, 0x3F, 0x00, 0x7B, 0x94, 0x11, 0x00, 0x00, 0x00, 0x00, 0x00,
      0xFF, 0xD9,
    ]);
  }
}
