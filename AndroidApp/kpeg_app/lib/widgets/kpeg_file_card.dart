import 'dart:io';
import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/kpeg_file.dart';

class KpegFileCard extends StatelessWidget {
  final KpegFile file;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const KpegFileCard({
    super.key,
    required this.file,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: KpegTheme.accent.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            // Thumbnail or icon
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: file.thumbnailPath != null
                  ? Image.file(
                      File(file.thumbnailPath!),
                      width: 52,
                      height: 52,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholderIcon(),
                    )
                  : _placeholderIcon(),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.filename,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    file.fileSizeFormatted,
                    style: TextStyle(
                        color: KpegTheme.accent.withValues(alpha: 0.8),
                        fontSize: 12,
                        fontWeight: FontWeight.w700),
                  ),
                  if (file.sceneHint != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      file.sceneHint!,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    _formatDate(file.capturedAt),
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.3),
                        fontSize: 11),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onDelete,
              icon: Icon(Icons.delete_outline,
                  color: Colors.white.withValues(alpha: 0.3), size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholderIcon() {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: KpegTheme.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.image_rounded,
          color: KpegTheme.accent, size: 24),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}
