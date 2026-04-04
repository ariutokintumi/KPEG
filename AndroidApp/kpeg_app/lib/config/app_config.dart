class AppConfig {
  // Mock mode OFF — using real API
  static const bool useMock = false;

  // Backend URL — change per environment
  // static const String apiBaseUrl = 'http://10.0.2.2:8000'; // emulator
  static const String apiBaseUrl = 'http://10.105.176.246:8000'; // physical device

  // Capture settings
  static const int imageQuality = 85;
  static const int maxImageWidth = 1920;

  // Local storage subdirectories
  static const String kpegStorageDir = 'kpeg_files';
  static const String peoplePhotosDir = 'people_photos';
}
