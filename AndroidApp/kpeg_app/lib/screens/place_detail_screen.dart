import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'dart:math';
import '../config/theme.dart';
import '../models/place.dart';
import '../providers/places_provider.dart';
import '../widgets/kpeg_gradient_background.dart';

class PlaceDetailScreen extends StatefulWidget {
  const PlaceDetailScreen({super.key});

  @override
  State<PlaceDetailScreen> createState() => _PlaceDetailScreenState();
}

class _PlaceDetailScreenState extends State<PlaceDetailScreen> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final List<({File photo, PlacePhotoMeta meta})> _photos = [];
  bool _saving = false;
  String? _error;
  double? _lat;
  double? _lng;
  double? _lastCompass;
  double? _lastTilt;

  static const int _minPhotos = 2;
  static const int _maxPhotos = 5;

  @override
  void initState() {
    super.initState();
    _getLocation();
    // Listen to sensors for per-photo metadata
    FlutterCompass.events?.listen((e) => _lastCompass = e.heading);
    accelerometerEventStream().listen((e) {
      _lastTilt = atan2(e.y, sqrt(e.x * e.x + e.z * e.z)) * (180 / pi);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _getLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 5)),
      );
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
      });
    } catch (_) {}
  }

  Future<void> _addPhoto(ImageSource source) async {
    if (_photos.length >= _maxPhotos) return;
    final picker = ImagePicker();
    final xfile = await picker.pickImage(
        source: source, imageQuality: 85, maxWidth: 1200);
    if (xfile == null) return;

    // Capture sensor data at moment of photo
    final meta = PlacePhotoMeta(
      lat: _lat,
      lng: _lng,
      compassHeading: _lastCompass,
      cameraTilt: _lastTilt,
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );

    setState(() => _photos.add((photo: File(xfile.path), meta: meta)));
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
      await context.read<PlacesProvider>().addPlace(
            name: name,
            description: _descriptionController.text.trim().isNotEmpty
                ? _descriptionController.text.trim()
                : null,
            lat: _lat,
            lng: _lng,
            photos: _photos.map((p) => p.photo).toList(),
            photosMeta: _photos.map((p) => p.meta).toList(),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: Colors.white),
                    ),
                    const Text('New place',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700)),
                    const Spacer(),
                    if (_lat != null)
                      Icon(Icons.gps_fixed,
                          color: KpegTheme.accent.withValues(alpha: 0.6),
                          size: 18),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _field(
                          _nameController, 'Place name *', Icons.place_rounded),
                      const SizedBox(height: 12),
                      _field(_descriptionController, 'Description (optional)',
                          Icons.notes_rounded),

                      const SizedBox(height: 20),

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
                      const SizedBox(height: 4),
                      Text(
                          'Each photo captures location & camera angle automatically',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.3),
                              fontSize: 12)),

                      const SizedBox(height: 12),
                      _photoGrid(),
                      const SizedBox(height: 12),

                      if (_photos.length < _maxPhotos)
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    _addPhoto(ImageSource.camera),
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
                                    _addPhoto(ImageSource.gallery),
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
                    label: Text(_saving ? 'Registering...' : 'Save place',
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

  Widget _field(
      TextEditingController controller, String hint, IconData icon) {
    return TextField(
      controller: controller,
      onChanged: (_) => setState(() {}),
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
            color: Colors.white.withValues(alpha: 0.3), fontSize: 14),
        prefixIcon: Icon(icon, color: KpegTheme.accent, size: 20),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(
                color: KpegTheme.accent.withValues(alpha: 0.2))),
        focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: KpegTheme.accent)),
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
          border: Border.all(
              color: KpegTheme.accent.withValues(alpha: 0.15)),
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
                child: Image.file(_photos[index].photo,
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
                    child: const Icon(Icons.close,
                        size: 16, color: Colors.white),
                  ),
                ),
              ),
              // Compass indicator
              if (_photos[index].meta.compassHeading != null)
                Positioned(
                  bottom: 4,
                  left: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${_photos[index].meta.compassHeading!.round()}°',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w600),
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
