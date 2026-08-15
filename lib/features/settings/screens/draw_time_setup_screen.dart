import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/widgets/glass_card.dart';
import '../viewmodels/draw_time_viewmodel.dart';

class DrawTimeSetupScreen extends ConsumerStatefulWidget {
  const DrawTimeSetupScreen({super.key});

  @override
  ConsumerState<DrawTimeSetupScreen> createState() => _DrawTimeSetupScreenState();
}

class _DrawTimeSetupScreenState extends ConsumerState<DrawTimeSetupScreen> {
  final TextEditingController _labelCtrl = TextEditingController();
  final TextEditingController _codeCtrl = TextEditingController();
  final TextEditingController _shiftCtrl = TextEditingController(text: 'Morning');

  final FocusNode _labelFocusNode = FocusNode();
  final FocusNode _codeFocusNode = FocusNode();
  final FocusNode _shiftFocusNode = FocusNode();

  @override
  void dispose() {
    _labelCtrl.dispose();
    _codeCtrl.dispose();
    _shiftCtrl.dispose();
    _labelFocusNode.dispose();
    _codeFocusNode.dispose();
    _shiftFocusNode.dispose();
    super.dispose();
  }

  void _addDrawTime() {
    final label = _labelCtrl.text.trim();
    final code = _codeCtrl.text.trim();
    final shift = _shiftCtrl.text.trim();

    if (label.isEmpty) {
      _showSnackbar('Please enter Draw Time Label (e.g. Dear 1 PM)!', AppColors.warning);
      _labelFocusNode.requestFocus();
      return;
    }

    if (code.isEmpty) {
      _showSnackbar('Please enter Draw Code (e.g. 1PM)!', AppColors.warning);
      _codeFocusNode.requestFocus();
      return;
    }

    ref.read(drawTimeViewModelProvider.notifier).addDrawTime(
          timeLabel: label,
          timeCode: code,
          shiftName: shift.isNotEmpty ? shift : 'Morning',
        );

    _labelCtrl.clear();
    _codeCtrl.clear();
    _labelFocusNode.requestFocus();

    _showSnackbar('Draw Time "$label" added successfully!', AppColors.success);
  }

