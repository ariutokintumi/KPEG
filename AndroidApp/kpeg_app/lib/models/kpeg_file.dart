class KpegFile {
  final int? id;
  final String filename;
  final String filePath;
  final DateTime capturedAt;
  final String? originalPhotoPath;
  final int fileSizeBytes;
  final String? sceneHint;
  final String? thumbnailPath; // Local-only mini thumbnail

  KpegFile({
    this.id,
    required this.filename,
    required this.filePath,
    required this.capturedAt,
    this.originalPhotoPath,
    required this.fileSizeBytes,
    this.sceneHint,
    this.thumbnailPath,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'filename': filename,
      'file_path': filePath,
      'captured_at': capturedAt.toIso8601String(),
      'original_photo_path': originalPhotoPath,
      'file_size_bytes': fileSizeBytes,
      'scene_hint': sceneHint,
      'thumbnail_path': thumbnailPath,
    };
  }

  factory KpegFile.fromMap(Map<String, dynamic> map) {
    return KpegFile(
      id: map['id'] as int,
      filename: map['filename'] as String,
      filePath: map['file_path'] as String,
      capturedAt: DateTime.parse(map['captured_at'] as String),
      originalPhotoPath: map['original_photo_path'] as String?,
      fileSizeBytes: map['file_size_bytes'] as int,
      sceneHint: map['scene_hint'] as String?,
      thumbnailPath: map['thumbnail_path'] as String?,
    );
  }

  String get fileSizeFormatted {
    if (fileSizeBytes < 1024) return '$fileSizeBytes B';
    return '${(fileSizeBytes / 1024).toStringAsFixed(1)} KB';
  }
}
