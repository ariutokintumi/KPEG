import 'package:flutter/material.dart';
import '../config/theme.dart';

class MetadataForm extends StatelessWidget {
  final bool isOutdoor;
  final ValueChanged<bool> onOutdoorChanged;
  final String sceneHint;
  final ValueChanged<String> onSceneHintChanged;
  final String tagsText;
  final ValueChanged<String> onTagsChanged;

  const MetadataForm({
    super.key,
    required this.isOutdoor,
    required this.onOutdoorChanged,
    required this.sceneHint,
    required this.onSceneHintChanged,
    required this.tagsText,
    required this.onTagsChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: KpegTheme.accent.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Indoor/Outdoor toggle
          Row(
            children: [
              Icon(isOutdoor ? Icons.wb_sunny_rounded : Icons.home_rounded,
                  color: KpegTheme.accent, size: 20),
              const SizedBox(width: 8),
              Text(
                isOutdoor ? 'Exterior' : 'Interior',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const Spacer(),
              Switch(
                value: isOutdoor,
                onChanged: onOutdoorChanged,
                activeThumbColor: KpegTheme.accent,
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Scene hint
          TextField(
            onChanged: onSceneHintChanged,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Describe la escena (ej: "almuerzo en la playa")',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 13),
              prefixIcon: const Icon(Icons.notes_rounded, color: KpegTheme.accent, size: 18),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: InputBorder.none,
            ),
          ),

          // Tags
          TextField(
            onChanged: onTagsChanged,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Tags separados por coma (ej: "vacaciones, amigos")',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 13),
              prefixIcon: const Icon(Icons.label_rounded, color: KpegTheme.accent, size: 18),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: InputBorder.none,
            ),
          ),
        ],
      ),
    );
  }
}
