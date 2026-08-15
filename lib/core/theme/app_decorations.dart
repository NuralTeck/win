import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Lumina Enterprise Glassmorphism & Surface Decorations
class AppDecorations {
  AppDecorations._();

  static final BorderRadius radiusSm = BorderRadius.circular(4);
  static final BorderRadius radiusDefault = BorderRadius.circular(8);
  static final BorderRadius radiusMd = BorderRadius.circular(12);
  static final BorderRadius radiusLg = BorderRadius.circular(16);
  static final BorderRadius radiusXl = BorderRadius.circular(24);
  static final BorderRadius radiusPill = BorderRadius.circular(999);

  static final Border sideBorder = Border.all(color: AppColors.border, width: 1);

  static final List<BoxShadow> ambientShadow = [
    const BoxShadow(
      color: Color.fromRGBO(0, 0, 0, 0.4),
      blurRadius: 32,
      offset: Offset(0, 8),
      spreadRadius: 0,
    ),
  ];

  static final List<BoxShadow> activeGlow = [
    const BoxShadow(
      color: Color.fromRGBO(139, 92, 246, 0.3),
      blurRadius: 15,
      offset: Offset(0, 0),
      spreadRadius: 2,
    ),
  ];

  static BoxDecoration glassCard({BorderRadius? borderRadius, Color? bgColor, Border? border}) {
    return BoxDecoration(
      color: bgColor ?? AppColors.glassCardBg,
      borderRadius: borderRadius ?? radiusLg,
      border: border ?? Border.all(color: AppColors.border, width: 1),
      boxShadow: ambientShadow,
    );
  }

  static BoxDecoration glassPanel({BorderRadius? borderRadius, Color? bgColor}) {
    return BoxDecoration(
      color: bgColor ?? AppColors.glassPanelBg,
      borderRadius: borderRadius ?? radiusLg,
      border: Border.all(color: AppColors.border, width: 1),
    );
  }

  static BoxDecoration surfaceContainerDecoration({BorderRadius? borderRadius, Color? color}) {
    return BoxDecoration(
      color: color ?? AppColors.surfaceContainer,
      borderRadius: borderRadius ?? radiusMd,
      border: Border.all(color: AppColors.border, width: 1),
    );
  }
}
