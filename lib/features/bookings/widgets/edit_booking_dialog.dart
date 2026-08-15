import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../shared/models/booking_model.dart';

class EditBookingDialog extends ConsumerStatefulWidget {
  final BookingModel booking;

  const EditBookingDialog({
    super.key,
    required this.booking,
  });

  @override
  ConsumerState<EditBookingDialog> createState() => _EditBookingDialogState();
}

class _EditBookingDialogState extends ConsumerState<EditBookingDialog> {
  late final TextEditingController _customerController;
  late final TextEditingController _serviceController;
  late final TextEditingController _amountController;
  late BookingStatus _status;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _customerController = TextEditingController(text: widget.booking.customerName);
    _serviceController = TextEditingController(text: widget.booking.serviceType);
    _amountController = TextEditingController(text: widget.booking.amount.toStringAsFixed(2));
    _status = widget.booking.status;
  }

  @override
  void dispose() {
    _customerController.dispose();
    _serviceController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _save() {
    setState(() => _isSaving = true);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Ledger entry ${widget.booking.referenceNumber} updated.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Fix Ledger Entry ${widget.booking.referenceNumber}',
      subtitle: 'Adjust transaction amount, customer metadata, or settlement status',
      width: 580,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppTextField(
            label: 'Customer Name',
            controller: _customerController,
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Service Type',
            controller: _serviceController,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  label: 'Gross Amount (\$)',
                  controller: _amountController,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ledger Status', style: AppTypography.labelMd.copyWith(color: AppColors.textSecondary)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLow,
                        borderRadius: AppDecorations.radiusDefault,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<BookingStatus>(
                          value: _status,
                          isExpanded: true,
                          dropdownColor: AppColors.surfaceContainerHigh,
                          style: AppTypography.bodyMd,
                          onChanged: (val) {
                            if (val != null) setState(() => _status = val);
                          },
                          items: BookingStatus.values.map((s) {
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
          label: 'Save & Fix Ledger',
          icon: Icons.check_circle_outline,
          isLoading: _isSaving,
          onPressed: _save,
        ),
      ],
    );
  }
}
