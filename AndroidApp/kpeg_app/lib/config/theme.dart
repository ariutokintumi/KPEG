import 'package:flutter/material.dart';

class KpegTheme {
  static const Color accent = Color(0xFF00C896);
  static const Color bgDark1 = Color(0xFF0A0A0A);
  static const Color bgDark2 = Color(0xFF0D1F1A);
  static const Color bgDark3 = Color(0xFF0A1628);

  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [bgDark1, bgDark2, bgDark3],
  );

  static ThemeData get darkTheme => ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      );

  static Color statusColor(StatusType type) {
    switch (type) {
      case StatusType.success:
        return Colors.green;
      case StatusType.error:
        return Colors.redAccent;
      case StatusType.info:
        return accent;
    }
  }
}

enum StatusType { success, error, info }
