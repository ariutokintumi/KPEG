import 'dart:async';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'dart:math';

class SensorService {
  String? _cachedDeviceModel;

  // Streams de sensores
  StreamSubscription? _compassSub;
  StreamSubscription? _accelSub;
  double? _lastCompassHeading;
  double? _lastTilt;

  /// Iniciar escucha de sensores (llamar al entrar en capture screen)
  void startListening() {
    _compassSub = FlutterCompass.events?.listen((event) {
      _lastCompassHeading = event.heading;
    });

    _accelSub = accelerometerEventStream().listen((event) {
      // Calcular tilt desde acelerómetro
      // pitch = atan2(y, sqrt(x^2 + z^2)) * 180 / pi
      // 0 = horizontal, -90 = apuntando abajo, 90 = apuntando arriba
      _lastTilt = atan2(event.y, sqrt(event.x * event.x + event.z * event.z)) *
          (180 / pi);
    });
  }

  /// Parar escucha (llamar al salir de capture screen)
  void stopListening() {
    _compassSub?.cancel();
    _accelSub?.cancel();
    _compassSub = null;
    _accelSub = null;
  }

  /// Snapshot de sensores al momento de captura
  SensorSnapshot captureSnapshot() {
    return SensorSnapshot(
      compassHeading: _lastCompassHeading,
      cameraTilt: _lastTilt,
    );
  }

  /// Obtener GPS (con flow de permisos)
  Future<GpsData?> getLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return null;
    }
    if (permission == LocationPermission.deniedForever) return null;

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      return GpsData(
        lat: position.latitude,
        lng: position.longitude,
        altitude: position.altitude != 0.0 ? position.altitude : null,
      );
    } catch (_) {
      return null;
    }
  }

  /// Modelo del dispositivo (ej: "Pixel 8 Pro")
  Future<String> getDeviceModel() async {
    if (_cachedDeviceModel != null) return _cachedDeviceModel!;
    final info = DeviceInfoPlugin();
    final android = await info.androidInfo;
    _cachedDeviceModel = android.model;
    return _cachedDeviceModel!;
  }

  /// Orientación basada en dimensiones de la imagen
  String getOrientation(int imageWidth, int imageHeight) {
    return imageWidth >= imageHeight ? 'landscape' : 'portrait';
  }

  /// Timestamp Unix (epoch seconds)
  int getTimestamp() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  /// Timezone IANA (ej: "Europe/Madrid")
  Future<String> getTimezone() async {
    return FlutterTimezone.getLocalTimezone();
  }
}

class SensorSnapshot {
  final double? compassHeading;
  final double? cameraTilt;

  SensorSnapshot({this.compassHeading, this.cameraTilt});
}

class GpsData {
  final double lat;
  final double lng;
  final double? altitude;

  GpsData({required this.lat, required this.lng, this.altitude});
}
