import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/gallery_provider.dart';
import '../widgets/kpeg_gradient_background.dart';
import '../widgets/kpeg_file_card.dart';
import 'decode_screen.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  @override
  void initState() {
    super.initState();
    // Cargar archivos al entrar en la pestaña
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GalleryProvider>().loadFiles();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GalleryProvider>();

    return KpegGradientBackground(
      child: SafeArea(
        child: Column(
          children: [
            // Cabecera
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: KpegTheme.accent.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: KpegTheme.accent.withValues(alpha: 0.4),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(Icons.photo_library_rounded,
                        size: 28, color: KpegTheme.accent),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Gallery',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${provider.files.length} .kpeg file${provider.files.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: KpegTheme.accent,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),

            // Lista o vacío
            Expanded(
              child: provider.files.isEmpty ? _emptyView() : _listView(provider),
            ),

            // Botón refresh
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: provider.loadFiles,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Refresh'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: KpegTheme.accent,
                    side: BorderSide(
                        color: KpegTheme.accent.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open_rounded,
              size: 56, color: KpegTheme.accent.withValues(alpha: 0.3)),
          const SizedBox(height: 12),
          Text(
            'No .kpeg files yet\nCapture a photo to get started',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3), fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _listView(GalleryProvider provider) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: provider.files.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final file = provider.files[index];
        return KpegFileCard(
          file: file,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChangeNotifierProvider.value(
                  value: provider,
                  child: DecodeScreen(file: file),
                ),
              ),
            );
          },
          onDelete: () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Delete'),
                content: Text('Delete ${file.filename}?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel')),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Delete',
                          style: TextStyle(color: Colors.redAccent))),
                ],
              ),
            );
            if (confirm == true) provider.deleteFile(file);
          },
        );
      },
    );
  }
}
