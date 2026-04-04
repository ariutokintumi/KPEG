import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/kpeg_file.dart';
import '../services/api_service.dart';
import '../services/kpeg_repository.dart';

enum DecodeState { idle, decoding, success, error }

class GalleryProvider extends ChangeNotifier {
  final KpegRepository _kpegRepo;
  final ApiService _api;

  GalleryProvider({
    required KpegRepository kpegRepo,
    required ApiService api,
  })  : _kpegRepo = kpegRepo,
        _api = api;

  List<KpegFile> files = [];
  DecodeState decodeState = DecodeState.idle;
  Uint8List? decodedImageBytes;
  String selectedQuality = 'balanced';
  String? errorMessage;

  Future<void> loadFiles() async {
    files = await _kpegRepo.getAll();
    notifyListeners();
  }

  void setQuality(String quality) {
    selectedQuality = quality;
    notifyListeners();
  }

  Future<void> decodeFile(KpegFile file) async {
    decodeState = DecodeState.decoding;
    decodedImageBytes = null;
    errorMessage = null;
    notifyListeners();

    try {
      final kpegBytes = await _kpegRepo.readBytes(file);
      decodedImageBytes = await _api.decode(kpegBytes, quality: selectedQuality);
      decodeState = DecodeState.success;
    } catch (e) {
      decodeState = DecodeState.error;
      errorMessage = e.toString();
    }
    notifyListeners();
  }

  Future<void> deleteFile(KpegFile file) async {
    await _kpegRepo.delete(file.id!);
    await loadFiles();
  }

  void resetDecode() {
    decodeState = DecodeState.idle;
    decodedImageBytes = null;
    errorMessage = null;
    notifyListeners();
  }
}
