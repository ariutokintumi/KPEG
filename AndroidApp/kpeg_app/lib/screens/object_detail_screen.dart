import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/indoor_object.dart';
import '../providers/objects_provider.dart';
import '../services/api_service.dart';
import '../widgets/kpeg_gradient_background.dart';

class ObjectDetailScreen extends StatefulWidget {
  final IndoorObject? object;

  const ObjectDetailScreen({super.key, this.object});

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

  final _apiService = ApiService();

  // Vista mode
  int _serverPhotoCount = 0;
  bool _loadingCount = false;
  bool _addingPhotos = false;

  bool get _isViewMode => widget.object != null;

  @override
  void initState() {
    super.initState();
    if (_isViewMode) {
      _nameController.text = widget.object!.name;
      _category = widget.object!.category;
      _loadServerPhotoCount();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadServerPhotoCount() async {
    setState(() => _loadingCount = true);
    try {
      final count = await _apiService.getObjectPhotoCount(widget.object!.objectId);
      if (mounted) setState(() {
        _serverPhotoCount = count;
        _loadingCount = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingCount = false);
    }
  }

  Future<void> _addPhoto(ImageSource source) async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(
        source: source, imageQuality: 85, maxWidth: 1200);
    if (xfile == null) return;

    if (_isViewMode) {
      // En modo vista: enviar directamente al servidor
      setState(() {
        _addingPhotos = true;
        _error = null;
      });
      try {
        await _apiService.addObjectPhotos(widget.object!.objectId, [File(xfile.path)]);
        await _loadServerPhotoCount();
        if (mounted) setState(() => _addingPhotos = false);
      } catch (e) {
        if (mounted) setState(() {
          _addingPhotos = false;
          _error = 'Error adding photo: $e';
        });
      }
    } else {
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
    if (_isViewMode) return _buildViewMode(context);
    return _buildCreateMode(context);
  }

  // ══════════════════════════════════════
  // CREATE MODE
  // ══════════════════════════════════════

  Widget _buildCreateMode(BuildContext context) {
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
                      _categorySelector(),

                      const SizedBox(height: 20),

                      // Photos — sin maximo
                      Text(
                        '${_photos.length} photos (min $_minPhotos)',
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

                      // Add buttons — sin limite
                      _addButtons(),

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

  // ══════════════════════════════════════
  // VIEW/EDIT MODE
  // ══════════════════════════════════════

  Widget _buildViewMode(BuildContext context) {
    final obj = widget.object!;

    return Scaffold(
      body: KpegGradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              // Header con nombre
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                    ),
                    Expanded(
                      child: Text(
                        obj.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),

                      // Info section
                      _infoSection(obj),

                      const SizedBox(height: 24),

                      // Photo count
                      Row(
                        children: [
                          Text(
                            _loadingCount
                                ? 'Loading photos...'
                                : '$_serverPhotoCount photos on server',
                            style: TextStyle(
                              color: KpegTheme.accent,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (_loadingCount) ...[
                            const SizedBox(width: 8),
                            const SizedBox(
                              width: 12, height: 12,
                              child: CircularProgressIndicator(strokeWidth: 1.5, color: KpegTheme.accent),
                            ),
                          ],
                        ],
                      ),

                      const SizedBox(height: 12),

                      // Existing photos from server
                      if (_serverPhotoCount > 0) _serverPhotoGrid(obj),

                      const SizedBox(height: 20),

                      // Add more photos section
                      Text(
                        'Add more photos',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),

                      const SizedBox(height: 12),

                      if (_addingPhotos)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: KpegTheme.accent)),
                              SizedBox(width: 8),
                              Text('Adding photo...', style: TextStyle(color: KpegTheme.accent, fontSize: 13)),
                            ],
                          ),
                        ),

                      if (!_addingPhotos) _addButtons(),

                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!,
                            style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                            textAlign: TextAlign.center),
                      ],

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoSection(IndoorObject obj) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: KpegTheme.accent.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Object ID — copiable
          Row(
            children: [
              Text('ID: ',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: obj.objectId));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Object ID copied'), duration: Duration(seconds: 1)),
                    );
                  },
                  child: Text(
                    obj.objectId,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              Icon(Icons.copy_rounded, size: 14, color: Colors.white.withValues(alpha: 0.3)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Category: ${obj.category}',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text(
            'Created: ${_formatDate(obj.createdAt)}',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            'Photos: ${obj.photoCount}',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _serverPhotoGrid(IndoorObject obj) {
    return SizedBox(
      height: 100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _serverPhotoCount,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, index) {
          final url = _apiService.objectPhotoUrl(obj.objectId, index);
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              url,
              width: 100,
              height: 100,
              fit: BoxFit.cover,
              loadingBuilder: (_, child, progress) {
                if (progress == null) return child;
                return Container(
                  width: 100, height: 100,
                  color: Colors.white.withValues(alpha: 0.05),
                  child: const Center(
                    child: SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: KpegTheme.accent),
                    ),
                  ),
                );
              },
              errorBuilder: (_, __, ___) => Container(
                width: 100, height: 100,
                color: Colors.white.withValues(alpha: 0.05),
                child: Icon(Icons.broken_image_rounded,
                    color: Colors.white.withValues(alpha: 0.2), size: 28),
              ),
            ),
          );
        },
      ),
    );
  }

  // ══════════════════════════════════════
  // SHARED WIDGETS
  // ══════════════════════════════════════

  Widget _categorySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
              onSelected: _isViewMode ? null : (_) => setState(() => _category = cat),
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
      ],
    );
  }

  Widget _addButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _addPhoto(ImageSource.camera),
            icon: const Icon(Icons.camera_alt_rounded, size: 18),
            label: const Text('Camera'),
            style: OutlinedButton.styleFrom(
              foregroundColor: KpegTheme.accent,
              side: BorderSide(color: KpegTheme.accent.withValues(alpha: 0.5)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
              side: BorderSide(color: KpegTheme.accent.withValues(alpha: 0.5)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
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

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
