import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/person.dart';
import '../providers/capture_provider.dart';
import '../providers/people_provider.dart';
import '../widgets/kpeg_gradient_background.dart';
import '../widgets/face_overlay.dart';
import '../widgets/metadata_form.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CaptureProvider>().startSensors();
    });
  }

  @override
  void dispose() {
    // No usamos context.read en dispose, el provider vive más que el widget
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CaptureProvider>();

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
                    child: const Icon(Icons.camera_alt_rounded,
                        size: 28, color: KpegTheme.accent),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'KPEG',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 6,
                    ),
                  ),
                ],
              ),
            ),

            // Preview + metadata
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    // Preview de la foto con face overlay
                    SizedBox(
                      height: 300,
                      width: double.infinity,
                      child: provider.photo == null
                          ? _emptyView()
                          : _photoView(context, provider),
                    ),

                    // Info de caras detectadas
                    if (provider.state == CaptureState.captured &&
                        provider.detectedFaces.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _facesInfoBar(provider),
                    ],

                    // Formulario de metadata (solo si hay foto)
                    if (provider.state == CaptureState.captured) ...[
                      const SizedBox(height: 12),
                      MetadataForm(
                        isOutdoor: provider.isOutdoor,
                        onOutdoorChanged: provider.setOutdoor,
                        sceneHint: provider.sceneHint,
                        onSceneHintChanged: provider.setSceneHint,
                        tagsText: provider.tagsText,
                        onTagsChanged: provider.setTagsText,
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Status + botones
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  if (provider.state == CaptureState.success &&
                      provider.lastSavedFile != null)
                    _successBanner(provider),
                  if (provider.state == CaptureState.error)
                    _errorBanner(provider),
                  _buildButtons(context, provider),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _facesInfoBar(CaptureProvider provider) {
    final total = provider.detectedFaces.length;
    final tagged = provider.detectedFaces.where((f) => f.isTagged).length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: KpegTheme.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.face_rounded, color: KpegTheme.accent, size: 16),
          const SizedBox(width: 6),
          Text(
            '$total cara${total == 1 ? '' : 's'} detectada${total == 1 ? '' : 's'}'
            '${tagged > 0 ? ' ($tagged etiquetada${tagged == 1 ? '' : 's'})' : ''}',
            style: const TextStyle(color: KpegTheme.accent, fontSize: 12),
          ),
          const SizedBox(width: 6),
          Text(
            '— toca para etiquetar',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _emptyView() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
            color: KpegTheme.accent.withValues(alpha: 0.2), width: 1.5),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_a_photo_rounded,
                size: 56, color: KpegTheme.accent.withValues(alpha: 0.3)),
            const SizedBox(height: 12),
            Text(
              'Pulsa el botón para\nhacer una foto',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3), fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photoView(BuildContext context, CaptureProvider provider) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            fit: StackFit.expand,
            children: [
              Image.file(provider.photo!, fit: BoxFit.cover),
              // Gradiente inferior
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.4),
                    ],
                  ),
                ),
              ),
              // Face overlay
              if (provider.detectedFaces.isNotEmpty &&
                  provider.state == CaptureState.captured)
                FaceOverlay(
                  faces: provider.detectedFaces,
                  imageWidth: provider.photoWidth ?? 1,
                  imageHeight: provider.photoHeight ?? 1,
                  displaySize: Size(
                      constraints.maxWidth, constraints.maxHeight),
                  onFaceTap: (index) =>
                      _showPersonPicker(context, provider, index),
                ),
              // Detecting spinner
              if (provider.state == CaptureState.detecting)
                Container(
                  color: Colors.black.withValues(alpha: 0.5),
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: KpegTheme.accent),
                        SizedBox(height: 12),
                        Text('Detectando caras...',
                            style:
                                TextStyle(color: Colors.white, fontSize: 14)),
                      ],
                    ),
                  ),
                ),
              // Check de éxito
              if (provider.state == CaptureState.success)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.85),
                      shape: BoxShape.circle,
                    ),
                    child:
                        const Icon(Icons.check, size: 48, color: Colors.white),
                  ),
                ),
              // Encoding spinner
              if (provider.state == CaptureState.encoding)
                Container(
                  color: Colors.black.withValues(alpha: 0.5),
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: KpegTheme.accent),
                        SizedBox(height: 12),
                        Text('Codificando...',
                            style:
                                TextStyle(color: Colors.white, fontSize: 14)),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  void _showPersonPicker(
      BuildContext context, CaptureProvider captureProvider, int faceIndex) {
    final people = context.read<PeopleProvider>().people;

    if (people.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Añade personas primero en la pestaña "Personas"'),
          backgroundColor: KpegTheme.accent,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: KpegTheme.bgDark1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '¿Quién es?',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              ...people.map((person) => _personOption(
                  ctx, captureProvider, faceIndex, person)),
              const SizedBox(height: 8),
              // Opción de quitar etiqueta
              if (captureProvider.detectedFaces[faceIndex].isTagged)
                ListTile(
                  leading: const Icon(Icons.close, color: Colors.redAccent),
                  title: const Text('Quitar etiqueta',
                      style: TextStyle(color: Colors.redAccent)),
                  onTap: () {
                    captureProvider.unassignFace(faceIndex);
                    Navigator.pop(ctx);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _personOption(BuildContext ctx, CaptureProvider provider,
      int faceIndex, Person person) {
    return ListTile(
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: KpegTheme.accent.withValues(alpha: 0.2),
        backgroundImage: person.referencePhotoPath != null
            ? FileImage(
                File(person.referencePhotoPath!))
            : null,
        child: person.referencePhotoPath == null
            ? const Icon(Icons.person, color: KpegTheme.accent, size: 20)
            : null,
      ),
      title: Text(person.name,
          style: const TextStyle(color: Colors.white, fontSize: 15)),
      subtitle: Text(person.userId,
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
      onTap: () {
        provider.assignPersonToFace(
            faceIndex, person.id!, person.userId, person.name);
        Navigator.pop(ctx);
      },
    );
  }

  Widget _successBanner(CaptureProvider provider) {
    final file = provider.lastSavedFile!;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${file.filename} (${file.fileSizeFormatted})',
              style: const TextStyle(color: Colors.green, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorBanner(CaptureProvider provider) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
      ),
      child: Text(
        provider.errorMessage ?? 'Error desconocido',
        style: const TextStyle(color: Colors.redAccent, fontSize: 13),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildButtons(BuildContext context, CaptureProvider provider) {
    final isBusy = provider.state == CaptureState.encoding ||
        provider.state == CaptureState.detecting;

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: isBusy
                ? null
                : () {
                    if (provider.state == CaptureState.success) {
                      provider.reset();
                    }
                    provider.capturePhoto();
                  },
            icon: const Icon(Icons.camera_alt_rounded),
            label: Text(
              provider.photo == null ? 'Hacer foto' : 'Nueva foto',
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: KpegTheme.accent,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              elevation: 8,
              shadowColor: KpegTheme.accent.withValues(alpha: 0.4),
            ),
          ),
        ),
        if (provider.state == CaptureState.captured) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              onPressed: isBusy ? null : provider.encodeAndSave,
              icon: const Icon(Icons.compress_rounded),
              label: const Text(
                'Codificar .kpeg',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: KpegTheme.accent,
                side:
                    const BorderSide(color: KpegTheme.accent, width: 1.5),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