  void _showSnackbar(String msg, Color bg) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: bg),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(drawTimeViewModelProvider);
    final notifier = ref.read(drawTimeViewModelProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [


          // Add New Draw Time Card
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.access_time_filled, color: AppColors.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'ADD NEW DRAW TIME / SHIFT',
                      style: AppTypography.titleMd.copyWith(fontWeight: FontWeight.bold, letterSpacing: 1.0),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Time Label
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Draw Time Label *', style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary)),
                          const SizedBox(height: 4),
                          SizedBox(
                            height: 42,
                            child: TextField(
                              controller: _labelCtrl,
                              focusNode: _labelFocusNode,
                              autofocus: true,
                              textInputAction: TextInputAction.next,
                              style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: 'e.g. Dear 1 PM',
                                filled: true,
                                fillColor: AppColors.surfaceContainerLow,
                                border: OutlineInputBorder(borderRadius: AppDecorations.radiusDefault, borderSide: const BorderSide(color: AppColors.border)),
                              ),
                              onSubmitted: (_) => _codeFocusNode.requestFocus(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),

                    // Draw Code
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Code *', style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary)),
                          const SizedBox(height: 4),
                          SizedBox(
                            height: 42,
                            child: TextField(
                              controller: _codeCtrl,
                              focusNode: _codeFocusNode,
                              textInputAction: TextInputAction.next,
                              textCapitalization: TextCapitalization.characters,
                              style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.bold, color: AppColors.primary),
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: 'e.g. 1PM',
                                filled: true,
                                fillColor: AppColors.surfaceContainerLow,
                                border: OutlineInputBorder(borderRadius: AppDecorations.radiusDefault, borderSide: const BorderSide(color: AppColors.border)),
                              ),
                              onSubmitted: (_) => _shiftFocusNode.requestFocus(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),

                    // Shift Category
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Shift Name', style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary)),
                          const SizedBox(height: 4),
                          SizedBox(
                            height: 42,
                            child: TextField(
                              controller: _shiftCtrl,
                              focusNode: _shiftFocusNode,
                              textInputAction: TextInputAction.done,
                              style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: 'e.g. Morning',
                                filled: true,
                                fillColor: AppColors.surfaceContainerLow,
                                border: OutlineInputBorder(borderRadius: AppDecorations.radiusDefault, borderSide: const BorderSide(color: AppColors.border)),
                              ),
                              onSubmitted: (_) => _addDrawTime(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),

                    // Save Button
                    SizedBox(
                      height: 42,
                      child: ElevatedButton.icon(
                        onPressed: _addDrawTime,
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('SAVE DRAW TIME', style: TextStyle(fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryContainer,
                          foregroundColor: AppColors.onPrimaryContainer,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          shape: RoundedRectangleBorder(borderRadius: AppDecorations.radiusDefault),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Master Draw Times Table
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'DRAW TIMES & SHIFTS LIST (${state.times.length})',
                      style: AppTypography.titleLg.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerHigh,
                        borderRadius: AppDecorations.radiusPill,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        'Universal Master List',
                        style: AppTypography.labelSm.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                Table(
                  columnWidths: const {
                    0: FlexColumnWidth(2.5),
                    1: FlexColumnWidth(1.5),
                    2: FlexColumnWidth(1.8),
                    3: FlexColumnWidth(1.5),
                    4: FlexColumnWidth(1.0),
                  },
                  border: const TableBorder(
                    horizontalInside: BorderSide(color: AppColors.border, width: 0.8),
                  ),
                  children: [
                    TableRow(
                      decoration: const BoxDecoration(color: AppColors.surfaceContainerHigh),
                      children: [
                        _cell('Draw Time Label', isHeader: true),
                        _cell('Code', isHeader: true),
                        _cell('Shift Category', isHeader: true),
                        _cell('Status', isHeader: true),
                        _cell('Delete', isHeader: true, alignment: Alignment.center),
                      ],
                    ),
                    ...state.times.asMap().entries.map((entry) {
                      final index = entry.key;
                      final item = entry.value;

                      return TableRow(
                        decoration: BoxDecoration(
                          color: index % 2 == 0 ? AppColors.surfaceContainerLow : AppColors.surfaceContainer,
                        ),
                        children: [
                          _cell(item.timeLabel, isBold: true, color: AppColors.textPrimary),
                          _cell(item.timeCode, isBold: true, color: AppColors.primary),
                          _cell(item.shiftName, color: AppColors.textSecondary),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                            child: InkWell(
                              onTap: () => notifier.toggleStatus(item.id),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: item.isActive ? AppColors.success.withAlpha(35) : AppColors.error.withAlpha(35),
                                  borderRadius: AppDecorations.radiusSm,
                                  border: Border.all(color: item.isActive ? AppColors.success : AppColors.error),
                                ),
                                child: Text(
                                  item.isActive ? 'ACTIVE' : 'INACTIVE',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: item.isActive ? AppColors.success : AppColors.error,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Center(
                            child: IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.error),
                              tooltip: 'Delete Draw Time',
                              onPressed: () => notifier.deleteDrawTime(item.id),
                            ),
                          ),
                        ],
                      );
                    }),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
    }


  Widget _cell(String text, {bool isHeader = false, bool isBold = false, Color? color, Alignment alignment = Alignment.centerLeft}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Align(
        alignment: alignment,
        child: Text(
          text,
          style: isHeader
              ? AppTypography.labelSm.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.bold)
              : AppTypography.bodySm.copyWith(
                  fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                  color: color ?? AppColors.textPrimary,
                ),
        ),
      ),
    );
  }
}
