import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/indoor_object.dart';
import '../providers/objects_provider.dart';
import '../widgets/kpeg_gradient_background.dart';

class ObjectDetailScreen extends StatefulWidget {
  const ObjectDetailScreen({super.key});

  @override
  State<ObjectDetailScreen> createState() => _ObjectDetailScreenState();
}

class _ObjectDetailScreenState extends State<ObjectDetailScreen> {
  final _nameController = TextEditingController();
  String _category = 'other';
  final List<File> _photos = [];
  bool _saving = false;
  String? _error;

  static const int _minPhotos = 1;
  static const int _maxPhotos = 3;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _addPhoto(ImageSource source) async {
    if (_photos.length >= _maxPhotos) return;
    final picker = ImagePicker();
    final xfile = await picker.pickImage(
        source: source, imageQuality: 85, maxWidth: 1200);
    if (xfile != null) {
      setState(() => _photos.add(File(xfile.path)));
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _photos.length < _minPhotos) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      if (!mounted) return;
      await context.read<ObjectsProvider>().addObject(
            name: name,
            category: _category,
            photos: _photos,
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _nameController.text.trim().isNotEmpty &&
        _photos.length >= _minPhotos &&
        !_saving;

    return Scaffold(
      body: KpegGradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: Colors.white),
                    ),
                    const Text('New object',
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name
                      TextField(
                        controller: _nameController,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                        decoration: InputDecoration(
                          hintText: 'Object name *',
                          hintStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.3)),
                          prefixIcon: const Icon(Icons.category_rounded,
                              color: KpegTheme.accent, size: 20),
                          enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                  color: KpegTheme.accent.withValues(alpha: 0.2))),
                          focusedBorder: const UnderlineInputBorder(
                              borderSide: BorderSide(color: KpegTheme.accent)),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Category
                      Text('Category',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 13)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: IndoorObject.categories.map((cat) {
                          final selected = _category == cat;
                          return ChoiceChip(
                            label: Text(cat),
                            selected: selected,
                            onSelected: (_) =>
                                setState(() => _category = cat),
                            selectedColor:
                                KpegTheme.accent.withValues(alpha: 0.3),
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.05),
                            labelStyle: TextStyle(
                              color: selected
                                  ? KpegTheme.accent
                                  : Colors.white54,
                              fontSize: 13,
                            ),
                            side: BorderSide(
                              color: selected
                                  ? KpegTheme.accent
                                  : Colors.white.withValues(alpha: 0.1),
                            ),
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 20),

                      // Photos
                      Text(
                        '${_photos.length}/$_maxPhotos photos (min $_minPhotos)',
                        style: TextStyle(
                          color: _photos.length >= _minPhotos
                              ? KpegTheme.accent
                              : Colors.white.withValues(alpha: 0.5),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _photoGrid(),
                      const SizedBox(height: 12),

                      if (_photos.length < _maxPhotos)
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _addPhoto(ImageSource.camera),
                                icon: const Icon(Icons.camera_alt_rounded, size: 18),
                                label: const Text('Camera'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: KpegTheme.accent,
                                  side: BorderSide(
                                      color: KpegTheme.accent.withValues(alpha: 0.5)),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _addPhoto(ImageSource.gallery),
                                icon: const Icon(Icons.photo_library_outlined, size: 18),
                                label: const Text('Gallery'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: KpegTheme.accent,
                                  side: BorderSide(
                                      color: KpegTheme.accent.withValues(alpha: 0.5)),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                          ],
                        ),

                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!,
                            style: const TextStyle(
                                color: Colors.redAccent, fontSize: 13)),
                      ],
                    ],
                  ),
                ),
              ),
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
                                strokeWidth: 2, color: Colors.black))
                        : const Icon(Icons.save_rounded),
                    label: Text(_saving ? 'Registering...' : 'Save object',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
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

  Widget _photoGrid() {
    if (_photos.isEmpty) {
      return Container(
        height: 100,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: KpegTheme.accent.withValues(alpha: 0.15)),
        ),
        child: Center(
          child: Text('No photos yet',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3), fontSize: 13)),
        ),
      );
    }

    return SizedBox(
      height: 100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _photos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, index) {
          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(_photos[index],
                    width: 100, height: 100, fit: BoxFit.cover),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: () => setState(() => _photos.removeAt(index)),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      shape: BoxShape.circle,
                    ),
                    child:
                        const Icon(Icons.close, size: 16, color: Colors.white),
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
