import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../config/app_config.dart';
import '../config/theme.dart';
import '../providers/people_provider.dart';
import '../services/face_detection_service.dart';
import '../services/face_recognition_service.dart';
import '../widgets/kpeg_gradient_background.dart';

class PersonDetailScreen extends StatefulWidget {
  const PersonDetailScreen({super.key});

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
  static const int _maxSelfies = 5;

  final _faceDetection = FaceDetectionService();
  final _faceCrop = FaceCropService();

  @override
  void dispose() {
    _nameController.dispose();
    _faceDetection.dispose();
    super.dispose();
  }

  Future<void> _addSelfie(ImageSource source) async {
    if (_selfies.length >= _maxSelfies || _processing) return;

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
      final cropBytes = await _faceCrop.cropFaceJpeg(
        file,
        left: face.boundingBox.left,
        top: face.boundingBox.top,
        right: face.boundingBox.right,
        bottom: face.boundingBox.bottom,
        imageWidth: width,
        imageHeight: height,
      );

      setState(() {
        _selfies.add((original: file, faceCrop: cropBytes));
        _processing = false;
      });
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

                      // Counter
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
                      Text('Face is auto-cropped from each photo',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.3),
                              fontSize: 12)),

                      const SizedBox(height: 16),

                      // Face crops grid
                      _selfieGrid(),

                      const SizedBox(height: 16),

                      // Processing indicator
                      if (_processing)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: KpegTheme.accent)),
                              SizedBox(width: 8),
                              Text('Detecting face...',
                                  style: TextStyle(
                                      color: KpegTheme.accent, fontSize: 13)),
                            ],
                          ),
                        ),

                      // Add buttons
                      if (_selfies.length < _maxSelfies && !_processing)
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    _addSelfie(ImageSource.camera),
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
                                onPressed: () =>
                                    _addSelfie(ImageSource.gallery),
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
}
