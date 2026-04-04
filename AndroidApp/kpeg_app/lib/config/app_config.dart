class AppConfig {
  // Toggle para cambiar entre mock y backend real
  static const bool useMock = true;

  // URL del backend — cambiar según entorno
  static const String apiBaseUrl = 'http://10.0.2.2:8000'; // emulador
  // static const String apiBaseUrl = 'http://10.105.176.246:8000'; // móvil físico

  // Configuración de captura
  static const int imageQuality = 85;
  static const int maxImageWidth = 1920;

  // Subdirectorio para almacenar .kpeg
  static const String kpegStorageDir = 'kpeg_files';

  // Subdirectorio para fotos de referencia de personas
  static const String peoplePhotosDir = 'people_photos';
}
