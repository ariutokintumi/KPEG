class KpegFile {
  final int? id;
  final String filename;
  final String filePath;
  final DateTime capturedAt;
  final String? originalPhotoPath;
  final int fileSizeBytes;
  final String? sceneHint;
  final String? thumbnailPath; // Local-only mini thumbnail

  // Hedera metadata
  final String? imageId; // ID de referencia en el backend
  final String? hederaFileId; // Hedera File Service ID
  final String? hederaTopicId; // HCS topic ID
  final String? hederaTopicTxId; // HCS transaction ID
  final String? hederaNftTokenId; // NFT collection token ID
  final String? hederaNftSerial; // NFT serial number
  final String? hederaNetwork; // testnet / mainnet

  KpegFile({
    this.id,
    required this.filename,
    required this.filePath,
    required this.capturedAt,
    this.originalPhotoPath,
    required this.fileSizeBytes,
    this.sceneHint,
    this.thumbnailPath,
    this.imageId,
    this.hederaFileId,
    this.hederaTopicId,
    this.hederaTopicTxId,
    this.hederaNftTokenId,
    this.hederaNftSerial,
    this.hederaNetwork,
  });

  bool get hasHederaData =>
      hederaFileId != null || hederaNftTokenId != null || hederaTopicId != null;

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
      'image_id': imageId,
      'hedera_file_id': hederaFileId,
      'hedera_topic_id': hederaTopicId,
      'hedera_topic_tx_id': hederaTopicTxId,
      'hedera_nft_token_id': hederaNftTokenId,
      'hedera_nft_serial': hederaNftSerial,
      'hedera_network': hederaNetwork,
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
      imageId: map['image_id'] as String?,
      hederaFileId: map['hedera_file_id'] as String?,
      hederaTopicId: map['hedera_topic_id'] as String?,
      hederaTopicTxId: map['hedera_topic_tx_id'] as String?,
      hederaNftTokenId: map['hedera_nft_token_id'] as String?,
      hederaNftSerial: map['hedera_nft_serial'] as String?,
      hederaNetwork: map['hedera_network'] as String?,
    );
  }

  String get fileSizeFormatted {
    if (fileSizeBytes < 1024) return '$fileSizeBytes B';
    return '${(fileSizeBytes / 1024).toStringAsFixed(1)} KB';
  }
}
