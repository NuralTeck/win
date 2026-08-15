import 'package:flutter/material.dart';

/// OpsCore Pro / Lumina Enterprise Color Palette
class AppColors {
  AppColors._();

  // Backgrounds & Surface Hierarchy
  static const Color bgPrimary = Color(0xFF0F1020);
  static const Color bgSecondary = Color(0xFF17192B);
  static const Color sidebar = Color(0xFF141729);
  
  static const Color surface = Color(0xFF0E1227);
  static const Color surfaceDim = Color(0xFF0E1227);
  static const Color surfaceBright = Color(0xFF34384F);
  
  static const Color surfaceContainerLowest = Color(0xFF080D22);
  static const Color surfaceContainerLow = Color(0xFF161A30);
  static const Color surfaceContainer = Color(0xFF1A1E34);
  static const Color surfaceContainerHigh = Color(0xFF25293F);
  static const Color surfaceContainerHighest = Color(0xFF2F334A);
  static const Color surfaceVariant = Color(0xFF2F334A);

  // Accents & Brand Colors
  static const Color primary = Color(0xFFD0BCFF);
  static const Color primaryContainer = Color(0xFFA078FF);
  static const Color onPrimary = Color(0xFF3C0091);
  static const Color onPrimaryContainer = Color(0xFF340080);
  static const Color inversePrimary = Color(0xFF6D3BD7);
  static const Color primaryFixed = Color(0xFFE9DDFF);
  static const Color primaryFixedDim = Color(0xFFD0BCFF);

  static const Color secondary = Color(0xFFDDB7FF);
  static const Color secondaryContainer = Color(0xFF6F00BE);
  static const Color onSecondary = Color(0xFF490080);
  static const Color onSecondaryContainer = Color(0xFFD6A9FF);

  static const Color tertiary = Color(0xFFFFB869);
  static const Color tertiaryContainer = Color(0xFFCA801E);
  static const Color onTertiary = Color(0xFF482900);
  static const Color onTertiaryContainer = Color(0xFF3F2300);

  // Status & Feedback
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color errorContainer = Color(0xFF93000A);
  static const Color onError = Color(0xFF690005);
  static const Color info = Color(0xFF3B82F6);

  // Typography & Neutrals
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFAEB4D1);
  static const Color onSurface = Color(0xFFDEE1FF);
  static const Color onSurfaceVariant = Color(0xFFCBC3D7);

  // Interactive & Glass Effects
  static const Color hover = Color(0xFF2A2E4A);
  static const Color border = Color(0x0FFFFFFF); // rgba(255, 255, 255, 0.06)
  static const Color outline = Color(0xFF958EA0);
  static const Color outlineVariant = Color(0xFF494454);

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryContainer, primary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const Color glassPanelBg = Color(0xB31E2238); // rgba(30, 34, 56, 0.7)
  static const Color glassCardBg = Color(0x991E2238);  // rgba(30, 34, 56, 0.6)
}
