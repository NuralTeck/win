import 'package:flutter/material.dart';
import '../../features/shared/models/series_price_model.dart';

/// Curated Palette of 20 modern, high-contrast colors for dark & light mode
const List<Color> kSeriesColorPalette = [
  Color(0xFF14B8A6), // Vibrant Teal
  Color(0xFF2DD4BF), // Mint Teal
  Color(0xFF06B6D4), // Cyan
  Color(0xFF38BDF8), // Sky Blue
  Color(0xFF3B82F6), // Blue
  Color(0xFF6366F1), // Indigo
  Color(0xFF8B5CF6), // Violet
  Color(0xFFA855F7), // Purple
  Color(0xFFD946EF), // Fuchsia
  Color(0xFFF43F5E), // Rose Pink
  Color(0xFFEF4444), // Crimson
  Color(0xFFF97316), // Orange
  Color(0xFFFB923C), // Light Orange
  Color(0xFFFBBF24), // Amber
  Color(0xFFEAB308), // Gold
  Color(0xFF84CC16), // Lime
  Color(0xFF22C55E), // Green
  Color(0xFF10B981), // Emerald
  Color(0xFFEC4899), // Hot Pink
  Color(0xFF94A3B8), // Slate
];

/// Curated distinct default color for every lottery series
Color getDefaultSeriesColor(String series) {
  if (series.toLowerCase().contains('undef') || series.toLowerCase().contains('inval')) {
    return Colors.redAccent;
  }
  final clean = series.replaceAll(RegExp(r'\D'), '');
  switch (clean) {
    case '1': return const Color(0xFF38BDF8); // Sky Blue
    case '2': return const Color(0xFF60A5FA); // Blue
    case '3': return const Color(0xFF818CF8); // Indigo
    case '5': return const Color(0xFF14B8A6); // Vibrant Teal
    case '6': return const Color(0xFFF43F5E); // Bright Rose / Pink
    case '10': return const Color(0xFF06B6D4); // Cyan
    case '12': return const Color(0xFF0284C7); // Royal Sky Blue
    case '14': return const Color(0xFF60A5FA); // Light Blue
    case '15': return const Color(0xFF34D399); // Emerald Mint
    case '16': return const Color(0xFF10B981); // Emerald
    case '18': return const Color(0xFFA855F7); // Purple
    case '20': return const Color(0xFFFBBF24); // Amber
    case '24': return const Color(0xFF4ADE80); // Light Green
    case '25': return const Color(0xFF22C55E); // Vivid Green
    case '30': return const Color(0xFF84CC16); // Lime
    case '36': return const Color(0xFFFB923C); // Orange
    case '40': return const Color(0xFF0D9488); // Deep Teal
    case '48': return const Color(0xFFEA580C); // Deep Orange
    case '50': return const Color(0xFFEAB308); // Gold / Yellow
    case '60': return const Color(0xFF9333EA); // Deep Purple
    case '70': return const Color(0xFF6366F1); // Indigo
    case '75': return const Color(0xFFD946EF); // Fuchsia
    case '80': return const Color(0xFFE11D48); // Magenta
    case '90': return const Color(0xFF2563EB); // Blue Ribbon
    case '100': return const Color(0xFFEF4444); // Crimson Red
    case '200': return const Color(0xFFB91C1C); // Ruby Red
    default:
      final n = int.tryParse(clean) ?? 0;
      return kSeriesColorPalette[n % kSeriesColorPalette.length];
  }
}

/// Global Reactive Registry for User-Customized Series Colors
class SeriesColorRegistry {
  static final Map<String, Color> _customColors = {};

  /// Sync from persistent series list
  static void updateFromList(List<UniversalSeriesPriceModel> list) {
    _customColors.clear();
    for (final item in list) {
      if (item.colorValue != null) {
        final clean = item.seriesName.replaceAll(RegExp(r'\D'), '');
        final c = Color(item.colorValue!);
        if (clean.isNotEmpty) {
          _customColors[clean] = c;
        }
        _customColors[item.seriesName.trim().toLowerCase()] = c;
      }
    }
  }

  /// Manually set custom color in memory (immediately available to UI & Syntax highlighter)
  static void setCustomColor(String seriesName, Color color) {
    final clean = seriesName.replaceAll(RegExp(r'\D'), '');
    if (clean.isNotEmpty) {
      _customColors[clean] = color;
    }
    _customColors[seriesName.trim().toLowerCase()] = color;
  }

  /// Get color for series: returns user custom color if set, or distinct default color
  static Color getColor(String series) {
    if (series.toLowerCase().contains('undef') || series.toLowerCase().contains('inval')) {
      return Colors.redAccent;
    }
    final clean = series.replaceAll(RegExp(r'\D'), '');
    if (clean.isNotEmpty && _customColors.containsKey(clean)) {
      return _customColors[clean]!;
    }
    final lower = series.trim().toLowerCase();
    if (_customColors.containsKey(lower)) {
      return _customColors[lower]!;
    }
    return getDefaultSeriesColor(series);
  }
}
