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

class NewOperationDialog extends ConsumerStatefulWidget {
  const NewOperationDialog({super.key});

  @override
  ConsumerState<NewOperationDialog> createState() => _NewOperationDialogState();
}

class _NewOperationDialogState extends ConsumerState<NewOperationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _categoryController = TextEditingController(text: 'Infrastructure');
  final _assigneesController = TextEditingController(text: 'Operations Admin');

  OperationPriority _priority = OperationPriority.high;
  String _nodeLocation = 'us-east-1a (Virginia)';
  bool _isSubmitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _categoryController.dispose();
    _assigneesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_titleController.text.trim().isEmpty) return;

    setState(() => _isSubmitting = true);

    final newOp = OperationModel(
      id: 'op_${DateTime.now().millisecondsSinceEpoch}',
      code: 'OP-${(1000 + (DateTime.now().millisecond % 8999))}',
      title: _titleController.text.trim(),
      category: _categoryController.text.trim(),
      assignees: _assigneesController.text.trim(),
      status: OperationStatus.active,
      priority: _priority,
      progress: 0.05,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      nodeLocation: _nodeLocation,
    );

    await ref.read(operationsViewModelProvider.notifier).addOperation(newOp);

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Initialize New Operation',
      subtitle: 'Deploy a managed operation process across node clusters',
      width: 580,
      content: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextField(
              label: 'Operation Title',
              hintText: 'e.g. Cluster Node Re-balancing & Index Sync',
              controller: _titleController,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    label: 'Category',
                    hintText: 'e.g. Infrastructure, Finance',
                    controller: _categoryController,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: AppTextField(
                    label: 'Assignees',
                    hintText: 'e.g. Sarah M., DevOps Team',
                    controller: _assigneesController,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                // Priority Dropdown
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Priority Level',
                        style: AppTypography.labelMd.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
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
                const SizedBox(width: 16),
                // Target Node Region Dropdown
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Target Node Cluster',
                        style: AppTypography.labelMd.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
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
                          child: DropdownButton<String>(
                            value: _nodeLocation,
                            isExpanded: true,
                            dropdownColor: AppColors.surfaceContainerHigh,
                            style: AppTypography.bodyMd,
                            onChanged: (val) {
                              if (val != null) setState(() => _nodeLocation = val);
                            },
                            items: const [
                              DropdownMenuItem(
                                value: 'us-east-1a (Virginia)',
                                child: Text('us-east-1a (Virginia)'),
                              ),
                              DropdownMenuItem(
                                value: 'eu-west-1 (Ireland)',
                                child: Text('eu-west-1 (Ireland)'),
                              ),
                              DropdownMenuItem(
                                value: 'ap-southeast-1 (Singapore)',
                                child: Text('ap-southeast-1 (Singapore)'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        AppSecondaryButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 12),
        AppPrimaryButton(
          label: 'Deploy Operation',
          icon: Icons.rocket_launch_outlined,
          isLoading: _isSubmitting,
          onPressed: _submit,
        ),
      ],
    );
  }
}
