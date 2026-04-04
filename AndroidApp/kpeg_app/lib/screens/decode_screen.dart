import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/kpeg_file.dart';
import '../providers/gallery_provider.dart';
import '../widgets/kpeg_gradient_background.dart';
import '../widgets/quality_selector.dart';

class DecodeScreen extends StatelessWidget {
  final KpegFile file;

  const DecodeScreen({super.key, required this.file});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GalleryProvider>();

    return Scaffold(
      body: KpegGradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              // Header con botón atrás
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        provider.resetDecode();
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: Colors.white),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            file.filename,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600),
                          ),
                          Text(
                            file.fileSizeFormatted,
                            style: TextStyle(
                                color: KpegTheme.accent.withValues(alpha: 0.8),
                                fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Imagen decodificada o estado
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildContent(provider),
                ),
              ),

              // Selector de calidad + botón decode
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    QualitySelector(
                      selected: provider.selectedQuality,
                      onChanged: provider.setQuality,
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: provider.decodeState == DecodeState.decoding
                            ? null
                            : () => provider.decodeFile(file),
                        icon: provider.decodeState == DecodeState.decoding
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.black),
                              )
                            : const Icon(Icons.auto_awesome_rounded),
                        label: Text(
                          provider.decodeState == DecodeState.decoding
                              ? 'Reconstructing...'
                              : provider.decodeState == DecodeState.success
                                  ? 'Reconstruct again'
                                  : 'Reconstruct with AI',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: KpegTheme.accent,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(GalleryProvider provider) {
    switch (provider.decodeState) {
      case DecodeState.idle:
        return _placeholderView();
      case DecodeState.decoding:
        return _loadingView();
      case DecodeState.success:
        return _imageView(provider);
      case DecodeState.error:
        return _errorView(provider);
    }
  }

  Widget _placeholderView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.auto_awesome_rounded,
              size: 64, color: KpegTheme.accent.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(
            'Select quality and tap\n"Reconstruct with AI"',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3), fontSize: 14),
          ),
          if (file.sceneHint != null) ...[
            const SizedBox(height: 12),
            Text(
              '"${file.sceneHint}"',
              style: TextStyle(
                  color: KpegTheme.accent.withValues(alpha: 0.5),
                  fontSize: 13,
                  fontStyle: FontStyle.italic),
            ),
          ],
        ],
      ),
    );
  }

  Widget _loadingView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: KpegTheme.accent),
          SizedBox(height: 20),
          Text(
            'AI is reconstructing your image...',
            style: TextStyle(color: Colors.white70, fontSize: 15),
          ),
          SizedBox(height: 8),
          Text(
            'This may take 5-15 seconds',
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _imageView(GalleryProvider provider) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: InteractiveViewer(
        child: Image.memory(
          provider.decodedImageBytes!,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  Widget _errorView(GalleryProvider provider) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
          const SizedBox(height: 16),
          Text(
            provider.errorMessage ?? 'Unknown error',
            style: const TextStyle(color: Colors.redAccent, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
