import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/detected_face.dart';

class FaceOverlay extends StatelessWidget {
  final List<DetectedFace> faces;
  final int imageWidth;
  final int imageHeight;
  final Size displaySize;
  final void Function(int faceIndex)? onFaceTap;

  const FaceOverlay({
    super.key,
    required this.faces,
    required this.imageWidth,
    required this.imageHeight,
    required this.displaySize,
    this.onFaceTap,
  });

  @override
  Widget build(BuildContext context) {
    if (faces.isEmpty) return const SizedBox.shrink();

    return Stack(
      children: List.generate(faces.length, (index) {
        final face = faces[index];
        final bbox = face.normalizedBbox;

        // Convertir bbox normalizado a coordenadas del display
        final left = bbox[0] * displaySize.width;
        final top = bbox[1] * displaySize.height;
        final right = bbox[2] * displaySize.width;
        final bottom = bbox[3] * displaySize.height;

        return Positioned(
          left: left,
          top: top,
          width: right - left,
          height: bottom - top,
          child: GestureDetector(
            onTap: onFaceTap != null ? () => onFaceTap!(index) : null,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: face.isTagged ? KpegTheme.accent : Colors.white70,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: face.isTagged
                  ? Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: KpegTheme.accent.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          face.personName ?? '',
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                  : Align(
                      alignment: Alignment.topRight,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.7),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.person_add,
                            size: 12, color: Colors.black87),
                      ),
                    ),
            ),
          ),
        );
      }),
    );
  }
}
