import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../shared/models/operation_model.dart';
import '../viewmodels/operations_viewmodel.dart';

class EditOperationDialog extends ConsumerStatefulWidget {
  final OperationModel operation;

  const EditOperationDialog({
    super.key,
    required this.operation,
  });

  @override
  ConsumerState<EditOperationDialog> createState() => _EditOperationDialogState();
}

class _EditOperationDialogState extends ConsumerState<EditOperationDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _categoryController;
  late final TextEditingController _assigneesController;
  late OperationStatus _status;
  late OperationPriority _priority;
  late double _progress;
  late String _nodeLocation;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.operation.title);
    _categoryController = TextEditingController(text: widget.operation.category);
    _assigneesController = TextEditingController(text: widget.operation.assignees);
    _status = widget.operation.status;
    _priority = widget.operation.priority;
    _progress = widget.operation.progress;
    _nodeLocation = widget.operation.nodeLocation;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _categoryController.dispose();
    _assigneesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);

    final updatedOp = widget.operation.copyWith(
      title: _titleController.text.trim(),
      category: _categoryController.text.trim(),
      assignees: _assigneesController.text.trim(),
      status: _status,
      priority: _priority,
      progress: _progress,
      nodeLocation: _nodeLocation,
      updatedAt: DateTime.now(),
    );

    // Update in viewmodel state
    await ref.read(operationsViewModelProvider.notifier).updateOperation(updatedOp);

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Operation ${widget.operation.code} updated successfully.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Fix & Edit Operation ${widget.operation.code}',
      subtitle: 'Modify parameters, re-assign nodes, or adjust execution progress',
      width: 600,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppTextField(
            label: 'Operation Title',
            controller: _titleController,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  label: 'Category',
                  controller: _categoryController,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: AppTextField(
                  label: 'Assignees',
                  controller: _assigneesController,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              // Status Dropdown
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Operational Status',
                      style: AppTypography.labelMd.copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLow,
                        borderRadius: AppDecorations.radiusDefault,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<OperationStatus>(
                          value: _status,
                          isExpanded: true,
                          dropdownColor: AppColors.surfaceContainerHigh,
                          style: AppTypography.bodyMd,
                          onChanged: (val) {
                            if (val != null) setState(() => _status = val);
                          },
                          items: OperationStatus.values.map((s) {
                            return DropdownMenuItem(
                              value: s,
                              child: Text(s.name.toUpperCase()),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Priority Dropdown
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Priority',
                      style: AppTypography.labelMd.copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLow,
                        borderRadius: AppDecorations.radiusDefault,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<OperationPriority>(
                          value: _priority,
                          isExpanded: true,
                          dropdownColor: AppColors.surfaceContainerHigh,
                          style: AppTypography.bodyMd,
                          onChanged: (val) {
                            if (val != null) setState(() => _priority = val);
                          },
                          items: OperationPriority.values.map((p) {
                            return DropdownMenuItem(
                              value: p,
                              child: Text(p.name.toUpperCase()),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Execution Progress Slider
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Execution Completion Progress',
                    style: AppTypography.labelMd.copyWith(color: AppColors.textSecondary),
                  ),
                  Text(
                    '${(_progress * 100).toInt()}%',
                    style: AppTypography.bodySm.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              Slider(
                value: _progress,
                min: 0.0,
                max: 1.0,
                activeColor: AppColors.primary,
                inactiveColor: AppColors.surfaceContainerHigh,
                onChanged: (val) => setState(() => _progress = val),
              ),
            ],
          ),
        ],
      ),
      actions: [
        AppSecondaryButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 12),
        AppPrimaryButton(
          label: 'Save & Fix Operation',
          icon: Icons.check_circle_outline,
          isLoading: _isSaving,
          onPressed: _save,
        ),
      ],
    );
  }
}
