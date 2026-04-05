import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/theme.dart';
import '../models/kpeg_file.dart';

/// Bottom sheet modal con info de Hedera de una imagen .kpeg.
/// Diseñado como lista expandible para añadir más info en el futuro.
class HederaInfoSheet extends StatelessWidget {
  final KpegFile file;

  const HederaInfoSheet({super.key, required this.file});

  static void show(BuildContext context, KpegFile file) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => HederaInfoSheet(file: file),
    );
  }

  @override
  Widget build(BuildContext context) {
    final network = file.hederaNetwork ?? 'testnet';

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF121212),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Título
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: KpegTheme.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.link_rounded,
                        color: KpegTheme.accent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Image Properties',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: KpegTheme.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      network.toUpperCase(),
                      style: const TextStyle(
                        color: KpegTheme.accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Sección: Blockchain Registry ──
              _sectionHeader('Blockchain Registry', Icons.verified_rounded),
              const SizedBox(height: 8),

              if (file.hasHederaData) ...[
                // Hedera File Service
                _infoRow(
                  icon: Icons.cloud_upload_rounded,
                  label: 'File Storage',
                  value: file.hederaFileId ?? 'Pending',
                  copyable: file.hederaFileId != null,
                  explorerUrl: file.hederaFileId != null
                      ? _hashScanUrl(network, 'file', file.hederaFileId!)
                      : null,
                  context: context,
                ),
                const SizedBox(height: 6),

                // Consensus Service (HCS)
                _infoRow(
                  icon: Icons.history_edu_rounded,
                  label: 'Consensus Log',
                  value: file.hederaTopicId ?? 'Pending',
                  subtitle: file.hederaTopicTxId != null
                      ? 'TX: ${_truncate(file.hederaTopicTxId!, 24)}'
                      : null,
                  copyable: file.hederaTopicId != null,
                  context: context,
                ),
                const SizedBox(height: 6),

                // NFT
                _infoRow(
                  icon: Icons.token_rounded,
                  label: 'NFT',
                  value: file.hederaNftTokenId != null
                      ? '${file.hederaNftTokenId} #${file.hederaNftSerial ?? '?'}'
                      : 'Pending',
                  copyable: file.hederaNftTokenId != null,
                  explorerUrl: file.hederaNftTokenId != null
                      ? _hashScanUrl(
                          network, 'token', file.hederaNftTokenId!)
                      : null,
                  context: context,
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          color: Colors.white.withValues(alpha: 0.3),
                          size: 18),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'No blockchain data yet.\nEncode a new photo to register on Hedera.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // ── Sección: Image Details ──
              _sectionHeader('Image Details', Icons.info_outline_rounded),
              const SizedBox(height: 8),
              _detailRow('Filename', file.filename),
              _detailRow('Size', file.fileSizeFormatted),
              _detailRow('Captured', _formatDate(file.capturedAt)),
              if (file.sceneHint != null)
                _detailRow('Scene', file.sceneHint!),
              if (file.imageId != null)
                _detailRow('Image ID', file.imageId!),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: KpegTheme.accent, size: 16),
        const SizedBox(width: 8),
        Text(
          title.toUpperCase(),
          style: TextStyle(
            color: KpegTheme.accent.withValues(alpha: 0.8),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _infoRow({
    required IconData icon,
    required String label,
    required String value,
    String? subtitle,
    bool copyable = false,
    String? explorerUrl,
    required BuildContext context,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KpegTheme.accent.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Icon(icon, color: KpegTheme.accent, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'monospace',
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3),
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (copyable)
            IconButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('$label copied'),
                    duration: const Duration(seconds: 1),
                    backgroundColor: KpegTheme.accent,
                  ),
                );
              },
              icon: Icon(Icons.copy_rounded,
                  color: Colors.white.withValues(alpha: 0.3), size: 16),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _hashScanUrl(String network, String type, String id) {
    return 'https://hashscan.io/$network/$type/$id';
  }

  String _truncate(String s, int max) {
    if (s.length <= max) return s;
    return '${s.substring(0, max)}...';
  }

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}
