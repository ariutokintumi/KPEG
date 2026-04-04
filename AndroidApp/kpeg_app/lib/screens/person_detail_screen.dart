import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/people_provider.dart';
import '../widgets/kpeg_gradient_background.dart';

class PersonDetailScreen extends StatefulWidget {
  const PersonDetailScreen({super.key});

  @override
  State<PersonDetailScreen> createState() => _PersonDetailScreenState();
}

class _PersonDetailScreenState extends State<PersonDetailScreen> {
  final _nameController = TextEditingController();
  File? _photo;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
      maxWidth: 800,
    );
    if (xfile != null) {
      setState(() => _photo = File(xfile.path));
    }
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
      maxWidth: 800,
    );
    if (xfile != null) {
      setState(() => _photo = File(xfile.path));
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _photo == null) return;

    setState(() => _saving = true);

    await context.read<PeopleProvider>().addPerson(name, _photo!);

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _nameController.text.trim().isNotEmpty && _photo != null;

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
                    const Text(
                      'New person',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      const SizedBox(height: 20),

                      // Foto de referencia
                      GestureDetector(
                        onTap: _takePhoto,
                        child: Container(
                          width: 180,
                          height: 180,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: KpegTheme.accent.withValues(alpha: 0.3),
                              width: 2,
                            ),
                            image: _photo != null
                                ? DecorationImage(
                                    image: FileImage(_photo!),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: _photo == null
                              ? Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.person_add_rounded,
                                        size: 48,
                                        color: KpegTheme.accent
                                            .withValues(alpha: 0.4)),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Tap to\ntake photo',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: 0.3),
                                          fontSize: 12),
                                    ),
                                  ],
                                )
                              : null,
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Botón galería
                      TextButton.icon(
                        onPressed: _pickFromGallery,
                        icon: const Icon(Icons.photo_library_outlined, size: 16),
                        label: const Text('Or pick from gallery', style: TextStyle(fontSize: 13)),
                        style: TextButton.styleFrom(
                          foregroundColor: KpegTheme.accent.withValues(alpha: 0.7),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Nombre
                      TextField(
                        controller: _nameController,
                        onChanged: (_) => setState(() {}),
                        style:
                            const TextStyle(color: Colors.white, fontSize: 18),
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          hintText: 'Person\'s name',
                          hintStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.3)),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                                color:
                                    KpegTheme.accent.withValues(alpha: 0.3)),
                          ),
                          focusedBorder: const UnderlineInputBorder(
                            borderSide:
                                BorderSide(color: KpegTheme.accent, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Botón guardar
              Padding(
                padding: const EdgeInsets.all(24),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: canSave && !_saving ? _save : null,
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
}
