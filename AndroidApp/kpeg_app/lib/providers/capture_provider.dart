import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../config/app_config.dart';
import '../models/capture_metadata.dart';
import '../models/detected_face.dart';
import '../models/kpeg_file.dart';
import '../services/api_service.dart';
import '../services/face_detection_service.dart';
import '../services/face_recognition_service.dart';
import '../services/kpeg_repository.dart';
import '../services/people_repository.dart';
import '../services/sensor_service.dart';

enum CaptureState { idle, captured, detecting, encoding, success, error }

class CaptureProvider extends ChangeNotifier {
  final ApiService _api;
  final KpegRepository _kpegRepo;
  final SensorService _sensors;
  final FaceDetectionService _faceDetection;
  final FaceCropService _faceCrop;
  final PeopleRepository _peopleRepo;

  CaptureProvider({
    required ApiService api,
    required KpegRepository kpegRepo,
    required SensorService sensors,
    required FaceDetectionService faceDetection,
    required FaceCropService faceCrop,
    required PeopleRepository peopleRepo,
  })  : _api = api,
        _kpegRepo = kpegRepo,
        _sensors = sensors,
        _faceDetection = faceDetection,
        _faceCrop = faceCrop,
        _peopleRepo = peopleRepo;

  CaptureState state = CaptureState.idle;
  File? photo;
  int? photoWidth;
  int? photoHeight;
  List<DetectedFace> detectedFaces = [];
  bool isOutdoor = false; // Default indoor for hackathon
  String sceneHint = '';
  String tagsText = '';
  String indoorDescription = '';
  String? selectedPlaceId;
  String? errorMessage;
  KpegFile? lastSavedFile;
  SensorSnapshot? _sensorSnapshot;
  GpsData? _gpsData;

  // Session management
  String? _sessionId;
  DateTime? _lastPhotoTime;

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

    // Detect faces with ML Kit
    try {
      detectedFaces = await _faceDetection.detectFaces(
        photo!,
        imageWidth: photoWidth!,
        imageHeight: photoHeight!,
      );

      // Auto-identify each face via server API
      final allPeople = await _peopleRepo.getAll();
      for (final face in detectedFaces) {
        try {
          // Crop face and send to server for identification
          final cropBytes = await _faceCrop.cropFaceJpeg(
            photo!,
            left: face.boundingBox.left,
            top: face.boundingBox.top,
            right: face.boundingBox.right,
            bottom: face.boundingBox.bottom,
            imageWidth: photoWidth!,
            imageHeight: photoHeight!,
          );

          final result = await _api.identifyFace(cropBytes);
          if (result.userId != null && result.confidence > 0.3) {
            // Find the person in our local cache
            final matched = allPeople
                .where((p) => p.visibleUserId == result.userId)
                .toList();
            if (matched.isNotEmpty) {
              face.personId = matched.first.id;
              face.userId = matched.first.visibleUserId;
              face.personName = matched.first.name;
              face.confidence = result.confidence;
            }
          }
        } catch (_) {
          // Identification failed — leave as untagged
        }
      }
    } catch (_) {
      // Face detection failed — continue without faces
    }

    state = CaptureState.captured;
    notifyListeners();
  }

  void setOutdoor(bool value) {
    isOutdoor = value;
    notifyListeners();
  }

  /// Asignar una persona a una cara detectada
  /// Assign a person to a detected face (manual = confidence 1.0)
  void assignPersonToFace(int faceIndex, int personId, String userId, String personName) {
    if (faceIndex < detectedFaces.length) {
      detectedFaces[faceIndex].personId = personId;
      detectedFaces[faceIndex].confidence = 1.0; // Manual assignment = full confidence
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

  void setIndoorDescription(String desc) {
    indoorDescription = desc;
  }

  void setSelectedPlaceId(String? placeId) {
    selectedPlaceId = placeId;
    notifyListeners();
  }

  /// Generate or reuse session ID (30-min windows)
  String _getSessionId() {
    final now = DateTime.now();
    if (_sessionId != null &&
        _lastPhotoTime != null &&
        now.difference(_lastPhotoTime!).inMinutes < 30) {
      return _sessionId!;
    }
    // New session
    _sessionId = 'sess_'
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}'
        '_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    return _sessionId!;
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

      _lastPhotoTime = DateTime.now();
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
    indoorDescription = '';
    selectedPlaceId = null;
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
      compassHeading: _sensorSnapshot?.compassHeading,
      cameraTilt: _sensorSnapshot?.cameraTilt,
      people: detectedFaces,
      sceneHint: sceneHint.isNotEmpty ? sceneHint : null,
      tags: _parsedTags,
      indoorPlaceId: selectedPlaceId,
      indoorDescription: indoorDescription.isNotEmpty ? indoorDescription : null,
      sessionId: _getSessionId(),
    );
  }
}
