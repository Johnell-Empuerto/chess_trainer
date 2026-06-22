import 'package:flutter/material.dart';

/// Theme configuration for the Chess Trainer app.
class AppTheme {
  AppTheme._();

  static const Color primary = Colors.blue;
  static const Color onPrimary = Colors.white;
  static const Color surface = Color(0xFF1E1E1E);
  static const Color onSurface = Colors.white;
  static const Color card = Color(0xFF2D2D2D);
  static const Color divider = Color(0xFF404040);
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xFFB0B0B0);
  static const Color textMuted = Color(0xFF808080);
  static const Color accent = Color(0x246C8EE3);

  static final ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: primary,
      onPrimary: onPrimary,
      surface: surface,
      onSurface: onSurface,
      error: Colors.red,
      onError: Colors.white,
      background: surface,
      onBackground: onSurface,
    ),
  );
}