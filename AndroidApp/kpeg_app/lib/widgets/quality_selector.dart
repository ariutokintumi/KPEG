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
    ('fast', 'Fast', Icons.bolt_rounded),
    ('balanced', 'Balanced', Icons.tune_rounded),
    ('high', 'High quality', Icons.auto_awesome_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
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
                      color: isSelected ? KpegTheme.accent : Colors.white54,
                      size: 20),
                  const SizedBox(height: 4),
                  Text(
                    opt.$2,
                    style: TextStyle(
                      color: isSelected ? KpegTheme.accent : Colors.white54,
                      fontSize: 11,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
