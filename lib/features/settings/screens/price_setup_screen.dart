import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/widgets/glass_card.dart';
import '../../shared/models/series_price_model.dart';
import '../viewmodels/series_price_viewmodel.dart';
import '../../../core/services/series_color_registry.dart';
import '../../sellers/viewmodels/seller_customer_viewmodel.dart';
import '../../../core/database/database_service.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(sellerCustomerViewModelProvider.notifier).loadSellers();
    });
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
      _showSnackbar(
        'Please enter a Series Name (e.g. 12, 24, A)!',
        AppColors.warning,
      );
      _seriesFocusNode.requestFocus();
      return;
    }

    // Check for Duplicate Series Name (Case-Insensitive)
    final currentList = ref.read(seriesPriceViewModelProvider).seriesList;
    final isDuplicate = currentList.any(
      (item) => item.seriesName.trim().toUpperCase() == sName.toUpperCase(),
    );

    if (isDuplicate) {
      _showSnackbar(
        'Duplicate Series! "$sName" already exists. Edit its price in the table below.',
        AppColors.error,
      );
      _seriesFocusNode.requestFocus();
      _seriesNameCtrl.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _seriesNameCtrl.text.length,
      );
      return;
    }

    final defaultColor = SeriesColorRegistry.getColor(sName);
    final newItem = UniversalSeriesPriceModel(
      id: 'sp_${DateTime.now().millisecondsSinceEpoch}',
      seriesName: sName,
      ticketPrice: price,
      colorValue: defaultColor.toARGB32(),
      isActive: true,
      createdAt: DateTime.now(),
    );

    ref.read(seriesPriceViewModelProvider.notifier).addSeriesPrice(newItem);
    SeriesColorRegistry.setCustomColor(sName, defaultColor);

    // Reset controllers & return focus back to Series field for immediate next entry
    _seriesNameCtrl.clear();
    _priceCtrl.text = '100';
    _seriesFocusNode.requestFocus();

    _showSnackbar(
      'Series $sName with Price ₹${_formatPrice(price)} saved successfully!',
      AppColors.success,
    );

    // If Series 100 was just added, ask to sync existing entries
    final is100Series =
        sName == '100' || sName.replaceAll(RegExp(r'\D'), '') == '100';
    if (is100Series) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          _promptRecalculateExisting(
            seriesName: sName,
            newPrice: price,
            is100Series: true,
          );
        }
      });
    }
  }

  void _editPrice(UniversalSeriesPriceModel item) {
    final ctrl = TextEditingController(text: _formatPrice(item.ticketPrice));
    Color selectedColor = item.colorValue != null
        ? Color(item.colorValue!)
        : SeriesColorRegistry.getColor(item.seriesName);

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: AppDecorations.radiusLg),
          title: Row(
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: selectedColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Edit Series ${item.seriesName} (Price & Color)',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'New Ticket Price (₹)',
                    labelStyle: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text(
                      'Series Color:',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: selectedColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '#${selectedColor.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase().substring(2)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: selectedColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: kSeriesColorPalette.map((c) {
                    final isThis = c.toARGB32() == selectedColor.toARGB32();
                    return InkWell(
                      onTap: () => setDialogState(() => selectedColor = c),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isThis ? Colors.white : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: isThis
                            ? const Icon(
                                Icons.check,
                                size: 14,
                                color: Colors.white,
                              )
                            : null,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (Navigator.canPop(dialogCtx)) Navigator.pop(dialogCtx);
              },
              child: const Text(
                'Cancel',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryContainer,
              ),
              onPressed: () {
                final newP = double.tryParse(ctrl.text) ?? item.ticketPrice;
                final bool priceChanged = (newP != item.ticketPrice);
                final updated = item.copyWith(
                  ticketPrice: newP,
                  colorValue: selectedColor.toARGB32(),
                );
                ref
                    .read(seriesPriceViewModelProvider.notifier)
                    .updateSeriesPrice(updated);
                SeriesColorRegistry.setCustomColor(
                  item.seriesName,
                  selectedColor,
                );
                if (Navigator.canPop(dialogCtx)) Navigator.pop(dialogCtx);
                _showSnackbar(
                  'Series ${item.seriesName} updated to ₹${_formatPrice(newP)}',
                  AppColors.success,
                );

                // ⚡ Prompt to recalculate existing entries if price was changed
                if (priceChanged) {
                  final is100Series =
                      item.seriesName.trim() == '100' ||
                      item.seriesName.replaceAll(RegExp(r'\D'), '') == '100';
                  Future.delayed(const Duration(milliseconds: 300), () {
                    if (mounted) {
                      _promptRecalculateExisting(
                        seriesName: item.seriesName,
                        newPrice: newP,
                        is100Series: is100Series,
                      );
                    }
                  });
                }
              },
              child: const Text(
                'Save Changes',
                style: TextStyle(
                  color: AppColors.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _promptRecalculateExisting({
    required String seriesName,
    required double newPrice,
    required bool is100Series,
  }) async {
    final state = ref.read(seriesPriceViewModelProvider);
    final perUnit = is100Series ? (newPrice / 100.0) : state.perUnitRate;

    final shouldRecalc = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: AppDecorations.radiusLg),
        title: Row(
          children: [
            const Icon(Icons.sync, color: AppColors.primary, size: 24),
            const SizedBox(width: 8),
            Text(
              is100Series
                  ? 'Series 100 Base Price Updated!'
                  : 'Series $seriesName Price Updated!',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              is100Series
                  ? 'Aapne Series 100 ka base price badal kar ₹${_formatPrice(newPrice)} (₹${perUnit.toStringAsFixed(2)}/unit) kar diya hai.\n\nKya aap existing entries (Vouchers, Unsold aur Bookings) ko bhi naye dynamic multiple rates ke hisaab se update karna chahte hain?'
                  : 'Aapne Series $seriesName ka price ₹${_formatPrice(newPrice)} kiya hai. Kya aap already entered Vouchers aur Sales ko bhi update karna chahte hain?',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primaryContainer.withAlpha(50),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.primary.withAlpha(60)),
              ),
              child: Text(
                '⚡ Multiplier Example: 12 Ser = ₹${(12 * perUnit).toStringAsFixed(2)} | 24 Ser = ₹${(24 * perUnit).toStringAsFixed(2)} | 50 Ser = ₹${(50 * perUnit).toStringAsFixed(2)} | 100 Ser = ₹${(100 * perUnit).toStringAsFixed(2)}',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Skip (Only New Entries)',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            icon: const Icon(Icons.flash_on, color: Colors.black, size: 16),
            label: const Text(
              'Recalculate Existing Entries',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (shouldRecalc == true && mounted) {
      _openBulkRecalculateDialog(custom100Price: is100Series ? newPrice : null);
    }
  }

  Future<void> _openBulkRecalculateDialog({double? custom100Price}) async {
    final now = DateTime.now();

    // Date Mode & Values
    String selectedDateMode = 'single'; // 'single', 'range', 'all'
    DateTime individualDate = now;
    DateTimeRange? customRange;

    // Multi-Customer Selection State
    bool isAllPartiesSelected = true;
    final Set<String> selectedParties = {};
    String partySearchQuery = '';
    final TextEditingController partySearchCtrl = TextEditingController();

    String selectedShift = 'All Shifts';
    bool updateVouchers = true;
    bool updateUnsold = true;
    bool updateSales = true;
    bool isProcessing = false;

    // Active Parties State
    bool isLoadingParties = true;
    bool hasInitialized = false;
    bool showAllRegisteredParties = false;
    List<String> activePartiesOnDate = [];

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          final state = ref.read(seriesPriceViewModelProvider);
          final active100 = custom100Price ?? state.series100Price;
          final perUnit = active100 / 100.0;
          final sellers = ref.read(sellerCustomerViewModelProvider).sellers;

          // Helper to fetch parties who actually have entries on selected date/range
          Future<void> refreshActiveParties() async {
            setDialogState(() => isLoadingParties = true);
            String? targetDate;
            String? startDateStr;
            String? endDateStr;

            if (selectedDateMode == 'single') {
              targetDate = DateFormat('yyyy-MM-dd').format(individualDate);
            } else if (selectedDateMode == 'range' && customRange != null) {
              startDateStr = DateFormat('yyyy-MM-dd').format(customRange!.start);
              endDateStr = DateFormat('yyyy-MM-dd').format(customRange!.end);
            }

            final list = await DatabaseService.instance.getActivePartiesForSelection(
              date: targetDate,
              startDate: startDateStr,
              endDate: endDateStr,
              drawShift: selectedShift == 'All Shifts' ? null : selectedShift,
            );

            if (dialogCtx.mounted) {
              setDialogState(() {
                activePartiesOnDate = list;
                isLoadingParties = false;
              });
            }
          }

          // Initial Load on opening dialog
          if (!hasInitialized) {
            hasInitialized = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              refreshActiveParties();
            });
          }

          // Build party dropdown items
          final displayedParties = <String>['All Parties'];
          if (showAllRegisteredParties || activePartiesOnDate.isEmpty) {
            for (final s in sellers) {
              final n = s.name.trim();
              if (n.isNotEmpty && !displayedParties.contains(n)) displayedParties.add(n);
            }
          } else {
            for (final p in activePartiesOnDate) {
              if (!displayedParties.contains(p)) displayedParties.add(p);
            }
          }

          final singleDateDisplay = DateFormat('dd MMM yyyy').format(individualDate);

          return AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: AppDecorations.radiusLg,
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withAlpha(40),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.flash_on,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    '⚡ Dynamic Rate Recalculation',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'Active Base Rate (Series 100): ',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                '₹${_formatPrice(active100)}',
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '(₹${perUnit.toStringAsFixed(2)} / unit)',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'All series dynamically calculated: Series Rate = Series Number × (Series 100 Price / 100)',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Target Date Scope
                    const Text(
                      'Select Date Mode:',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        ChoiceChip(
                          label: const Text('Individual Date'),
                          selected: selectedDateMode == 'single',
                          selectedColor: AppColors.primaryContainer,
                          onSelected: (val) {
                            if (val) {
                              setDialogState(() => selectedDateMode = 'single');
                              refreshActiveParties();
                            }
                          },
                        ),
                        const SizedBox(width: 6),
                        ChoiceChip(
                          label: const Text('Date Range'),
                          selected: selectedDateMode == 'range',
                          selectedColor: AppColors.primaryContainer,
                          onSelected: (val) {
                            if (val) {
                              setDialogState(() => selectedDateMode = 'range');
                              refreshActiveParties();
                            }
                          },
                        ),
                        const SizedBox(width: 6),
                        ChoiceChip(
                          label: const Text('All History'),
                          selected: selectedDateMode == 'all',
                          selectedColor: AppColors.primaryContainer,
                          onSelected: (val) {
                            if (val) {
                              setDialogState(() => selectedDateMode = 'all');
                              refreshActiveParties();
                            }
                          },
                        ),
                      ],
                    ),

                    // 1. Single / Individual Date Controls
                    if (selectedDateMode == 'single') ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          ActionChip(
                            label: const Text('Today'),
                            avatar: const Icon(Icons.today, size: 14),
                            backgroundColor: DateUtils.isSameDay(individualDate, now)
                                ? AppColors.primary.withAlpha(60)
                                : null,
                            onPressed: () {
                              setDialogState(() => individualDate = now);
                              refreshActiveParties();
                            },
                          ),
                          const SizedBox(width: 6),
                          ActionChip(
                            label: const Text('Yesterday'),
                            avatar: const Icon(Icons.history, size: 14),
                            backgroundColor: DateUtils.isSameDay(
                                    individualDate, now.subtract(const Duration(days: 1)))
                                ? AppColors.primary.withAlpha(60)
                                : null,
                            onPressed: () {
                              setDialogState(() =>
                                  individualDate = now.subtract(const Duration(days: 1)));
                              refreshActiveParties();
                            },
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.calendar_month,
                                  size: 16, color: AppColors.primary),
                              label: Text(
                                singleDateDisplay,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                  fontSize: 13,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppColors.primary),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 10),
                              ),
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: dialogCtx,
                                  initialDate: individualDate,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2035),
                                  builder: (c, child) {
                                    return Theme(
                                      data: ThemeData.dark().copyWith(
                                        colorScheme: const ColorScheme.dark(
                                          primary: AppColors.primary,
                                          onPrimary: Colors.black,
                                          surface: Color(0xFF1E293B),
                                          onSurface: Colors.white,
                                        ),
                                        dialogTheme: const DialogThemeData(
                                          backgroundColor: Color(0xFF0F172A),
                                        ),
                                      ),
                                      child: child!,
                                    );
                                  },
                                );
                                if (picked != null) {
                                  setDialogState(() => individualDate = picked);
                                  refreshActiveParties();
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ],

                    // 2. Date Range Controls
                    if (selectedDateMode == 'range') ...[
                      const SizedBox(height: 10),
                      InkWell(
                        onTap: () async {
                          final picked = await showDateRangePicker(
                            context: dialogCtx,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2035),
                            initialDateRange: customRange ??
                                DateTimeRange(
                                  start: now.subtract(const Duration(days: 7)),
                                  end: now,
                                ),
                            builder: (c, child) {
                              return Theme(
                                data: ThemeData.dark().copyWith(
                                  colorScheme: const ColorScheme.dark(
                                    primary: AppColors.primary,
                                    onPrimary: Colors.black,
                                    surface: Color(0xFF1E293B),
                                    onSurface: Colors.white,
                                  ),
                                  dialogTheme: const DialogThemeData(
                                    backgroundColor: Color(0xFF0F172A),
                                  ),
                                ),
                                child: child!,
                              );
                            },
                          );
                          if (picked != null) {
                            setDialogState(() => customRange = picked);
                            refreshActiveParties();
                          }
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.primary.withAlpha(120)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.date_range, color: AppColors.primary, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  customRange != null
                                      ? '${DateFormat('dd MMM yyyy').format(customRange!.start)}  →  ${DateFormat('dd MMM yyyy').format(customRange!.end)}'
                                      : 'Click to select Date Range (e.g. Last 7 Days)',
                                  style: TextStyle(
                                    color: customRange != null
                                        ? AppColors.textPrimary
                                        : AppColors.textSecondary,
                                    fontSize: 12,
                                    fontWeight: customRange != null
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                              const Icon(Icons.edit_calendar, color: AppColors.primary, size: 16),
                            ],
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 14),

                    // Draw Shift Filter
                    const Text(
                      'Select Draw Shift:',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: selectedShift,
                      dropdownColor: AppColors.surface,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        filled: true,
                        fillColor: AppColors.surfaceContainerLow,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'All Shifts',
                          child: Text('All Shifts (1 PM, 6 PM, 8 PM)'),
                        ),
                        DropdownMenuItem(
                          value: 'Dear 1 PM',
                          child: Text('Dear 1 PM (Morning)'),
                        ),
                        DropdownMenuItem(
                          value: 'Dear 6 PM',
                          child: Text('Dear 6 PM (Day)'),
                        ),
                        DropdownMenuItem(
                          value: 'Dear 8 PM',
                          child: Text('Dear 8 PM (Night)'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => selectedShift = val);
                          refreshActiveParties();
                        }
                      },
                    ),

                    const SizedBox(height: 14),

                    // Multi-Customer / Parties Selection Section
                    Row(
                      children: [
                        const Text(
                          'Select Parties / Customers:',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        if (isLoadingParties)
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          )
                        else
                          Text(
                            isAllPartiesSelected
                                ? '⭐ All Parties Selected'
                                : '${selectedParties.length} Selected',
                            style: TextStyle(
                              color: isAllPartiesSelected ? AppColors.primary : AppColors.success,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        ChoiceChip(
                          label: const Text('⭐ All Parties'),
                          selected: isAllPartiesSelected,
                          selectedColor: AppColors.primaryContainer,
                          onSelected: (val) {
                            if (val) {
                              setDialogState(() {
                                isAllPartiesSelected = true;
                                selectedParties.clear();
                              });
                            }
                          },
                        ),
                        const SizedBox(width: 6),
                        ChoiceChip(
                          label: Text(
                            selectedParties.isEmpty
                                ? 'Select Multiple Customers'
                                : 'Selected (${selectedParties.length} Customers)',
                          ),
                          selected: !isAllPartiesSelected,
                          selectedColor: AppColors.primaryContainer,
                          onSelected: (val) {
                            if (val) {
                              setDialogState(() {
                                isAllPartiesSelected = false;
                                if (selectedParties.isEmpty && activePartiesOnDate.isNotEmpty) {
                                  selectedParties.addAll(activePartiesOnDate);
                                }
                              });
                            }
                          },
                        ),
                      ],
                    ),
                    if (!isAllPartiesSelected) ...[
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.primary.withAlpha(120)),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: SizedBox(
                                      height: 32,
                                      child: TextField(
                                        controller: partySearchCtrl,
                                        style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                                        decoration: InputDecoration(
                                          hintText: 'Search customer name...',
                                          hintStyle: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                          prefixIcon: const Icon(Icons.search, size: 14, color: AppColors.textSecondary),
                                          isDense: true,
                                          contentPadding: const EdgeInsets.symmetric(vertical: 6),
                                          filled: true,
                                          fillColor: AppColors.surface,
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                                        ),
                                        onChanged: (val) => setDialogState(() => partySearchQuery = val.toLowerCase()),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  TextButton(
                                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
                                    onPressed: () {
                                      setDialogState(() {
                                        selectedParties.addAll(displayedParties.where((p) => p != 'All Parties'));
                                      });
                                    },
                                    child: const Text('Select All', style: TextStyle(fontSize: 11, color: AppColors.primary)),
                                  ),
                                  TextButton(
                                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
                                    onPressed: () {
                                      setDialogState(() {
                                        selectedParties.clear();
                                      });
                                    },
                                    child: const Text('Clear', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1, color: AppColors.border),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 140),
                              child: ListView(
                                shrinkWrap: true,
                                padding: EdgeInsets.zero,
                                children: displayedParties.where((p) {
                                  if (p == 'All Parties') return false;
                                  if (partySearchQuery.isNotEmpty && !p.toLowerCase().contains(partySearchQuery)) return false;
                                  return true;
                                }).map((name) {
                                  final isChecked = selectedParties.contains(name);
                                  final hasEntry = activePartiesOnDate.contains(name);
                                  return CheckboxListTile(
                                    dense: true,
                                    visualDensity: VisualDensity.compact,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                                    value: isChecked,
                                    title: Row(
                                      children: [
                                        Icon(
                                          hasEntry ? Icons.check_circle : Icons.person_outline,
                                          size: 14,
                                          color: hasEntry ? AppColors.success : Colors.grey,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            name,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: hasEntry ? FontWeight.bold : FontWeight.normal,
                                              color: hasEntry ? AppColors.textPrimary : AppColors.textSecondary,
                                            ),
                                          ),
                                        ),
                                        if (hasEntry)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: AppColors.success.withAlpha(30),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: const Text(
                                              'Active',
                                              style: TextStyle(fontSize: 9, color: AppColors.success, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                      ],
                                    ),
                                    onChanged: (val) {
                                      setDialogState(() {
                                        if (val == true) {
                                          selectedParties.add(name);
                                        } else {
                                          selectedParties.remove(name);
                                        }
                                      });
                                    },
                                  );
                                }).toList(),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (activePartiesOnDate.isNotEmpty && !showAllRegisteredParties) ...[
                        const SizedBox(height: 4),
                        InkWell(
                          onTap: () {
                            setDialogState(() => showAllRegisteredParties = true);
                          },
                          child: const Text(
                            'Showing only parties with entries. Tap to show all registered parties.',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 11,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ],

                    const SizedBox(height: 14),

                    // Apply To
                    const Text(
                      'Apply To:',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Vouchers (Stock Issue)',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                        ),
                      ),
                      value: updateVouchers,
                      onChanged: (val) =>
                          setDialogState(() => updateVouchers = val ?? true),
                    ),
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Unsold Tickets (Returns)',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                        ),
                      ),
                      value: updateUnsold,
                      onChanged: (val) =>
                          setDialogState(() => updateUnsold = val ?? true),
                    ),
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Bookings & Ticket Sales',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                        ),
                      ),
                      value: updateSales,
                      onChanged: (val) =>
                          setDialogState(() => updateSales = val ?? true),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isProcessing ? null : () => Navigator.pop(dialogCtx),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                icon: isProcessing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : const Icon(Icons.sync, color: Colors.black, size: 16),
                label: Text(
                  isProcessing ? 'Recalculating...' : 'Apply Dynamic Rates Now',
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onPressed: isProcessing
                    ? null
                    : () async {
                        setDialogState(() => isProcessing = true);
                        try {
                          String? targetDate;
                          String? startDateStr;
                          String? endDateStr;

                          if (selectedDateMode == 'single') {
                            targetDate = DateFormat('yyyy-MM-dd').format(individualDate);
                          } else if (selectedDateMode == 'range' && customRange != null) {
                            startDateStr = DateFormat('yyyy-MM-dd').format(customRange!.start);
                            endDateStr = DateFormat('yyyy-MM-dd').format(customRange!.end);
                          }

                          final targetParties = (!isAllPartiesSelected && selectedParties.isNotEmpty)
                              ? selectedParties.toList()
                              : null;

                          final res = await ref
                              .read(seriesPriceViewModelProvider.notifier)
                              .recalculateRatesAcrossSystem(
                                date: targetDate,
                                startDate: startDateStr,
                                endDate: endDateStr,
                                partyNames: targetParties,
                                drawShift: selectedShift == 'All Shifts'
                                    ? null
                                    : selectedShift,
                                customSeries100Price: active100,
                                updateVouchers: updateVouchers,
                                updateUnsold: updateUnsold,
                                updateSales: updateSales,
                              );
                          if (dialogCtx.mounted &&
                              Navigator.canPop(dialogCtx)) {
                            Navigator.pop(dialogCtx);
                          }
                          if (mounted) {
                            _showSnackbar(
                              '✅ Recalculated! Vouchers: ${res['vouchers']}, Unsold: ${res['unsold']}, Sales: ${res['sales']} updated.',
                              AppColors.success,
                            );
                          }
                        } catch (e) {
                          if (dialogCtx.mounted) {
                            setDialogState(() => isProcessing = false);
                          }
                          if (mounted) {
                            _showSnackbar(
                              'Recalculation error: $e',
                              AppColors.error,
                            );
                          }
                        }
                      },
              ),
            ],
          );
        },
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
                  const Icon(
                    Icons.keyboard,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'ADD TICKET SERIES & PRICE (Press Enter to move / save)',
                    style: AppTypography.labelSm.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer.withAlpha(50),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: AppColors.primary.withAlpha(60),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.auto_graph,
                          color: AppColors.primary,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '100 Ser Base: ₹${_formatPrice(state.series100Price)} (₹${state.perUnitRate.toStringAsFixed(2)}/unit)',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.sync, size: 15, color: Colors.black),
                    label: const Text(
                      '⚡ Recalculate Existing Entries',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11.5,
                      ),
                    ),
                    onPressed: () => _openBulkRecalculateDialog(),
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
                        Text(
                          'Series Name *',
                          style: AppTypography.labelSm.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 42,
                          child: TextField(
                            controller: _seriesNameCtrl,
                            focusNode: _seriesFocusNode,
                            autofocus: true,
                            textInputAction: TextInputAction.next,
                            style: AppTypography.bodySm.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: 'e.g. 12, 24, 36, 60, A',
                              hintStyle: TextStyle(
                                color: AppColors.textSecondary.withAlpha(100),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              filled: true,
                              fillColor: AppColors.surfaceContainerLow,
                              border: OutlineInputBorder(
                                borderRadius: AppDecorations.radiusDefault,
                                borderSide: BorderSide(color: AppColors.border),
                              ),
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
                        Text(
                          'Ticket Price (₹) *',
                          style: AppTypography.labelSm.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 42,
                          child: TextField(
                            controller: _priceCtrl,
                            focusNode: _priceFocusNode,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.done,
                            style: AppTypography.bodySm.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppColors.tertiary,
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: '100',
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              filled: true,
                              fillColor: AppColors.surfaceContainerLow,
                              border: OutlineInputBorder(
                                borderRadius: AppDecorations.radiusDefault,
                                borderSide: BorderSide(color: AppColors.border),
                              ),
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
                      label: const Text(
                        'SAVE SERIES & PRICE',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryContainer,
                        foregroundColor: AppColors.onPrimaryContainer,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        shape: RoundedRectangleBorder(
                          borderRadius: AppDecorations.radiusDefault,
                        ),
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
                    style: AppTypography.titleLg.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerHigh,
                      borderRadius: AppDecorations.radiusPill,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      'Universal & Permanent Master',
                      style: AppTypography.labelSm.copyWith(
                        color: AppColors.tertiary,
                        fontWeight: FontWeight.bold,
                      ),
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
                          0: FlexColumnWidth(1.8), // Series Name
                          1: FlexColumnWidth(2.0), // Series Color
                          2: FlexColumnWidth(2.0), // Ticket Price
                          3: FlexColumnWidth(1.4), // Status
                          4: FlexColumnWidth(1.2), // Actions
                        },
                        border: const TableBorder(
                          horizontalInside: BorderSide(
                            color: AppColors.border,
                            width: 0.8,
                          ),
                        ),
                        children: [
                          TableRow(
                            decoration: const BoxDecoration(
                              color: AppColors.surfaceContainerHigh,
                            ),
                            children: [
                              _cell('SERIES NAME', isHeader: true),
                              _cell('SERIES COLOR', isHeader: true),
                              _cell('TICKET PRICE (₹)', isHeader: true),
                              _cell('STATUS', isHeader: true),
                              _cell(
                                'ACTIONS',
                                isHeader: true,
                                alignment: Alignment.center,
                              ),
                            ],
                          ),
                          ...state.seriesList.asMap().entries.map((entry) {
                            final index = entry.key;
                            final item = entry.value;
                            final seriesColor = item.colorValue != null
                                ? Color(item.colorValue!)
                                : SeriesColorRegistry.getColor(item.seriesName);

                            return TableRow(
                              decoration: BoxDecoration(
                                color: index % 2 == 0
                                    ? AppColors.surfaceContainerLow
                                    : AppColors.surfaceContainer,
                              ),
                              children: [
                                _cell(
                                  item.seriesName,
                                  isBold: true,
                                  color: seriesColor,
                                ),
                                InkWell(
                                  onTap: () => _editPrice(item),
                                  borderRadius: AppDecorations.radiusSm,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 10,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 14,
                                          height: 14,
                                          decoration: BoxDecoration(
                                            color: seriesColor,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.white38,
                                              width: 1.2,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: seriesColor.withAlpha(
                                                  80,
                                                ),
                                                blurRadius: 4,
                                                spreadRadius: 1,
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '#${seriesColor.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase().substring(2)}',
                                          style: AppTypography.bodySm.copyWith(
                                            color: seriesColor,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Icon(
                                          Icons.palette_outlined,
                                          size: 14,
                                          color: seriesColor.withAlpha(180),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                Row(
                                  children: [
                                    Text(
                                      '₹${_formatPrice(item.ticketPrice)}',
                                      style: AppTypography.bodySm.copyWith(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: AppColors.tertiary,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.edit,
                                        size: 16,
                                        color: AppColors.primary,
                                      ),
                                      tooltip: 'Edit Price & Color',
                                      onPressed: () => _editPrice(item),
                                    ),
                                  ],
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                    horizontal: 8,
                                  ),
                                  child: InkWell(
                                    onTap: () => notifier.toggleStatus(item.id),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: item.isActive
                                            ? AppColors.success.withAlpha(35)
                                            : AppColors.error.withAlpha(35),
                                        borderRadius: AppDecorations.radiusSm,
                                        border: Border.all(
                                          color: item.isActive
                                              ? AppColors.success
                                              : AppColors.error,
                                        ),
                                      ),
                                      child: Text(
                                        item.isActive ? 'ACTIVE' : 'INACTIVE',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: item.isActive
                                              ? AppColors.success
                                              : AppColors.error,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Center(
                                  child: IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      size: 18,
                                      color: AppColors.error,
                                    ),
                                    tooltip: 'Delete Series',
                                    onPressed: () =>
                                        notifier.deleteSeriesPrice(item.id),
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

  Widget _cell(
    String text, {
    bool isHeader = false,
    bool isBold = false,
    Color? color,
    Alignment alignment = Alignment.centerLeft,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      alignment: alignment,
      child: Text(
        text,
        style: isHeader
            ? AppTypography.labelSm.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.textSecondary,
              )
            : AppTypography.bodySm.copyWith(
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                color: color ?? AppColors.textPrimary,
              ),
      ),
    );
  }
}
