import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/people_provider.dart';
import '../services/face_recognition_service.dart';
import '../widgets/kpeg_gradient_background.dart';

class PersonDetailScreen extends StatefulWidget {
  final FaceRecognitionService faceRecognition;

  const PersonDetailScreen({super.key, required this.faceRecognition});

  @override
  State<PersonDetailScreen> createState() => _PersonDetailScreenState();
}

class _PersonDetailScreenState extends State<PersonDetailScreen> {
  final _nameController = TextEditingController();
  final List<({File photo, Uint8List embedding})> _selfies = [];
  bool _saving = false;
  String? _error;

  static const int _minSelfies = 2;
  static const int _maxSelfies = 5;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _takeSelfie() async {
    if (_selfies.length >= _maxSelfies) return;

    final picker = ImagePicker();
    final xfile = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
      maxWidth: 800,
      preferredCameraDevice: CameraDevice.front,
    );
    if (xfile == null) return;

    setState(() => _error = null);

    try {
      final file = File(xfile.path);
      final embedding = await widget.faceRecognition.extractSelfieEmbedding(file);
      setState(() {
        _selfies.add((photo: file, embedding: embedding));
      });
    } catch (e) {
      setState(() => _error = 'Could not detect face. Try again with better lighting.');
    }
  }

  Future<void> _pickFromGallery() async {
    if (_selfies.length >= _maxSelfies) return;

    final picker = ImagePicker();
    final xfile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
      maxWidth: 800,
    );
    if (xfile == null) return;

    setState(() => _error = null);

    try {
      final file = File(xfile.path);
      final embedding = await widget.faceRecognition.extractSelfieEmbedding(file);
      setState(() {
        _selfies.add((photo: file, embedding: embedding));
      });
    } catch (e) {
      setState(() => _error = 'Could not process photo.');
    }
  }

  void _removeSelfie(int index) {
    setState(() {
      _selfies.removeAt(index);
    });
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _selfies.length < _minSelfies) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await context.read<PeopleProvider>().addPersonWithSelfies(name, _selfies);
      // Reload embeddings cache
      await widget.faceRecognition.loadEmbeddings();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = 'Error saving: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _nameController.text.trim().isNotEmpty &&
        _selfies.length >= _minSelfies &&
        !_saving;

    return Scaffold(
      body: KpegGradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: Colors.white),
                    ),
                    const Text('New person',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      const SizedBox(height: 12),

                      // Name input
                      TextField(
                        controller: _nameController,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(
                            color: Colors.white, fontSize: 18),
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          hintText: 'Person\'s name',
                          hintStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.3)),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                                color: KpegTheme.accent.withValues(alpha: 0.3)),
                          ),
                          focusedBorder: const UnderlineInputBorder(
                            borderSide: BorderSide(
                                color: KpegTheme.accent, width: 2),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Selfie counter
                      Text(
                        '${_selfies.length}/$_maxSelfies selfies (min $_minSelfies)',
                        style: TextStyle(
                          color: _selfies.length >= _minSelfies
                              ? KpegTheme.accent
                              : Colors.white.withValues(alpha: 0.5),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),

                      const SizedBox(height: 4),
                      Text(
                        'Take photos from different angles',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.3),
                            fontSize: 12),
                      ),

                      const SizedBox(height: 16),

                      // Selfie grid
                      _selfieGrid(),

                      const SizedBox(height: 16),

                      // Add selfie buttons
                      if (_selfies.length < _maxSelfies) ...[
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _takeSelfie,
                                icon: const Icon(Icons.camera_alt_rounded,
                                    size: 18),
                                label: const Text('Camera'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: KpegTheme.accent,
                                  side: BorderSide(
                                      color: KpegTheme.accent
                                          .withValues(alpha: 0.5)),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _pickFromGallery,
                                icon: const Icon(
                                    Icons.photo_library_outlined,
                                    size: 18),
                                label: const Text('Gallery'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: KpegTheme.accent,
                                  side: BorderSide(
                                      color: KpegTheme.accent
                                          .withValues(alpha: 0.5)),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],

                      // Error message
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!,
                            style: const TextStyle(
                                color: Colors.redAccent, fontSize: 13),
                            textAlign: TextAlign.center),
                      ],
                    ],
                  ),
                ),
              ),

              // Save button
              Padding(
                padding: const EdgeInsets.all(24),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: canSave ? _save : null,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.black),
                          )
                        : const Icon(Icons.save_rounded),
                    label: Text(
                      _saving ? 'Saving...' : 'Save person',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: KpegTheme.accent,
                      foregroundColor: Colors.black,
                      disabledBackgroundColor:
                          KpegTheme.accent.withValues(alpha: 0.3),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _selfieGrid() {
    if (_selfies.isEmpty) {
      return Container(
        height: 120,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: KpegTheme.accent.withValues(alpha: 0.15)),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.face_rounded,
                  size: 36, color: KpegTheme.accent.withValues(alpha: 0.3)),
              const SizedBox(height: 8),
              Text('No selfies yet',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3),
                      fontSize: 13)),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _selfies.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  _selfies[index].photo,
                  width: 100,
                  height: 100,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: () => _removeSelfie(index),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close,
                        size: 16, color: Colors.white),
                  ),
                ),
              ),
              // Index label
              Positioned(
                bottom: 4,
                left: 4,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: KpegTheme.accent.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '#${index + 1}',
                    style: const TextStyle(
                        color: Colors.black,
                        fontSize: 10,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
