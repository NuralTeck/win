import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../theme/app_decorations.dart';

class AppTableColumn {
  final String label;
  final double? width;
  final AlignmentGeometry alignment;

  const AppTableColumn({
    required this.label,
    this.width,
    this.alignment = Alignment.centerLeft,
  });
}

class AppDataTable extends StatelessWidget {
  final List<AppTableColumn> columns;
  final List<List<Widget>> rows;
  final bool isLoading;

  const AppDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Container(
        height: 240,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
        ),
      );
    }

    if (rows.isEmpty) {
      return Container(
        height: 200,
        alignment: Alignment.center,
        child: Text(
          'No records found matching criteria.',
          style: AppTypography.bodyMd.copyWith(color: AppColors.textSecondary),
        ),
      );
    }

    return Container(
      decoration: AppDecorations.glassCard(
        borderRadius: AppDecorations.radiusLg,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Table Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: const BoxDecoration(
              color: AppColors.surfaceContainerHigh,
              border: Border(
                bottom: BorderSide(color: AppColors.border, width: 1),
              ),
            ),
            child: Row(
              children: columns.map((col) {
                Widget child = Text(
                  col.label.toUpperCase(),
                  style: AppTypography.labelSm.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                );

                if (col.width != null) {
                  return SizedBox(
                    width: col.width,
                    child: Align(alignment: col.alignment, child: child),
                  );
                }
                return Expanded(
                  child: Align(alignment: col.alignment, child: child),
                );
              }).toList(),
            ),
          ),

          // Table Rows
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: rows.length,
            separatorBuilder: (context, index) => const Divider(
              height: 1,
              color: AppColors.border,
            ),
            itemBuilder: (context, index) {
              return _DataTableRowTile(
                cells: rows[index],
                columns: columns,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DataTableRowTile extends StatefulWidget {
  final List<Widget> cells;
  final List<AppTableColumn> columns;

  const _DataTableRowTile({
    required this.cells,
    required this.columns,
  });

  @override
  State<_DataTableRowTile> createState() => _DataTableRowTileState();
}

class _DataTableRowTileState extends State<_DataTableRowTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        color: _isHovered ? AppColors.hover : Colors.transparent,
        child: Row(
          children: List.generate(widget.cells.length, (idx) {
            final col = widget.columns[idx];
            final cell = widget.cells[idx];

            if (col.width != null) {
              return SizedBox(
                width: col.width,
                child: Align(alignment: col.alignment, child: cell),
              );
            }
            return Expanded(
              child: Align(alignment: col.alignment, child: cell),
            );
          }),
        ),
      ),
    );
  }
}
