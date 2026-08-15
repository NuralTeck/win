import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_decorations.dart';

class GlassCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;
  final Color? backgroundColor;
  final Border? border;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius,
    this.backgroundColor,
    this.border,
    this.onTap,
  });

  @override
  State<GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<GlassCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final effectiveBorder = widget.border ??
        Border.all(
          color: _isHovered
              ? AppColors.primary.withAlpha(76)
              : AppColors.border,
          width: 1,
        );

    Widget content = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: widget.padding ?? const EdgeInsets.all(20),
      margin: widget.margin,
      decoration: AppDecorations.glassCard(
        borderRadius: widget.borderRadius ?? AppDecorations.radiusLg,
        bgColor: _isHovered
            ? (widget.backgroundColor ?? AppColors.glassCardBg).withAlpha(220)
            : widget.backgroundColor ?? AppColors.glassCardBg,
        border: effectiveBorder,
      ),
      child: widget.child,
    );

    if (widget.onTap != null) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: content,
        ),
      );
    }

    return content;
  }
}
