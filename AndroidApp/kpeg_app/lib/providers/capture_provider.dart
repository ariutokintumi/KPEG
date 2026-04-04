import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../config/app_config.dart';
import '../models/capture_metadata.dart';
import '../models/detected_face.dart';
import '../models/kpeg_file.dart';
import '../services/api_service.dart';
import '../services/face_detection_service.dart';
import '../services/kpeg_repository.dart';
import '../services/sensor_service.dart';

enum CaptureState { idle, captured, detecting, encoding, success, error }

class CaptureProvider extends ChangeNotifier {
  final ApiService _api;
  final KpegRepository _kpegRepo;
  final SensorService _sensors;
  final FaceDetectionService _faceDetection;

  CaptureProvider({
    required ApiService api,
    required KpegRepository kpegRepo,
    required SensorService sensors,
    required FaceDetectionService faceDetection,
  })  : _api = api,
        _kpegRepo = kpegRepo,
        _sensors = sensors,
        _faceDetection = faceDetection;

  CaptureState state = CaptureState.idle;
  File? photo;
  int? photoWidth;
  int? photoHeight;
  List<DetectedFace> detectedFaces = [];
  bool isOutdoor = true;
  String sceneHint = '';
  String tagsText = '';
  String? errorMessage;
  KpegFile? lastSavedFile;
  SensorSnapshot? _sensorSnapshot;
  GpsData? _gpsData;

  /// Iniciar sensores (llamar al inicio)
  void startSensors() => _sensors.startListening();

  /// Parar sensores (llamar al dispose)
  void stopSensors() => _sensors.stopListening();

  /// Abrir cámara y capturar foto
  Future<void> capturePhoto() async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: AppConfig.imageQuality,
      maxWidth: AppConfig.maxImageWidth.toDouble(),
    );
    if (xfile == null) return;

    // Capturar snapshot de sensores AL MOMENTO de la foto
    _sensorSnapshot = _sensors.captureSnapshot();

    photo = File(xfile.path);

    // Obtener dimensiones de la imagen
    final decodedImage = await decodeImageFromList(await photo!.readAsBytes());
    photoWidth = decodedImage.width;
    photoHeight = decodedImage.height;

    state = CaptureState.detecting;
    errorMessage = null;
    lastSavedFile = null;
    detectedFaces = [];
    notifyListeners();

    // Detectar caras automáticamente
    try {
      detectedFaces = await _faceDetection.detectFaces(
        photo!,
        imageWidth: photoWidth!,
        imageHeight: photoHeight!,
      );
    } catch (_) {
      // Si falla la detección, seguimos sin caras — no es crítico
    }

    state = CaptureState.captured;
    notifyListeners();
  }

  void setOutdoor(bool value) {
    isOutdoor = value;
    notifyListeners();
  }

  /// Asignar una persona a una cara detectada
  void assignPersonToFace(int faceIndex, int personId, String userId, String personName) {
    if (faceIndex < detectedFaces.length) {
      detectedFaces[faceIndex].personId = personId;
      detectedFaces[faceIndex].userId = userId;
      detectedFaces[faceIndex].personName = personName;
      notifyListeners();
    }
  }

  /// Quitar asignación de persona
  void unassignFace(int faceIndex) {
    if (faceIndex < detectedFaces.length) {
      detectedFaces[faceIndex].personId = null;
      detectedFaces[faceIndex].userId = null;
      detectedFaces[faceIndex].personName = null;
      notifyListeners();
    }
  }

  void setSceneHint(String hint) {
    sceneHint = hint;
  }

  void setTagsText(String text) {
    tagsText = text;
  }

  List<String> get _parsedTags {
    if (tagsText.isEmpty) return [];
    return tagsText.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
  }

  /// Codificar foto y guardar .kpeg
  Future<void> encodeAndSave() async {
    if (photo == null) return;

    state = CaptureState.encoding;
    errorMessage = null;
    notifyListeners();

    try {
      // Obtener GPS (async, no bloquea si tarda o se deniega)
      _gpsData = await _sensors.getLocation();

      final metadata = await _buildMetadata();
      final kpegBytes = await _api.encode(photo!, metadata);

      lastSavedFile = await _kpegRepo.save(
        kpegBytes,
        sceneHint: sceneHint.isNotEmpty ? sceneHint : null,
        originalPhotoPath: photo!.path,
      );

      state = CaptureState.success;
      notifyListeners();
    } catch (e) {
      state = CaptureState.error;
      errorMessage = e.toString();
      notifyListeners();
    }
  }

  /// Reset para nueva captura
  void reset() {
    state = CaptureState.idle;
    photo = null;
    photoWidth = null;
    photoHeight = null;
    detectedFaces = [];
    sceneHint = '';
    tagsText = '';
    errorMessage = null;
    lastSavedFile = null;
    _sensorSnapshot = null;
    _gpsData = null;
    notifyListeners();
  }

  Future<CaptureMetadata> _buildMetadata() async {
    final orientation = _sensors.getOrientation(photoWidth ?? 1, photoHeight ?? 1);
    final deviceModel = await _sensors.getDeviceModel();
    final timezone = await _sensors.getTimezone();

    return CaptureMetadata(
      orientation: orientation,
      timestamp: _sensors.getTimestamp(),
      timezone: timezone,
      deviceModel: deviceModel,
      isOutdoor: isOutdoor,
      lat: _gpsData?.lat,
      lng: _gpsData?.lng,
      altitude: _gpsData?.altitude,
      compassHeading: _sensorSnapshot?.compassHeading,
      cameraTilt: _sensorSnapshot?.cameraTilt,
      people: detectedFaces,
      sceneHint: sceneHint.isNotEmpty ? sceneHint : null,
      tags: _parsedTags,
    );
  }
}
