import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../shared/models/seller_model.dart';

class EditSellerDialog extends ConsumerStatefulWidget {
  final SellerModel seller;

  const EditSellerDialog({
    super.key,
    required this.seller,
  });

  @override
  ConsumerState<EditSellerDialog> createState() => _EditSellerDialogState();
}

class _EditSellerDialogState extends ConsumerState<EditSellerDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _categoryController;
  late final TextEditingController _revenueController;
  late SellerTier _tier;
  late SellerStatus _status;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.seller.name);
    _categoryController = TextEditingController(text: widget.seller.category);
    _revenueController = TextEditingController(text: widget.seller.monthlyRevenue.toStringAsFixed(2));
    _tier = widget.seller.tier;
    _status = widget.seller.status;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _revenueController.dispose();
    super.dispose();
  }

  void _save() {
    setState(() => _isSaving = true);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Partner ${widget.seller.code} profile updated successfully.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Fix & Edit Partner ${widget.seller.code}',
      subtitle: 'Update enterprise partner details, tier level, and active status',
      width: 580,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppTextField(
            label: 'Partner Name',
            controller: _nameController,
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Category',
            controller: _categoryController,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Partner Tier', style: AppTypography.labelMd.copyWith(color: AppColors.textSecondary)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLow,
                        borderRadius: AppDecorations.radiusDefault,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<SellerTier>(
                          value: _tier,
                          isExpanded: true,
                          dropdownColor: AppColors.surfaceContainerHigh,
                          style: AppTypography.bodyMd,
                          onChanged: (val) {
                            if (val != null) setState(() => _tier = val);
                          },
                          items: SellerTier.values.map((t) {
                            return DropdownMenuItem(
                              value: t,
                              child: Text(t.name.toUpperCase()),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Partner Status', style: AppTypography.labelMd.copyWith(color: AppColors.textSecondary)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLow,
                        borderRadius: AppDecorations.radiusDefault,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<SellerStatus>(
                          value: _status,
                          isExpanded: true,
                          dropdownColor: AppColors.surfaceContainerHigh,
                          style: AppTypography.bodyMd,
                          onChanged: (val) {
                            if (val != null) setState(() => _status = val);
                          },
                          items: SellerStatus.values.map((s) {
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
          label: 'Save Partner Changes',
          icon: Icons.check_circle_outline,
          isLoading: _isSaving,
          onPressed: _save,
        ),
      ],
    );
  }
}
