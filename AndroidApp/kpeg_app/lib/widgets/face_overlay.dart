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

        final left = bbox[0] * displaySize.width;
        final top = bbox[1] * displaySize.height;
        final right = bbox[2] * displaySize.width;
        final bottom = bbox[3] * displaySize.height;

        final color = _tierColor(face.tier);

        return Positioned(
          left: left,
          top: top,
          width: right - left,
          height: bottom - top,
          child: GestureDetector(
            onTap: onFaceTap != null ? () => onFaceTap!(index) : null,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: color, width: 2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Stack(
                children: [
                  // Name label at bottom
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _labelText(face),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  // Tap indicator for unmatched/uncertain faces
                  if (face.tier == ConfidenceTier.unknown ||
                      face.tier == ConfidenceTier.medium)
                    Align(
                      alignment: Alignment.topRight,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.8),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          face.tier == ConfidenceTier.medium
                              ? Icons.help_outline
                              : Icons.person_add,
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Color _tierColor(ConfidenceTier tier) {
    switch (tier) {
      case ConfidenceTier.high:
        return KpegTheme.accent; // Green — confident auto-match
      case ConfidenceTier.medium:
        return Colors.amber; // Yellow — suggested match
      case ConfidenceTier.low:
        return Colors.redAccent; // Red — low confidence
      case ConfidenceTier.unknown:
        return Colors.redAccent; // Red — no match
    }
  }

  String _labelText(DetectedFace face) {
    if (!face.isTagged) return 'Unknown';
    final name = face.personName ?? 'Unknown';
    // Mostrar hasta 5 caracteres del nombre
    final short = name.length > 5 ? name.substring(0, 5) : name;
    if (face.tier == ConfidenceTier.medium) return '$short?';
    return short;
  }
}
