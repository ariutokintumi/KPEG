import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../config/app_config.dart';
import '../models/kpeg_file.dart';
import 'database_service.dart';

class KpegRepository {
  final DatabaseService _dbService;

  KpegRepository(this._dbService);

  Future<String> get _storageDir async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, AppConfig.kpegStorageDir));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  Future<String> get _thumbDir async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'kpeg_thumbnails'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  Future<List<KpegFile>> getAll() async {
    final db = await _dbService.database;
    final maps = await db.query('kpeg_files', orderBy: 'captured_at DESC');
    return maps.map((m) => KpegFile.fromMap(m)).toList();
  }

  /// Save .kpeg + generate local thumbnail from original photo
  Future<KpegFile> save(
    Uint8List kpegBytes, {
    String? sceneHint,
    String? originalPhotoPath,
  }) async {
    final now = DateTime.now();
    final filename = _generateFilename(now);
    final dir = await _storageDir;
    final filePath = p.join(dir, filename);

    await File(filePath).writeAsBytes(kpegBytes);

    // Generate local thumbnail from original photo (never sent to server)
    String? thumbnailPath;
    if (originalPhotoPath != null) {
      try {
        thumbnailPath = await _generateThumbnail(originalPhotoPath, now);
      } catch (_) {
        // Thumbnail generation failed — continue without it
      }
    }

    final kpegFile = KpegFile(
      filename: filename,
      filePath: filePath,
      capturedAt: now,
      originalPhotoPath: originalPhotoPath,
      fileSizeBytes: kpegBytes.length,
      sceneHint: sceneHint,
      thumbnailPath: thumbnailPath,
    );

    final db = await _dbService.database;
    final id = await db.insert('kpeg_files', kpegFile.toMap());
    return KpegFile(
      id: id,
      filename: kpegFile.filename,
      filePath: kpegFile.filePath,
      capturedAt: kpegFile.capturedAt,
      originalPhotoPath: kpegFile.originalPhotoPath,
      fileSizeBytes: kpegFile.fileSizeBytes,
      sceneHint: kpegFile.sceneHint,
      thumbnailPath: kpegFile.thumbnailPath,
    );
  }

  Future<Uint8List> readBytes(KpegFile file) async {
    return File(file.filePath).readAsBytes();
  }

  Future<void> delete(int id) async {
    final db = await _dbService.database;
    final maps = await db.query('kpeg_files', where: 'id = ?', whereArgs: [id]);
    if (maps.isNotEmpty) {
      final kpeg = File(maps.first['file_path'] as String);
      if (await kpeg.exists()) await kpeg.delete();
      // Delete thumbnail too
      final thumb = maps.first['thumbnail_path'] as String?;
      if (thumb != null) {
        final thumbFile = File(thumb);
        if (await thumbFile.exists()) await thumbFile.delete();
      }
    }
    await db.delete('kpeg_files', where: 'id = ?', whereArgs: [id]);
  }

  /// Generate a small JPEG thumbnail (local only, never sent to server)
  Future<String> _generateThumbnail(String originalPath, DateTime dt) async {
    final bytes = await File(originalPath).readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) throw Exception('Failed to decode');

    // Resize to max 120px on longest side
    final resized = img.copyResize(image,
        width: image.width >= image.height ? 120 : null,
        height: image.height > image.width ? 120 : null);
    final jpgBytes = img.encodeJpg(resized, quality: 60);

    final dir = await _thumbDir;
    final ts = dt.millisecondsSinceEpoch;
    final path = p.join(dir, 'thumb_$ts.jpg');
    await File(path).writeAsBytes(jpgBytes);
    return path;
  }

  String _generateFilename(DateTime dt) {
    final ts = '${dt.year}'
        '${dt.month.toString().padLeft(2, '0')}'
        '${dt.day.toString().padLeft(2, '0')}'
        '_${dt.hour.toString().padLeft(2, '0')}'
        '${dt.minute.toString().padLeft(2, '0')}'
        '${dt.second.toString().padLeft(2, '0')}';
    return 'KPEG_$ts.kpeg';
  }
}
