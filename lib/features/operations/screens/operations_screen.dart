import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/widgets/app_data_table.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/utils/formatters.dart';
import '../viewmodels/operations_viewmodel.dart';
import '../widgets/new_operation_dialog.dart';
import '../widgets/edit_operation_dialog.dart';
import '../../shared/models/operation_model.dart';

class OperationsScreen extends ConsumerWidget {
  const OperationsScreen({super.key});

  void _openNewOperationDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withAlpha(153),
      builder: (context) => const NewOperationDialog(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(operationsViewModelProvider);
    final notifier = ref.read(operationsViewModelProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Operations Management',
                      style: AppTypography.headlineLg.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Monitor, orchestrate, and audit high-concurrency system processes',
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              AppPrimaryButton(
                label: 'New Operation',
                icon: Icons.add,
                onPressed: () => _openNewOperationDialog(context),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Filters & Search Bar
          Row(
            children: [
              // Search Input
              SizedBox(
                width: 320,
                child: AppSearchField(
                  hintText: 'Filter by title, code, or category...',
                  onChanged: notifier.setSearchQuery,
                ),
              ),
              const SizedBox(width: 16),

              // Filter Chips
              _FilterChipTile(
                label: 'All Statuses',
                isSelected: state.selectedStatus == null,
                onTap: () => notifier.setStatusFilter(null),
              ),
              const SizedBox(width: 8),
              _FilterChipTile(
                label: 'Active',
                isSelected: state.selectedStatus == OperationStatus.active,
                onTap: () => notifier.setStatusFilter(OperationStatus.active),
              ),
              const SizedBox(width: 8),
              _FilterChipTile(
                label: 'Pending',
                isSelected: state.selectedStatus == OperationStatus.pending,
                onTap: () => notifier.setStatusFilter(OperationStatus.pending),
              ),
              const SizedBox(width: 8),
              _FilterChipTile(
                label: 'Completed',
                isSelected: state.selectedStatus == OperationStatus.completed,
                onTap: () => notifier.setStatusFilter(OperationStatus.completed),
              ),
              const Spacer(),
              Text(
                'Showing ${state.filteredOperations.length} of ${state.operations.length} operations',
                style: AppTypography.labelSm.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Operations Data Table
          AppDataTable(
            isLoading: state.isLoading,
            columns: const [
              AppTableColumn(label: 'CODE', width: 100),
              AppTableColumn(label: 'OPERATION DETAILS'),
              AppTableColumn(label: 'PRIORITY', width: 110),
              AppTableColumn(label: 'STATUS', width: 120),
              AppTableColumn(label: 'PROGRESS', width: 160),
              AppTableColumn(label: 'UPDATED', width: 150),
              AppTableColumn(label: 'ACTIONS', width: 90, alignment: Alignment.centerRight),
            ],
            rows: state.filteredOperations.map((op) {
              return [
                Text(
                  op.code,
                  style: AppTypography.bodySm.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      op.title,
                      style: AppTypography.bodySm.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${op.category} • Assignees: ${op.assignees} • Node: ${op.nodeLocation}',
                      style: AppTypography.labelSm.copyWith(
                        color: AppColors.textSecondary.withAlpha(150),
                      ),
                    ),
                  ],
                ),
                StatusBadge.fromStatus(op.priority.name),
                StatusBadge.fromStatus(op.status.name),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: AppDecorations.radiusPill,
                        child: LinearProgressIndicator(
                          value: op.progress,
                          minHeight: 6,
                          backgroundColor: AppColors.surfaceContainerHigh,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            op.progress == 1.0
                                ? AppColors.success
                                : AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(op.progress * 100).toInt()}%',
                      style: AppTypography.labelSm.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                Text(
                  Formatters.formatDateTime(op.updatedAt),
                  style: AppTypography.labelSm.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.tune, size: 18, color: AppColors.primary),
                      tooltip: 'Fix & Edit Operation',
                      onPressed: () {
                        showDialog(
                          context: context,
                          barrierColor: Colors.black.withAlpha(153),
                          builder: (context) => EditOperationDialog(operation: op),
                        );
                      },
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, size: 18, color: AppColors.textSecondary),
                      color: AppColors.surfaceContainerHigh,
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'edit',
                          child: Text('Edit / Fix Operation', style: AppTypography.bodySm),
                          onTap: () {
                            Future.microtask(() {
                              if (context.mounted) {
                                showDialog(
                                  context: context,
                                  barrierColor: Colors.black.withAlpha(153),
                                  builder: (context) => EditOperationDialog(operation: op),
                                );
                              }
                            });
                          },
                        ),
                        PopupMenuItem(
                          value: 'pause',
                          child: Text('Pause Execution', style: AppTypography.bodySm),
                        ),
                        PopupMenuItem(
                          value: 'logs',
                          child: Text('View Live Logs', style: AppTypography.bodySm),
                        ),
                        PopupMenuItem(
                          value: 'cancel',
                          child: Text('Abort Process', style: AppTypography.bodySm.copyWith(color: AppColors.error)),
                        ),
                      ],
                    ),
                  ],
                ),
              ];
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _FilterChipTile extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChipTile({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppDecorations.radiusPill,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryContainer : AppColors.surfaceContainerLow,
          borderRadius: AppDecorations.radiusPill,
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: AppTypography.labelSm.copyWith(
            color: isSelected ? AppColors.onPrimaryContainer : AppColors.textSecondary,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
