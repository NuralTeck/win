import 'package:flutter/material.dart';

class KpiMetricModel {
  final String title;
  final String value;
  final double changePercentage; // e.g. +14.2%
  final bool isPositive;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final List<double>? sparklineData;

  const KpiMetricModel({
    required this.title,
    required this.value,
    required this.changePercentage,
    required this.isPositive,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    this.sparklineData,
  });
}
