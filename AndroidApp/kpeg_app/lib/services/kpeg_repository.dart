import 'dart:io';
import 'dart:typed_data';
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

  Future<List<KpegFile>> getAll() async {
    final db = await _dbService.database;
    final maps = await db.query('kpeg_files', orderBy: 'captured_at DESC');
    return maps.map((m) => KpegFile.fromMap(m)).toList();
  }

  /// Guarda un .kpeg: escribe bytes al disco + inserta en DB
  Future<KpegFile> save(
    Uint8List kpegBytes, {
    String? sceneHint,
    String? originalPhotoPath,
  }) async {
    final now = DateTime.now();
    final filename = _generateFilename(now);
    final dir = await _storageDir;
    final filePath = p.join(dir, filename);

    // Escribir bytes al disco
    await File(filePath).writeAsBytes(kpegBytes);

    final kpegFile = KpegFile(
      filename: filename,
      filePath: filePath,
      capturedAt: now,
      originalPhotoPath: originalPhotoPath,
      fileSizeBytes: kpegBytes.length,
      sceneHint: sceneHint,
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
    );
  }

  /// Lee los bytes de un .kpeg del disco
  Future<Uint8List> readBytes(KpegFile file) async {
    return File(file.filePath).readAsBytes();
  }

  Future<void> delete(int id) async {
    final db = await _dbService.database;
    final maps = await db.query('kpeg_files', where: 'id = ?', whereArgs: [id]);
    if (maps.isNotEmpty) {
      final file = File(maps.first['file_path'] as String);
      if (await file.exists()) await file.delete();
    }
    await db.delete('kpeg_files', where: 'id = ?', whereArgs: [id]);
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
