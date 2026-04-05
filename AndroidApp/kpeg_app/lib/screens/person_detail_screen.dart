import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../config/app_config.dart';
import '../config/theme.dart';
import '../models/person.dart';
import '../providers/people_provider.dart';
import '../services/api_service.dart';
import '../services/face_detection_service.dart';
import '../widgets/kpeg_gradient_background.dart';

class PersonDetailScreen extends StatefulWidget {
  final Person? person;

  const PersonDetailScreen({super.key, this.person});

  @override
  State<PersonDetailScreen> createState() => _PersonDetailScreenState();
}

class _PersonDetailScreenState extends State<PersonDetailScreen> {
  final _nameController = TextEditingController();
  // Each selfie: original file + cropped face bytes
  final List<({File original, Uint8List faceCrop})> _selfies = [];
  bool _saving = false;
  bool _processing = false;
  String? _error;

  static const int _minSelfies = 2;

  final _faceDetection = FaceDetectionService();
  final _apiService = ApiService();

  // Vista mode: foto count desde servidor
  int _serverSelfieCount = 0;
  bool _loadingCount = false;

  bool get _isViewMode => widget.person != null;

  @override
  void initState() {
    super.initState();
    if (_isViewMode) {
      _nameController.text = widget.person!.name;
      _loadServerSelfieCount();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _faceDetection.dispose();
    super.dispose();
  }

  Future<void> _loadServerSelfieCount() async {
    setState(() => _loadingCount = true);
    try {
      final count = await _apiService.getPersonSelfieCount(widget.person!.visibleUserId);
      if (mounted) setState(() {
        _serverSelfieCount = count;
        _loadingCount = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingCount = false);
    }
  }

  Future<void> _addSelfie(ImageSource source) async {
    if (_processing) return;

    final picker = ImagePicker();
    final xfile = await picker.pickImage(
      source: source,
      imageQuality: 90,
      maxWidth: 800,
      preferredCameraDevice: CameraDevice.front,
    );
    if (xfile == null) return;

    setState(() {
      _processing = true;
      _error = null;
    });

    try {
      final file = File(xfile.path);
      final decodedImage = await decodeImageFromList(await file.readAsBytes());
      final width = decodedImage.width;
      final height = decodedImage.height;

      // Detect face with ML Kit
      final faces = await _faceDetection.detectFaces(
        file,
        imageWidth: width,
        imageHeight: height,
      );

      if (faces.isEmpty) {
        setState(() {
          _processing = false;
          _error = 'No face detected. Try with better lighting.';
        });
        return;
      }

      // Crop the first (largest) face
      final face = faces.first;
      final imageBytes = await file.readAsBytes();
      final image = img.decodeImage(imageBytes);
      if (image == null) throw Exception('Failed to decode');
      final bb = face.boundingBox;
      final padX = (bb.right - bb.left) * 0.1;
      final padY = (bb.bottom - bb.top) * 0.1;
      final cx = (bb.left - padX).clamp(0, width - 1).toInt();
      final cy = (bb.top - padY).clamp(0, height - 1).toInt();
      final cw = ((bb.right - bb.left) + padX * 2).toInt().clamp(1, width - cx);
      final ch = ((bb.bottom - bb.top) + padY * 2).toInt().clamp(1, height - cy);
      final cropped = img.copyCrop(image, x: cx, y: cy, width: cw, height: ch);
      final cropBytes = Uint8List.fromList(img.encodeJpg(cropped, quality: 85));

      if (_isViewMode) {
        // En modo vista: guardar como archivo y enviar al servidor
        final appDir = await getApplicationDocumentsDirectory();
        final photosDir = Directory(p.join(appDir.path, AppConfig.peoplePhotosDir));
        if (!await photosDir.exists()) await photosDir.create(recursive: true);
        final ts = DateTime.now().millisecondsSinceEpoch;
        final path = p.join(photosDir.path, 'face_$ts.jpg');
        final cropFile = File(path);
        await cropFile.writeAsBytes(cropBytes);

        await _apiService.addPersonSelfies(widget.person!.visibleUserId, [cropFile]);
        await _loadServerSelfieCount();

        setState(() {
          _processing = false;
          _error = null;
        });
      } else {
        setState(() {
          _selfies.add((original: file, faceCrop: cropBytes));
          _processing = false;
        });
      }
    } catch (e) {
      setState(() {
        _processing = false;
        _error = 'Error processing photo: $e';
      });
    }
  }

  void _removeSelfie(int index) {
    setState(() => _selfies.removeAt(index));
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _selfies.length < _minSelfies) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      // Save face crops as files to send to server
      final appDir = await getApplicationDocumentsDirectory();
      final photosDir =
          Directory(p.join(appDir.path, AppConfig.peoplePhotosDir));
      if (!await photosDir.exists()) await photosDir.create(recursive: true);

      final selfieFiles = <File>[];
      String? thumbnailPath;

      for (int i = 0; i < _selfies.length; i++) {
        final ts = DateTime.now().millisecondsSinceEpoch + i;
        final path = p.join(photosDir.path, 'face_$ts.jpg');
        final file = File(path);
        await file.writeAsBytes(_selfies[i].faceCrop);
        selfieFiles.add(file);

        // First crop = local thumbnail
        if (i == 0) thumbnailPath = path;
      }

      if (!mounted) return;
      await context.read<PeopleProvider>().addPerson(name, selfieFiles, thumbnailPath: thumbnailPath);
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
        _selfies.length >= _minSelfies &&
        !_saving &&
        !_processing;

    return Scaffold(
      body: KpegGradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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

                      // Name
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
                                color:
                                    KpegTheme.accent.withValues(alpha: 0.3)),
                          ),
                          focusedBorder: const UnderlineInputBorder(
                            borderSide:
                                BorderSide(color: KpegTheme.accent, width: 2),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Counter — sin maximo
                      Text(
                        '${_selfies.length} selfies (min $_minSelfies)',
                        style: TextStyle(
                          color: _selfies.length >= _minSelfies
                              ? KpegTheme.accent
                              : Colors.white.withValues(alpha: 0.5),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text('Face is auto-cropped from each photo',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.3),
                              fontSize: 12)),

                      const SizedBox(height: 16),

                      // Face crops grid
                      _selfieGrid(),

                      const SizedBox(height: 16),

                      // Processing indicator
                      if (_processing) _processingIndicator(),

                      // Add buttons — sin limite
                      if (!_processing)
                        _addButtons(),

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

              // Save
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
                    label: Text(
                      _saving ? 'Registering...' : 'Save person',
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

  // ══════════════════════════════════════
  // VIEW/EDIT MODE
  // ══════════════════════════════════════

  Widget _buildViewMode(BuildContext context) {
    final person = widget.person!;

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
                        person.name,
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
                      _infoSection(person),

                      const SizedBox(height: 24),

                      // Selfie count
                      Row(
                        children: [
                          Text(
                            _loadingCount
                                ? 'Loading selfies...'
                                : '$_serverSelfieCount selfies on server',
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

                      // Existing selfies from server
                      if (_serverSelfieCount > 0) _serverSelfieGrid(person),

                      const SizedBox(height: 20),

                      // Separator
                      Text(
                        'Add more selfies',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text('Face is auto-cropped from each photo',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.3),
                              fontSize: 12)),

                      const SizedBox(height: 12),

                      // Processing indicator
                      if (_processing) _processingIndicator(),

                      // Add buttons
                      if (!_processing) _addButtons(),

                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!,
                            style: const TextStyle(
                                color: Colors.redAccent, fontSize: 13),
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

  Widget _infoSection(Person person) {
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
          // User ID — copiable
          Row(
            children: [
              Text('ID: ',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: person.visibleUserId));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('User ID copied'), duration: Duration(seconds: 1)),
                    );
                  },
                  child: Text(
                    person.visibleUserId,
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
          // Created date
          Text(
            'Created: ${_formatDate(person.createdAt)}',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
          ),
          const SizedBox(height: 4),
          // Selfie count
          Text(
            'Selfies: ${person.selfieCount}',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _serverSelfieGrid(Person person) {
    return SizedBox(
      height: 100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _serverSelfieCount,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, index) {
          final url = _apiService.personSelfieUrl(person.visibleUserId, index);
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
                  width: 100,
                  height: 100,
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
                width: 100,
                height: 100,
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

  Widget _processingIndicator() {
    return const Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: KpegTheme.accent)),
          SizedBox(width: 8),
          Text('Detecting face...',
              style: TextStyle(color: KpegTheme.accent, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _addButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _addSelfie(ImageSource.camera),
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
            onPressed: () => _addSelfie(ImageSource.gallery),
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

  Widget _selfieGrid() {
    if (_selfies.isEmpty) {
      return Container(
        height: 120,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: KpegTheme.accent.withValues(alpha: 0.15)),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.face_rounded,
                  size: 36,
                  color: KpegTheme.accent.withValues(alpha: 0.3)),
              const SizedBox(height: 8),
              Text('Take selfies — face will be auto-cropped',
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
              // Show the CROPPED FACE, not the original photo
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  _selfies[index].faceCrop,
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
              Positioned(
                bottom: 4,
                left: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: KpegTheme.accent.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('#${index + 1}',
                      style: const TextStyle(
                          color: Colors.black,
                          fontSize: 10,
                          fontWeight: FontWeight.w700)),
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
