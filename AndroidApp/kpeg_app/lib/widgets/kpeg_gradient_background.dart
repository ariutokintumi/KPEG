import 'package:flutter/material.dart';
import '../config/theme.dart';

class KpegGradientBackground extends StatelessWidget {
  final Widget child;

  const KpegGradientBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: KpegTheme.backgroundGradient),
      child: child,
    );
  }
}
