import 'package:flutter/material.dart';
import '../config/theme.dart';

class QualitySelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const QualitySelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  static const _options = [
    (
      'fast',
      'Fast',
      Icons.bolt_rounded,
      '~2s',
      'FLUX Schnell\nNo library refs',
    ),
    (
      'balanced',
      'Balanced',
      Icons.tune_rounded,
      '~10s',
      'FLUX Dev + Kontext\nBitmap + faces + places',
    ),
    (
      'high',
      'High Quality',
      Icons.auto_awesome_rounded,
      '~20s',
      'FLUX Pro + Kontext\n+ Clarity upscaler 2x',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: _options.map((opt) {
            final isSelected = selected == opt.$1;
            return Expanded(
              child: GestureDetector(
                onTap: () => onChanged(opt.$1),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? KpegTheme.accent.withValues(alpha: 0.2)
                        : Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? KpegTheme.accent
                          : Colors.white.withValues(alpha: 0.1),
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(opt.$3,
                          color:
                              isSelected ? KpegTheme.accent : Colors.white54,
                          size: 20),
                      const SizedBox(height: 4),
                      Text(
                        opt.$2,
                        style: TextStyle(
                          color:
                              isSelected ? KpegTheme.accent : Colors.white54,
                          fontSize: 11,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        opt.$4,
                        style: TextStyle(
                          color: isSelected
                              ? KpegTheme.accent.withValues(alpha: 0.7)
                              : Colors.white.withValues(alpha: 0.3),
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        // Descripción del tier seleccionado
        _tierDescription(),
      ],
    );
  }

  Widget _tierDescription() {
    final opt = _options.firstWhere((o) => o.$1 == selected);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        opt.$5,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.4),
          fontSize: 10,
          height: 1.4,
        ),
      ),
    );
  }
}
