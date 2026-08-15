import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/widgets/glass_card.dart';
import '../../shared/models/series_price_model.dart';
import '../viewmodels/series_price_viewmodel.dart';

class PriceSetupScreen extends ConsumerStatefulWidget {
  const PriceSetupScreen({super.key});

  @override
  ConsumerState<PriceSetupScreen> createState() => _PriceSetupScreenState();
}

class _PriceSetupScreenState extends ConsumerState<PriceSetupScreen> {
  // Input Controllers & Focus Nodes for Fast Keyboard Entry
  final TextEditingController _seriesNameCtrl = TextEditingController();
  final TextEditingController _priceCtrl = TextEditingController();

  final FocusNode _seriesFocusNode = FocusNode();
  final FocusNode _priceFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _seriesNameCtrl.dispose();
    _priceCtrl.dispose();
    _seriesFocusNode.dispose();
    _priceFocusNode.dispose();
    super.dispose();
  }

  String _formatPrice(double price) {
    if (price % 1 == 0) {
      return price.toInt().toString();
    }
    return price.toStringAsFixed(2);
  }

  void _addSeries() {
    final sName = _seriesNameCtrl.text.trim();
    final price = double.tryParse(_priceCtrl.text.trim()) ?? 100.0;

    if (sName.isEmpty) {
      _showSnackbar('Please enter a Series Name (e.g. 12, 24, A)!', AppColors.warning);
      _seriesFocusNode.requestFocus();
      return;
    }

    // Check for Duplicate Series Name (Case-Insensitive)
    final currentList = ref.read(seriesPriceViewModelProvider).seriesList;
    final isDuplicate = currentList.any((item) => item.seriesName.trim().toUpperCase() == sName.toUpperCase());

    if (isDuplicate) {
      _showSnackbar('Duplicate Series! "$sName" already exists. Edit its price in the table below.', AppColors.error);
      _seriesFocusNode.requestFocus();
      _seriesNameCtrl.selection = TextSelection(baseOffset: 0, extentOffset: _seriesNameCtrl.text.length);
      return;
    }

    final newItem = UniversalSeriesPriceModel(
      id: 'sp_${DateTime.now().millisecondsSinceEpoch}',
      seriesName: sName,
      ticketPrice: price,
      isActive: true,
      createdAt: DateTime.now(),
    );

    ref.read(seriesPriceViewModelProvider.notifier).addSeriesPrice(newItem);

    // Reset controllers & return focus back to Series field for immediate next entry
    _seriesNameCtrl.clear();
    _priceCtrl.text = '100';
    _seriesFocusNode.requestFocus();

    _showSnackbar('Series $sName with Price ₹${_formatPrice(price)} saved successfully!', AppColors.success);
  }

  void _editPrice(UniversalSeriesPriceModel item) {
    final ctrl = TextEditingController(text: _formatPrice(item.ticketPrice));

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: AppDecorations.radiusLg),
        title: Text('Edit Price — Series ${item.seriesName}', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 18),
          decoration: const InputDecoration(
            labelText: 'New Ticket Price (₹)',
            labelStyle: TextStyle(color: AppColors.textSecondary),
          ),
          onSubmitted: (val) {
            final newP = double.tryParse(val) ?? item.ticketPrice;
            final updated = item.copyWith(ticketPrice: newP);
            ref.read(seriesPriceViewModelProvider.notifier).updateSeriesPrice(updated);
            if (Navigator.canPop(dialogCtx)) Navigator.pop(dialogCtx);
            _showSnackbar('Price for Series ${item.seriesName} updated to ₹${_formatPrice(newP)}', AppColors.success);
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (Navigator.canPop(dialogCtx)) Navigator.pop(dialogCtx);
            },
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryContainer),
            onPressed: () {
              final newP = double.tryParse(ctrl.text) ?? item.ticketPrice;
              final updated = item.copyWith(ticketPrice: newP);
              ref.read(seriesPriceViewModelProvider.notifier).updateSeriesPrice(updated);
              if (Navigator.canPop(dialogCtx)) Navigator.pop(dialogCtx);
              _showSnackbar('Price for Series ${item.seriesName} updated to ₹${_formatPrice(newP)}', AppColors.success);
            },
            child: const Text('Save Price', style: TextStyle(color: AppColors.onPrimaryContainer, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showSnackbar(String msg, Color bg) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: bg,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(seriesPriceViewModelProvider);
    final notifier = ref.read(seriesPriceViewModelProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [


          // Series & Price Creation Form with Keyboard Navigation
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.keyboard, color: AppColors.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'ADD TICKET SERIES & PRICE (Press Enter to move / save)',
                      style: AppTypography.labelSm.copyWith(fontWeight: FontWeight.bold, color: AppColors.primary, letterSpacing: 1.0),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Series Name Input (Focus #1 -> Enter moves to Price)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Series Name *', style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary)),
                          const SizedBox(height: 6),
                          SizedBox(
                            height: 42,
                            child: TextField(
                              controller: _seriesNameCtrl,
                              focusNode: _seriesFocusNode,
                              autofocus: true,
                              textInputAction: TextInputAction.next,
                              style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.bold, color: AppColors.primary),
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: 'e.g. 12, 24, 36, 60, A',
                                hintStyle: TextStyle(color: AppColors.textSecondary.withAlpha(100)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                filled: true,
                                fillColor: AppColors.surfaceContainerLow,
                                border: OutlineInputBorder(borderRadius: AppDecorations.radiusDefault, borderSide: BorderSide(color: AppColors.border)),
                              ),
                              onSubmitted: (_) => _priceFocusNode.requestFocus(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),

                    // Ticket Price Input (Focus #2 -> Enter saves & returns focus to Series Name)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Ticket Price (₹) *', style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary)),
                          const SizedBox(height: 6),
                          SizedBox(
                            height: 42,
                            child: TextField(
                              controller: _priceCtrl,
                              focusNode: _priceFocusNode,
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.done,
                              style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.bold, color: AppColors.tertiary),
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: '100',
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                filled: true,
                                fillColor: AppColors.surfaceContainerLow,
                                border: OutlineInputBorder(borderRadius: AppDecorations.radiusDefault, borderSide: BorderSide(color: AppColors.border)),
                              ),
                              onSubmitted: (_) => _addSeries(),
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
                        onPressed: _addSeries,
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('SAVE SERIES & PRICE', style: TextStyle(fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryContainer,
                          foregroundColor: AppColors.onPrimaryContainer,
                          padding: const EdgeInsets.symmetric(horizontal: 24),
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

          // Master Series & Price Table List
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'UNIVERSAL SERIES & PRICE LIST (${state.seriesList.length})',
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
                        'Universal & Permanent Master',
                        style: AppTypography.labelSm.copyWith(color: AppColors.tertiary, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLow,
                    borderRadius: AppDecorations.radiusDefault,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: state.seriesList.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(32.0),
                          child: Center(
                            child: Text(
                              'No series added yet. Type Series Name -> press Enter -> type Price -> press Enter to Save!',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          ),
                        )
                      : Table(
                          columnWidths: const {
                            0: FlexColumnWidth(2.0), // Series Name
                            1: FlexColumnWidth(2.5), // Ticket Price
                            2: FlexColumnWidth(1.5), // Status
                            3: FlexColumnWidth(1.2), // Actions
                          },
                          border: const TableBorder(horizontalInside: BorderSide(color: AppColors.border, width: 0.8)),
                          children: [
                            TableRow(
                              decoration: const BoxDecoration(color: AppColors.surfaceContainerHigh),
                              children: [
                                _cell('SERIES NAME', isHeader: true),
                                _cell('TICKET PRICE (₹)', isHeader: true),
                                _cell('STATUS', isHeader: true),
                                _cell('ACTIONS', isHeader: true, alignment: Alignment.center),
                              ],
                            ),
                            ...state.seriesList.asMap().entries.map((entry) {
                              final index = entry.key;
                              final item = entry.value;

                              return TableRow(
                                decoration: BoxDecoration(
                                  color: index % 2 == 0 ? AppColors.surfaceContainerLow : AppColors.surfaceContainer,
                                ),
                                children: [
                                  _cell(item.seriesName, isBold: true, color: AppColors.primary),
                                  Row(
                                    children: [
                                      Text(
                                        '₹${_formatPrice(item.ticketPrice)}',
                                        style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.tertiary),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        icon: const Icon(Icons.edit, size: 16, color: AppColors.primary),
                                        tooltip: 'Edit Price',
                                        onPressed: () => _editPrice(item),
                                      ),
                                    ],
                                  ),
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
                                      tooltip: 'Delete Series',
                                      onPressed: () => notifier.deleteSeriesPrice(item.id),
                                    ),
                                  ),
                                ],
                              );
                            }),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
      );
    }


  Widget _cell(String text, {bool isHeader = false, bool isBold = false, Color? color, Alignment alignment = Alignment.centerLeft}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      alignment: alignment,
      child: Text(
        text,
        style: isHeader
            ? AppTypography.labelSm.copyWith(fontWeight: FontWeight.bold, color: AppColors.textSecondary)
            : AppTypography.bodySm.copyWith(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: color ?? AppColors.textPrimary),
      ),
    );
  }
}
