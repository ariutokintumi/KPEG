import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  // Mock mode OFF — using real API
  static const bool useMock = false;

  // IP por defecto del servidor
  static const String defaultServerIp = '10.105.176.246';
  static const int serverPort = 8000;

  // IP configurable en runtime
  static String _serverIp = defaultServerIp;

  static String get serverIp => _serverIp;
  static String get apiBaseUrl => 'http://$_serverIp:$serverPort';

  // Cargar IP guardada (llamar al inicio de la app)
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _serverIp = prefs.getString('server_ip') ?? defaultServerIp;
  }

  // Guardar nueva IP
  static Future<void> setServerIp(String ip) async {
    _serverIp = ip;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_ip', ip);
  }

  // Capture settings
  static const int imageQuality = 85;
  static const int maxImageWidth = 1920;

  // Local storage subdirectories
  static const String kpegStorageDir = 'kpeg_files';
  static const String peoplePhotosDir = 'people_photos';
}
