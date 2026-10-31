import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/database/database_service.dart';
import '../../shared/models/ticket_sale_model.dart';
import '../viewmodels/ticket_sales_viewmodel.dart';
import '../services/gemini_scanner_service.dart';
import '../../settings/viewmodels/series_price_viewmodel.dart';
import '../../sellers/viewmodels/seller_customer_viewmodel.dart';

/// Persistent controller bundle per scanned item to completely eliminate cursor loss
class _ItemEditControllers {
  final TextEditingController seriesCtrl;
  final TextEditingController ticketCtrl;
  final TextEditingController amountCtrl;
  final TextEditingController sellerCtrl;
  final FocusNode seriesFocus;
  final FocusNode ticketFocus;
  final FocusNode amountFocus;
  final FocusNode sellerFocus;

  _ItemEditControllers({
    required this.seriesCtrl,
    required this.ticketCtrl,
    required this.amountCtrl,
    required this.sellerCtrl,
    required this.seriesFocus,
    required this.ticketFocus,
    required this.amountFocus,
    required this.sellerFocus,
  });

  void dispose() {
    seriesCtrl.dispose();
    ticketCtrl.dispose();
    amountCtrl.dispose();
    sellerCtrl.dispose();
    seriesFocus.dispose();
    ticketFocus.dispose();
    amountFocus.dispose();
    sellerFocus.dispose();
  }
}

class AiPhotoReviewDialog extends ConsumerStatefulWidget {
  final Uint8List imageBytes;
  final List<Uint8List>? allImageBytes;
  final List<GeminiScannedItem> initialItems;
  final String activeShift;
  final DateTime activeDate;
  final String defaultSeller;
  final String? pendingPhotoId;
  final List<String>? pendingPhotoIds;

  const AiPhotoReviewDialog({
    super.key,
    required this.imageBytes,
    this.allImageBytes,
    required this.initialItems,
    required this.activeShift,
    required this.activeDate,
    required this.defaultSeller,
    this.pendingPhotoId,
    this.pendingPhotoIds,
  });

  @override
  ConsumerState<AiPhotoReviewDialog> createState() => _AiPhotoReviewDialogState();
}

class _AiPhotoReviewDialogState extends ConsumerState<AiPhotoReviewDialog> {
  late List<GeminiScannedItem> _items;
  late TextEditingController _customerCtrl;
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _dialogFocusNode = FocusNode();
  String _searchQuery = '';
  late ValueNotifier<double> _totalAmountNotifier;
  bool _isSaving = false;
  int _currentImageIndex = 0;
  bool _filterByCurrentPhoto = true; // 📸 Strictly show only active photo's numbers by default
  final Set<GeminiScannedItem> _selectedItems = {};
  final TextEditingController _customSeriesCtrl = TextEditingController();
  late List<Uint8List> _allImageBytesList;
  late List<String?> _pendingPhotoIdsList;

  // ⚡ Persistent controllers & focus nodes to guarantee zero cursor loss on typing
  final Map<GeminiScannedItem, _ItemEditControllers> _controllersMap = {};

  _ItemEditControllers _getControllers(GeminiScannedItem item) {
    return _controllersMap.putIfAbsent(item, () {
      final ser = item.series == '?' ? '' : item.series;
      final amt = item.amount > 0
          ? (item.amount % 1 == 0 ? item.amount.toInt().toString() : item.amount.toStringAsFixed(2))
          : '';
      return _ItemEditControllers(
        seriesCtrl: TextEditingController(text: ser),
        ticketCtrl: TextEditingController(text: item.ticketNo),
        amountCtrl: TextEditingController(text: amt),
        sellerCtrl: TextEditingController(text: item.sellerName),
        seriesFocus: FocusNode(),
        ticketFocus: FocusNode(),
        amountFocus: FocusNode(),
        sellerFocus: FocusNode(),
      );
    });
  }

  void _moveToNextRow(int currentIdx) {
    final list = _displayedItems;
    if (currentIdx + 1 < list.length) {
      final nextItem = list[currentIdx + 1];
      _getControllers(nextItem).ticketFocus.requestFocus();
    } else {
      _addNewRow();
    }
  }

  Uint8List get _currentImageBytes {
    if (_allImageBytesList.isNotEmpty) {
      final idx = _currentImageIndex.clamp(0, _allImageBytesList.length - 1);
      return _allImageBytesList[idx];
    }
    return widget.imageBytes;
  }

  @override
  void initState() {
    super.initState();
    if (widget.allImageBytes != null && widget.allImageBytes!.isNotEmpty) {
      _allImageBytesList = List<Uint8List>.from(widget.allImageBytes!);
      if (widget.pendingPhotoIds != null && widget.pendingPhotoIds!.length == widget.allImageBytes!.length) {
        _pendingPhotoIdsList = List<String?>.from(widget.pendingPhotoIds!);
      } else {
        _pendingPhotoIdsList = List<String?>.filled(widget.allImageBytes!.length, widget.pendingPhotoId, growable: true);
      }
    } else {
      _allImageBytesList = [widget.imageBytes];
      _pendingPhotoIdsList = [widget.pendingPhotoId];
    }

    final initialCust = widget.defaultSeller.isNotEmpty ? widget.defaultSeller : 'Walk-in Customer';
    _customerCtrl = TextEditingController(text: initialCust);
    _items = List.from(widget.initialItems);
    for (final item in _items) {
      item.sellerName = initialCust;
      _getControllers(item);
    }
    // 📑 Keep items in strict physical visual order of the scanned parcha (Column 1, Column 2, etc.)
    _recalculateAllPrices();
    _totalAmountNotifier = ValueNotifier<double>(_totalAmount);
  }

  List<GeminiScannedItem> get _displayedItems {
    var items = _items;
    // 📸 Strictly filter by current photo if multiple photos uploaded
    if (_allImageBytesList.length > 1 && _filterByCurrentPhoto) {
      items = items.where((it) => it.photoIndex == _currentImageIndex).toList();
    }
    if (_searchQuery.isEmpty) return items;
    return items.where((it) {
      final tkt = it.ticketNo.toLowerCase();
      final ser = it.series.toLowerCase();
      final amt = it.amount.toString();
      final seller = it.sellerName.toLowerCase();
      return tkt.contains(_searchQuery) ||
          ser.contains(_searchQuery) ||
          amt.contains(_searchQuery) ||
          seller.contains(_searchQuery);
    }).toList();
  }

  int get _missingSeriesCount =>
      _items.where((it) => it.series == '?' || it.series.trim().isEmpty).length;

  void _applySeriesToAllMissing(String newSeries) {
    if (newSeries.trim().isEmpty) return;
    setState(() {
      final clean = newSeries.trim().toUpperCase();
      final defaultAmt = _getPriceForSeries(clean);
      for (final item in _items) {
        if (item.series == '?' || item.series.trim().isEmpty) {
          item.series = clean;
          item.amount = defaultAmt;
          final ctrls = _controllersMap[item];
          if (ctrls != null) {
            ctrls.seriesCtrl.text = clean;
            ctrls.amountCtrl.text = defaultAmt > 0
                ? (defaultAmt % 1 == 0 ? defaultAmt.toInt().toString() : defaultAmt.toStringAsFixed(2))
                : '';
          }
        }
      }
      _totalAmountNotifier.value = _totalAmount;
    });
  }

  @override
  void dispose() {
    _customerCtrl.dispose();
    _searchCtrl.dispose();
    _searchFocusNode.dispose();
    _dialogFocusNode.dispose();
    _customSeriesCtrl.dispose();
    _totalAmountNotifier.dispose();
    for (final c in _controllersMap.values) {
      c.dispose();
    }
    _controllersMap.clear();
    super.dispose();
  }

  void _toggleSelectAll() {
    setState(() {
      final disp = _displayedItems;
      if (_selectedItems.length == disp.length) {
        _selectedItems.clear();
      } else {
        _selectedItems.clear();
        _selectedItems.addAll(disp);
      }
    });
  }

  void _toggleItemSelection(GeminiScannedItem item) {
    setState(() {
      if (_selectedItems.contains(item)) {
        _selectedItems.remove(item);
      } else {
        _selectedItems.add(item);
      }
    });
  }

  void _applySeries(String series) {
    final clean = series.trim().toUpperCase();
    if (clean.isEmpty) return;
    final targets = _selectedItems.isNotEmpty ? _selectedItems.toList() : _displayedItems;
    setState(() {
      final defaultAmt = _getPriceForSeries(clean);
      for (final it in targets) {
        it.series = clean;
        it.amount = defaultAmt;
        final ctrls = _controllersMap[it];
        if (ctrls != null) {
          ctrls.seriesCtrl.text = clean;
          ctrls.amountCtrl.text = defaultAmt > 0
              ? (defaultAmt % 1 == 0 ? defaultAmt.toInt().toString() : defaultAmt.toStringAsFixed(2))
              : '';
        }
      }
      _recalculateAllPrices();
      _totalAmountNotifier.value = _totalAmount;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ Set Series $clean on ${targets.length} tickets'),
        backgroundColor: const Color(0xFF166534),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _showAddMultipleSeriesDialog() async {
    final targets = _selectedItems.isNotEmpty ? _selectedItems.toList() : _displayedItems;
    if (targets.isEmpty) return;

    final seriesCtrl = TextEditingController(text: '24');
    final quickOptions = ['12', '20', '24', '36', '40', '60', '100'];

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: AppColors.surfaceContainerHigh,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.purple.withAlpha(40),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.copy_all_rounded, color: Colors.purpleAccent, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Add / Duplicate Series', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(
                      'Clone ${targets.length} ticket(s) with another series',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Select or Enter Series to Add:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: quickOptions.map((opt) {
                  final isSel = seriesCtrl.text.trim() == opt;
                  return InkWell(
                    onTap: () {
                      setDlgState(() => seriesCtrl.text = opt);
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSel ? Colors.purpleAccent : const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: isSel ? Colors.purpleAccent : AppColors.border),
                      ),
                      child: Text(
                        'S$opt',
                        style: TextStyle(
                          color: isSel ? Colors.black : Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: seriesCtrl,
                autofocus: true,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Target Series',
                  hintText: 'e.g. 24 or 36',
                  prefixIcon: const Icon(Icons.tag_rounded, size: 18),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purpleAccent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.add, size: 16),
              label: Text('Add ${targets.length} Tickets', style: const TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () {
                final s = seriesCtrl.text.trim();
                if (s.isNotEmpty) {
                  Navigator.pop(ctx, s);
                }
              },
            ),
          ],
        ),
      ),
    );

    if (result != null && result.trim().isNotEmpty) {
      final clean = result.trim().toUpperCase();
      final defaultAmt = _getPriceForSeries(clean);
      final List<GeminiScannedItem> newClones = [];
      for (final it in targets) {
        newClones.add(GeminiScannedItem(
          series: clean,
          ticketNo: it.ticketNo,
          amount: defaultAmt,
          quantity: it.quantity,
          sellerName: it.sellerName,
          photoIndex: it.photoIndex,
        ));
      }
      setState(() {
        _items.addAll(newClones);
        _recalculateAllPrices();
        _totalAmountNotifier.value = _totalAmount;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Added ${newClones.length} tickets in Series $clean! Total: ${_items.length}'),
          backgroundColor: Colors.purple.shade800,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _deleteSelectedItems() {
    if (_selectedItems.isEmpty) return;
    final count = _selectedItems.length;
    for (final it in _selectedItems) {
      _controllersMap[it]?.dispose();
      _controllersMap.remove(it);
    }
    setState(() {
      _items.removeWhere((it) => _selectedItems.contains(it));
      _selectedItems.clear();
      _totalAmountNotifier.value = _totalAmount;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🗑️ Removed $count selected tickets'),
        backgroundColor: Colors.red.shade800,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  double _getPriceForSeries(String series) {
    if (series.isEmpty || series == '?') return 0.0;
    final seriesState = ref.read(seriesPriceViewModelProvider);
    double price = seriesState.getPriceForSeries(series);

    if (price <= 0) {
      double config100Price = 0.0;
      final activeSeries = seriesState.seriesList.where((s) => s.isActive).toList();
      if (activeSeries.isNotEmpty) {
        final s100 = activeSeries.where((s) => s.seriesName.trim() == '100');
        if (s100.isNotEmpty && s100.first.ticketPrice > 0) {
          config100Price = s100.first.ticketPrice;
        } else {
          config100Price = activeSeries.first.ticketPrice;
        }
      }

      if (config100Price > 0) {
        final singleRate = config100Price >= 100 ? (config100Price / 100.0) : config100Price;
        final digits = series.replaceAll(RegExp(r'\D'), '');
        final multiplier = double.tryParse(digits) ?? 1.0;
        price = (multiplier > 0 ? multiplier : 1.0) * singleRate;
      } else {
        final digits = series.replaceAll(RegExp(r'\D'), '');
        price = double.tryParse(digits) ?? 0.0;
      }
    }
    return price;
  }

  void _recalculateAllPrices() {
    for (final item in _items) {
      if (item.amount <= 0 && item.series != '?') {
        item.amount = _getPriceForSeries(item.series);
      }
    }
  }

  void _addNewRow() {
    final lastSeries = _items.isNotEmpty && _items.last.series != '?' ? _items.last.series : '12';
    final defaultAmt = _getPriceForSeries(lastSeries);
    final newItem = GeminiScannedItem(
      series: lastSeries,
      ticketNo: '',
      amount: defaultAmt,
      sellerName: _customerCtrl.text.trim().isNotEmpty ? _customerCtrl.text.trim() : widget.defaultSeller,
      photoIndex: _currentImageIndex,
    );
    setState(() {
      _items.add(newItem);
      _totalAmountNotifier.value = _totalAmount;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _getControllers(newItem).ticketFocus.requestFocus();
    });
  }

  void _deleteItem(GeminiScannedItem item) {
    _controllersMap[item]?.dispose();
    _controllersMap.remove(item);
    setState(() {
      _items.remove(item);
      _selectedItems.remove(item);
      _totalAmountNotifier.value = _totalAmount;
    });
  }

  double get _totalAmount {
    return _items.fold<double>(0.0, (sum, item) => sum + (item.amount * item.quantity));
  }

  Future<void> _saveAllConfirmedTickets() async {
    if (_items.isEmpty) {
      Navigator.pop(context, false);
      return;
    }

    // ⚡ Sync latest controller text into items before saving
    for (final item in _items) {
      final c = _controllersMap[item];
      if (c != null) {
        if (c.ticketCtrl.text.trim().isNotEmpty) item.ticketNo = c.ticketCtrl.text.trim();
        if (c.seriesCtrl.text.trim().isNotEmpty) item.series = c.seriesCtrl.text.trim().toUpperCase();
        final a = double.tryParse(c.amountCtrl.text.trim());
        if (a != null) item.amount = a;
        if (c.sellerCtrl.text.trim().isNotEmpty) item.sellerName = c.sellerCtrl.text.trim();
      }
    }

    setState(() => _isSaving = true);
    final mainCustomer = _customerCtrl.text.trim().isNotEmpty ? _customerCtrl.text.trim() : 'Walk-in Customer';
    final List<TicketSaleModel> salesToSave = [];
    final now = DateTime.now();

    for (int i = 0; i < _items.length; i++) {
      final item = _items[i];
      final cleanTicketNo = item.ticketNo.trim();
      if (cleanTicketNo.isEmpty) continue;
      final cleanSeries = item.series.trim().toUpperCase().isEmpty ? '?' : item.series.trim().toUpperCase();
      final cleanSeller = item.sellerName.trim().isNotEmpty && item.sellerName != 'Walk-in Customer' ? item.sellerName.trim() : mainCustomer;
      final uniqueMicro = now.microsecondsSinceEpoch + i;
      final saleId = 'tkt_ai_${uniqueMicro}_${cleanSeries}_$cleanTicketNo';

      final sale = TicketSaleModel(
        id: saleId,
        receiptNumber: 'AI-$cleanSeries-$cleanTicketNo',
        buyerName: cleanSeller,
        buyerPhone: '+91 9876543210',
        agentCode: 'AG-AI',
        agentName: cleanSeller,
        drawCode: ((item.drawShift != null && item.drawShift!.isNotEmpty) ? item.drawShift! : widget.activeShift).replaceAll(' ', '-').toUpperCase(),
        drawName: (item.drawShift != null && item.drawShift!.isNotEmpty) ? item.drawShift! : widget.activeShift,
        ticketSeries: cleanSeries,
        ticketNumber: '$cleanSeries $cleanTicketNo',
        quantity: item.quantity > 0 ? item.quantity : 1,
        pricePerTicket: item.amount,
        totalAmount: item.amount * (item.quantity > 0 ? item.quantity : 1),
        commissionAmount: (item.amount * (item.quantity > 0 ? item.quantity : 1)) * 0.05,
        status: TicketStatus.sold,
        paymentMode: PaymentMode.cash,
        saleDate: DateTime(
          item.targetDate != null && DateTime.tryParse(item.targetDate!) != null
              ? DateTime.tryParse(item.targetDate!)!.year
              : widget.activeDate.year,
          item.targetDate != null && DateTime.tryParse(item.targetDate!) != null
              ? DateTime.tryParse(item.targetDate!)!.month
              : widget.activeDate.month,
          item.targetDate != null && DateTime.tryParse(item.targetDate!) != null
              ? DateTime.tryParse(item.targetDate!)!.day
              : widget.activeDate.day,
          now.hour,
          now.minute,
          now.second,
        ),
        drawDate: DateTime(
          item.targetDate != null && DateTime.tryParse(item.targetDate!) != null
              ? DateTime.tryParse(item.targetDate!)!.year
              : widget.activeDate.year,
          item.targetDate != null && DateTime.tryParse(item.targetDate!) != null
              ? DateTime.tryParse(item.targetDate!)!.month
              : widget.activeDate.month,
          item.targetDate != null && DateTime.tryParse(item.targetDate!) != null
              ? DateTime.tryParse(item.targetDate!)!.day
              : widget.activeDate.day,
          12,
          0,
          0,
        ),
      );

      salesToSave.add(sale);
    }

    try {
      // ⚡ INSTANT BATCH INSERTION (0.015s for 100+ tickets!)
      await ref.read(ticketSalesViewModelProvider.notifier).addTicketSalesBulk(salesToSave);

      // Approve remaining active photos
      for (final id in _pendingPhotoIdsList) {
        if (id != null && id.isNotEmpty) {
          await DatabaseService.instance.updatePendingPhotoStatus(id, 'approved');
        }
      }

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.success,
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Text('✅ Successfully booked ${salesToSave.length} numbers from Scanned Photo! (₹${_totalAmountNotifier.value.toStringAsFixed(0)})'),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.error,
            content: Text('Failed to save tickets: $e'),
          ),
        );
      }
    }
  }

  Future<void> _confirmRejectCurrentPhoto() async {
    if (_allImageBytesList.isEmpty) return;
    final targetIdx = _currentImageIndex.clamp(0, _allImageBytesList.length - 1);
    final count = _items.where((it) => it.photoIndex == targetIdx).length;
    final parchaName = _allImageBytesList.length > 1 ? 'Parcha ${targetIdx + 1}' : 'This Photo';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 24),
            const SizedBox(width: 8),
            Text('Reject $parchaName?', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Are you sure you want to reject and discard $parchaName?\n\n'
          '• $count scanned number(s) belonging to this photo will be deleted.\n'
          '• This photo will be removed from the pending queue.',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.delete_forever_rounded, size: 16),
            label: Text('Yes, Reject $parchaName', style: const TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _executeRejectPhoto(targetIdx);
    }
  }

  Future<void> _executeRejectPhoto(int targetIdx) async {
    // 1. Mark in database if pendingPhotoId exists
    if (targetIdx < _pendingPhotoIdsList.length && _pendingPhotoIdsList[targetIdx] != null) {
      final pId = _pendingPhotoIdsList[targetIdx]!;
      await DatabaseService.instance.updatePendingPhotoStatus(pId, 'rejected');
    }

    // 2. Remove controllers for items belonging to targetIdx
    final itemsToRemove = _items.where((it) => it.photoIndex == targetIdx).toList();
    for (final it in itemsToRemove) {
      _selectedItems.remove(it);
      final c = _controllersMap.remove(it);
      c?.dispose();
    }
    _items.removeWhere((it) => it.photoIndex == targetIdx);

    // 3. Re-index photoIndex for subsequent photos
    for (final it in _items) {
      if (it.photoIndex > targetIdx) {
        it.photoIndex -= 1;
      }
    }

    // 4. Remove from photo lists
    if (targetIdx < _allImageBytesList.length) {
      _allImageBytesList = List<Uint8List>.from(_allImageBytesList)..removeAt(targetIdx);
    }
    if (targetIdx < _pendingPhotoIdsList.length) {
      _pendingPhotoIdsList = List<String?>.from(_pendingPhotoIdsList)..removeAt(targetIdx);
    }

    // 5. Update state or close if empty
    if (_allImageBytesList.isEmpty || _items.isEmpty) {
      if (mounted) {
        Navigator.pop(context, true); // true to reload queue in parent screen
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.warning,
            content: Row(
              children: [
                Icon(Icons.delete_outline_rounded, color: Colors.white),
                SizedBox(width: 8),
                Text('All photos rejected & dismissed from queue.'),
              ],
            ),
          ),
        );
      }
    } else {
      setState(() {
        if (_currentImageIndex >= _allImageBytesList.length) {
          _currentImageIndex = _allImageBytesList.length - 1;
        }
        _totalAmountNotifier.value = _totalAmount;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.warning,
            content: Text('🗑️ Parcha ${targetIdx + 1} rejected. ${_allImageBytesList.length} parcha(s) remaining.'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _confirmRejectAllPhotos() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        title: const Row(
          children: [
            Icon(Icons.delete_sweep_rounded, color: AppColors.error, size: 24),
            SizedBox(width: 8),
            Text('Reject All Photos?', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Are you sure you want to reject all ${_allImageBytesList.length} photos and dismiss all ${_items.length} numbers?\n\n'
          'All pending photos in this batch will be marked as rejected.',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.delete_forever_rounded, size: 16),
            label: const Text('Reject All', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      for (final id in _pendingPhotoIdsList) {
        if (id != null && id.isNotEmpty) {
          await DatabaseService.instance.updatePendingPhotoStatus(id, 'rejected');
        }
      }
      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.warning,
            content: Text('❌ All pending photos rejected & dismissed.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Dialog(
      backgroundColor: AppColors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border, width: 1.5),
      ),
      child: Focus(
        focusNode: _dialogFocusNode,
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;

          final isCtrl = HardwareKeyboard.instance.isControlPressed;
          final isAlt = HardwareKeyboard.instance.isAltPressed;
          final key = event.logicalKey;

          // Ctrl+Enter or Cmd+Enter -> Confirm and Book all tickets
          if (isCtrl && (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter)) {
            if (!_isSaving) {
              _saveAllConfirmedTickets();
            }
            return KeyEventResult.handled;
          }

          // Alt+N or Ctrl+N -> Add Row
          if ((isAlt || isCtrl) && key == LogicalKeyboardKey.keyN) {
            _addNewRow();
            return KeyEventResult.handled;
          }

          // Ctrl+F -> Focus Search
          if (isCtrl && key == LogicalKeyboardKey.keyF) {
            _searchFocusNode.requestFocus();
            _searchCtrl.selection = TextSelection(baseOffset: 0, extentOffset: _searchCtrl.text.length);
            return KeyEventResult.handled;
          }

          // Alt+A -> Toggle Select All
          if (isAlt && key == LogicalKeyboardKey.keyA) {
            _toggleSelectAll();
            return KeyEventResult.handled;
          }

          // Alt+Delete or Delete when items selected
          if ((isAlt && key == LogicalKeyboardKey.delete) || (key == LogicalKeyboardKey.delete && _selectedItems.isNotEmpty)) {
            _deleteSelectedItems();
            return KeyEventResult.handled;
          }

          // F1 - F7 or Alt+1 - Alt+7 -> Quick Series
          if (key == LogicalKeyboardKey.f1 || (isAlt && key == LogicalKeyboardKey.digit1)) {
            _applySeries('12');
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.f2 || (isAlt && key == LogicalKeyboardKey.digit2)) {
            _applySeries('20');
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.f3 || (isAlt && key == LogicalKeyboardKey.digit3)) {
            _applySeries('24');
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.f4 || (isAlt && key == LogicalKeyboardKey.digit4)) {
            _applySeries('36');
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.f5 || (isAlt && key == LogicalKeyboardKey.digit5)) {
            _applySeries('40');
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.f6 || (isAlt && key == LogicalKeyboardKey.digit6)) {
            _applySeries('60');
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.f7 || (isAlt && key == LogicalKeyboardKey.digit7)) {
            _applySeries('100');
            return KeyEventResult.handled;
          }

          // Switch photos with Alt+Left / Alt+Right
          if (isAlt && key == LogicalKeyboardKey.arrowLeft) {
            if (_currentImageIndex > 0) {
              setState(() => _currentImageIndex--);
            }
            return KeyEventResult.handled;
          }
          if (isAlt && key == LogicalKeyboardKey.arrowRight) {
            if (_currentImageIndex < _allImageBytesList.length - 1) {
              setState(() => _currentImageIndex++);
            }
            return KeyEventResult.handled;
          }

          return KeyEventResult.ignored;
        },
        child: Container(
          width: math.min(1320.0, math.max(1050.0, screenWidth * 0.94)),
          height: math.min(880.0, math.max(680.0, screenHeight * 0.90)),
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            // 1. Header Bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.purpleAccent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.document_scanner_rounded, color: Colors.purpleAccent, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'AI Photo Scanned — Review & Confirm Booking',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.textPrimary),
                        ),
                        Row(
                          children: [
                            Text(
                              'Shift: ${widget.activeShift} | Date: ${DateFormat('dd-MM-yyyy').format(widget.activeDate)}',
                              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withAlpha(25),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: AppColors.primary.withAlpha(70)),
                              ),
                              child: const Text(
                                '⌨️ [Ctrl+Enter] Book | [Alt+N] Add | [Enter] Next | [F1..F7] Series | [Ctrl+F] Search',
                                style: TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryContainer,
                        foregroundColor: AppColors.onPrimaryContainer,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add Row (Alt+N)', style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: _addNewRow,
                    ),
                    const SizedBox(width: 10),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                      onPressed: () => Navigator.pop(context, false),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 12),

            // 📑 MULTI-PARCHA TABS (All parchas in one screen)
            if (_allImageBytesList.length > 1)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (int i = 0; i < _allImageBytesList.length; i++) ...[
                        Builder(builder: (context) {
                          final isSel = _filterByCurrentPhoto && _currentImageIndex == i;
                          final count = _items.where((it) => it.photoIndex == i).length;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  _currentImageIndex = i;
                                  _filterByCurrentPhoto = true;
                                });
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                decoration: BoxDecoration(
                                  color: isSel ? AppColors.primary : const Color(0xFF1E293B),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isSel ? AppColors.primary : AppColors.border,
                                    width: isSel ? 1.4 : 1.0,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.receipt_long_rounded,
                                      size: 15,
                                      color: isSel ? Colors.black : Colors.amberAccent,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Parcha ${i + 1} ($count)',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: isSel ? Colors.black : Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                      // "All Parchas" Tab
                      Builder(builder: (context) {
                        final isAllSel = !_filterByCurrentPhoto;
                        return InkWell(
                          onTap: () {
                            setState(() {
                              _filterByCurrentPhoto = false;
                            });
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                            decoration: BoxDecoration(
                              color: isAllSel ? Colors.purpleAccent : const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isAllSel ? Colors.purpleAccent : AppColors.border,
                                width: isAllSel ? 1.4 : 1.0,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.dashboard_rounded,
                                  size: 15,
                                  color: isAllSel ? Colors.black : Colors.purpleAccent,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'All Parchas (${_items.length})',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isAllSel ? Colors.black : Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),

            // 2. Main Content Split View
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left Side: Original Image Preview
                  Container(
                    width: 320,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          color: AppColors.surfaceContainer,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Row 1: Photo title + Prev/Next page navigation
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.photo_size_select_actual_outlined, size: 15, color: AppColors.primary),
                                      const SizedBox(width: 5),
                                      Text(
                                        _allImageBytesList.length > 1
                                            ? 'Photo ${_currentImageIndex + 1} of ${_allImageBytesList.length}'
                                            : 'Original Photo / Slip',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                  if (_allImageBytesList.length > 1)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        InkWell(
                                          onTap: _currentImageIndex > 0
                                              ? () => setState(() => _currentImageIndex--)
                                              : null,
                                          borderRadius: BorderRadius.circular(4),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                            child: Icon(
                                              Icons.arrow_back_ios_rounded,
                                              size: 13,
                                              color: _currentImageIndex > 0 ? Colors.white : Colors.white24,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 2),
                                        Text(
                                          '${_currentImageIndex + 1}/${_allImageBytesList.length}',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.cyanAccent),
                                        ),
                                        const SizedBox(width: 2),
                                        InkWell(
                                          onTap: _currentImageIndex < _allImageBytesList.length - 1
                                              ? () => setState(() => _currentImageIndex++)
                                              : null,
                                          borderRadius: BorderRadius.circular(4),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                            child: Icon(
                                              Icons.arrow_forward_ios_rounded,
                                              size: 13,
                                              color: _currentImageIndex < _allImageBytesList.length - 1
                                                  ? Colors.white
                                                  : Colors.white24,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              // Row 2: Filter Toggle + Reject Photo Button
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  if (_allImageBytesList.length > 1)
                                    InkWell(
                                      onTap: () => setState(() => _filterByCurrentPhoto = !_filterByCurrentPhoto),
                                      borderRadius: BorderRadius.circular(6),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: _filterByCurrentPhoto
                                              ? AppColors.primary.withValues(alpha: 0.2)
                                              : const Color(0xFF1E293B),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(
                                            color: _filterByCurrentPhoto ? AppColors.primary : AppColors.border,
                                            width: 1,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              _filterByCurrentPhoto ? Icons.filter_alt_rounded : Icons.all_inclusive_rounded,
                                              size: 12,
                                              color: _filterByCurrentPhoto ? AppColors.primary : Colors.grey,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              _filterByCurrentPhoto
                                                  ? 'Photo ${_currentImageIndex + 1} (${_items.where((it) => it.photoIndex == _currentImageIndex).length})'
                                                  : 'All (${_items.length})',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: _filterByCurrentPhoto ? AppColors.primary : Colors.grey,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                  else
                                    const SizedBox.shrink(),
                                  // 🗑️ REJECT CURRENT PHOTO BUTTON
                                  InkWell(
                                    onTap: _isSaving ? null : _confirmRejectCurrentPhoto,
                                    borderRadius: BorderRadius.circular(6),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.redAccent.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.7), width: 1),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.delete_forever_rounded, size: 12, color: Colors.redAccent),
                                          const SizedBox(width: 4),
                                          Text(
                                            _allImageBytesList.length > 1 ? 'Reject P${_currentImageIndex + 1}' : 'Reject Photo',
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.redAccent,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: InteractiveViewer(
                            panEnabled: true,
                            minScale: 0.8,
                            maxScale: 4.0,
                            child: Center(
                              child: Image.memory(
                                _currentImageBytes,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Right Side: Editable Scanned Tickets Table
                  Expanded(
                    child: Column(
                      children: [
                        // Customer / Party Bar
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.person_rounded, color: AppColors.primary, size: 20),
                              const SizedBox(width: 10),
                              const Text(
                                'Customer / Seller: ',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Consumer(
                                  builder: (context, ref, _) {
                                    final sellerState = ref.watch(sellerCustomerViewModelProvider);
                                    final sellers = sellerState.sellers.where((s) => s.isActive).toList();
                                    return Autocomplete<String>(
                                      initialValue: TextEditingValue(text: _customerCtrl.text),
                                      optionsBuilder: (textEditingValue) {
                                        if (textEditingValue.text.isEmpty) {
                                          return sellers.map((s) => s.name);
                                        }
                                        final q = textEditingValue.text.toLowerCase();
                                        return sellers
                                            .where((s) => s.name.toLowerCase().contains(q) || s.accessKey.toLowerCase().contains(q))
                                            .map((s) => s.name);
                                      },
                                      onSelected: (val) {
                                        setState(() {
                                          _customerCtrl.text = val;
                                          for (final item in _items) {
                                            item.sellerName = val;
                                          }
                                        });
                                      },
                                      fieldViewBuilder: (ctx, fieldCtrl, focusNode, onFieldSubmitted) {
                                        return TextField(
                                          controller: fieldCtrl,
                                          focusNode: focusNode,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                          decoration: InputDecoration(
                                            hintText: 'Type or choose Customer Name (e.g. Sanjit ji)...',
                                            isDense: true,
                                            filled: true,
                                            fillColor: AppColors.surfaceContainerLowest,
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                                          ),
                                          onChanged: (val) {
                                            _customerCtrl.text = val;
                                            for (final item in _items) {
                                              item.sellerName = val.isNotEmpty ? val : 'Walk-in Customer';
                                            }
                                            setState(() {});
                                          },
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        // ⚠️ Missing Series Quick-Fix Notification Bar
                        if (_missingSeriesCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.amber.shade700, width: 1.2),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '$_missingSeriesCount ticket(s) missing Series:',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: Colors.amber,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  width: 90,
                                  height: 28,
                                  margin: const EdgeInsets.only(right: 6),
                                  child: TextField(
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                                    decoration: InputDecoration(
                                      hintText: 'Custom Series',
                                      hintStyle: TextStyle(fontSize: 10, color: Colors.amber.shade200),
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                                      filled: true,
                                      fillColor: const Color(0xFF1E293B),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.amber.shade700)),
                                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.amber.shade700)),
                                    ),
                                    onSubmitted: (val) => _applySeriesToAllMissing(val),
                                  ),
                                ),
                                TextButton.icon(
                                  style: TextButton.styleFrom(
                                    backgroundColor: Colors.amber.shade700,
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                  ),
                                  icon: const Icon(Icons.flash_on, size: 13, color: Colors.black),
                                  label: const Text('Set 12', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                  onPressed: () => _applySeriesToAllMissing('12'),
                                ),
                                const SizedBox(width: 4),
                                TextButton.icon(
                                  style: TextButton.styleFrom(
                                    backgroundColor: Colors.amber.shade700,
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                  ),
                                  icon: const Icon(Icons.flash_on, size: 13, color: Colors.black),
                                  label: const Text('Set 24', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                  onPressed: () => _applySeriesToAllMissing('24'),
                                ),
                                const SizedBox(width: 4),
                                TextButton.icon(
                                  style: TextButton.styleFrom(
                                    backgroundColor: Colors.amber.shade700,
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                  ),
                                  icon: const Icon(Icons.flash_on, size: 13, color: Colors.black),
                                  label: const Text('Set 100', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                  onPressed: () => _applySeriesToAllMissing('100'),
                                ),
                              ],
                            ),
                          ),
                        // Layout Mode & Quick Actions Bar
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              const Icon(Icons.table_chart_rounded, size: 16, color: AppColors.primary),
                              const SizedBox(width: 6),
                              const Text(
                                'Arrangement: ',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSecondary),
                              ),
                              const SizedBox(width: 4),
                              _buildColumnSelectorBtn(1, '1 Col', Icons.view_list_rounded),
                              const SizedBox(width: 4),
                              _buildColumnSelectorBtn(2, '2 Cols (Parcha)', Icons.view_column_rounded),
                              const SizedBox(width: 4),
                              _buildColumnSelectorBtn(3, '3 Cols', Icons.grid_view_rounded),
                              const SizedBox(width: 10),
                              // 🔍 Real-Time Live Search Bar
                              Expanded(
                                child: Container(
                                  height: 32,
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceContainerLowest,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: _searchQuery.isNotEmpty ? AppColors.primary : AppColors.border,
                                      width: _searchQuery.isNotEmpty ? 1.5 : 1.0,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.search_rounded, size: 16, color: AppColors.primary),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: TextField(
                                          controller: _searchCtrl,
                                          focusNode: _searchFocusNode,
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                          decoration: InputDecoration(
                                            hintText: 'Search Ticket / Series (e.g. 53487, 24) [Ctrl+F]...',
                                            hintStyle: TextStyle(
                                              fontSize: 11,
                                              color: AppColors.textSecondary.withValues(alpha: 0.7),
                                            ),
                                            border: InputBorder.none,
                                            isDense: true,
                                            contentPadding: const EdgeInsets.symmetric(vertical: 7),
                                          ),
                                          onChanged: (val) {
                                            setState(() => _searchQuery = val.trim().toLowerCase());
                                          },
                                        ),
                                      ),
                                      if (_searchQuery.isNotEmpty) ...[
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            '${_displayedItems.length}/${_items.length}',
                                            style: const TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        GestureDetector(
                                          onTap: () {
                                            _searchCtrl.clear();
                                            setState(() => _searchQuery = '');
                                          },
                                          child: const Icon(Icons.close_rounded, size: 14, color: AppColors.textSecondary),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  backgroundColor: AppColors.surfaceContainerLowest,
                                  foregroundColor: AppColors.primary,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                ),
                                icon: const Icon(Icons.add, size: 15),
                                label: const Text('+ Add Row (Alt+N)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                onPressed: _addNewRow,
                              ),
                            ],
                          ),
                        ),

                        // ⚡ BATCH SERIES & SELECTION CONTROL BAR
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _selectedItems.isNotEmpty ? AppColors.primary : AppColors.border,
                              width: _selectedItems.isNotEmpty ? 1.4 : 1.0,
                            ),
                          ),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                // 1. Select All Checkbox & Count
                                InkWell(
                                  onTap: _toggleSelectAll,
                                  borderRadius: BorderRadius.circular(4),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: _selectedItems.isNotEmpty
                                          ? AppColors.primary.withAlpha(40)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          _selectedItems.isNotEmpty && _selectedItems.length == _displayedItems.length
                                              ? Icons.check_box_rounded
                                              : (_selectedItems.isNotEmpty
                                                  ? Icons.indeterminate_check_box_rounded
                                                  : Icons.check_box_outline_blank_rounded),
                                          size: 16,
                                          color: _selectedItems.isNotEmpty ? AppColors.primary : Colors.grey,
                                        ),
                                        const SizedBox(width: 5),
                                        Text(
                                           _selectedItems.isEmpty
                                               ? 'Select All (Alt+A)'
                                               : '${_selectedItems.length}/${_displayedItems.length} Selected',
                                           style: TextStyle(
                                             fontSize: 11,
                                             fontWeight: FontWeight.bold,
                                             color: _selectedItems.isNotEmpty ? AppColors.primary : Colors.white70,
                                           ),
                                         ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(width: 1, height: 18, color: AppColors.border),
                                const SizedBox(width: 8),

                                // 2. "Set Series" Label
                                Text(
                                  _selectedItems.isEmpty ? 'Set Series (All):' : 'Set Series (${_selectedItems.length}):',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: _selectedItems.isNotEmpty ? AppColors.primary : Colors.grey.shade400,
                                  ),
                                ),
                                const SizedBox(width: 6),

                                // Quick Series Chips with F1-F7 indicators
                                 ...[
                                   {'ser': '12', 'key': 'F1'},
                                   {'ser': '20', 'key': 'F2'},
                                   {'ser': '24', 'key': 'F3'},
                                   {'ser': '36', 'key': 'F4'},
                                   {'ser': '40', 'key': 'F5'},
                                   {'ser': '60', 'key': 'F6'},
                                   {'ser': '100', 'key': 'F7'},
                                 ].map((info) {
                                   final s = info['ser']!;
                                   final shortcut = info['key']!;
                                   return Padding(
                                     padding: const EdgeInsets.only(right: 4),
                                     child: Tooltip(
                                       message: 'Apply Series $s ($shortcut or Alt+${shortcut[1]})',
                                       child: InkWell(
                                         onTap: () => _applySeries(s),
                                         borderRadius: BorderRadius.circular(4),
                                         child: Container(
                                           padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                           decoration: BoxDecoration(
                                             color: const Color(0xFF0F172A),
                                             borderRadius: BorderRadius.circular(4),
                                             border: Border.all(color: const Color(0xFF38BDF8).withAlpha(90)),
                                           ),
                                           child: Row(
                                             mainAxisSize: MainAxisSize.min,
                                             children: [
                                               Text(
                                                 'S$s',
                                                 style: const TextStyle(
                                                   color: Color(0xFF38BDF8),
                                                   fontSize: 11,
                                                   fontWeight: FontWeight.bold,
                                                 ),
                                               ),
                                               const SizedBox(width: 3),
                                               Container(
                                                 padding: const EdgeInsets.symmetric(horizontal: 2.5, vertical: 0.5),
                                                 decoration: BoxDecoration(
                                                   color: const Color(0xFF38BDF8).withAlpha(35),
                                                   borderRadius: BorderRadius.circular(3),
                                                 ),
                                                 child: Text(
                                                   shortcut,
                                                   style: const TextStyle(
                                                     fontSize: 8,
                                                     fontWeight: FontWeight.w800,
                                                     color: Color(0xFF7DD3FC),
                                                   ),
                                                 ),
                                               ),
                                             ],
                                           ),
                                         ),
                                       ),
                                     ),
                                   );
                                 }),

                                // Custom Series Input
                                Container(
                                  width: 65,
                                  height: 26,
                                  margin: const EdgeInsets.only(left: 2, right: 4),
                                  child: TextField(
                                    controller: _customSeriesCtrl,
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                    decoration: InputDecoration(
                                      hintText: 'Custom',
                                      hintStyle: const TextStyle(fontSize: 10, color: Colors.grey),
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                      fillColor: const Color(0xFF0F172A),
                                      filled: true,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: AppColors.border)),
                                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: AppColors.border)),
                                    ),
                                    onSubmitted: (val) {
                                      if (val.trim().isNotEmpty) {
                                        _applySeries(val.trim());
                                        _customSeriesCtrl.clear();
                                      }
                                    },
                                  ),
                                ),
                                InkWell(
                                  onTap: () {
                                    if (_customSeriesCtrl.text.trim().isNotEmpty) {
                                      _applySeries(_customSeriesCtrl.text.trim());
                                      _customSeriesCtrl.clear();
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(4),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text('Apply', style: TextStyle(color: Colors.black, fontSize: 10.5, fontWeight: FontWeight.bold)),
                                  ),
                                ),

                                const SizedBox(width: 10),
                                Container(width: 1, height: 18, color: AppColors.border),
                                const SizedBox(width: 10),

                                // 3. "+ Add / Duplicate Series" Button (Multiple series add kar sake ek baar me)
                                InkWell(
                                  onTap: _showAddMultipleSeriesDialog,
                                  borderRadius: BorderRadius.circular(4),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.purple.shade900.withAlpha(160),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: Colors.purpleAccent, width: 0.8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.copy_rounded, size: 12, color: Colors.purpleAccent),
                                        const SizedBox(width: 4),
                                        Text(
                                          _selectedItems.isEmpty ? '+ Add Series (All)' : '+ Add Series (${_selectedItems.length})',
                                          style: const TextStyle(color: Colors.purpleAccent, fontSize: 10.5, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                // 4. Delete Selected (if any selected)
                                if (_selectedItems.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  InkWell(
                                    onTap: _deleteSelectedItems,
                                    borderRadius: BorderRadius.circular(4),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.red.shade900.withAlpha(160),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: Colors.redAccent, width: 0.8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.delete_outline, size: 12, color: Colors.redAccent),
                                          const SizedBox(width: 3),
                                          Text(
                                            'Del (${_selectedItems.length})',
                                            style: const TextStyle(color: Colors.redAccent, fontSize: 10.5, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.border),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: _displayedItems.isEmpty
                                ? Center(
                                    child: Text(
                                      _searchQuery.isNotEmpty
                                          ? 'No tickets matching "$_searchQuery".\nClear search to see all ${_items.length} tickets.'
                                          : 'No tickets detected in this image.\nClick "+ Add Row" to enter manually.',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(color: AppColors.textSecondary),
                                    ),
                                  )
                                : _columnCount == 1
                                    ? ListView.separated(
                                        itemCount: _displayedItems.length,
                                        separatorBuilder: (_, _) => const Divider(color: AppColors.border, height: 1),
                                        itemBuilder: (context, idx) {
                                          final item = _displayedItems[idx];
                                          final originalIdx = _items.indexOf(item);
                                          return _buildFullListRow(item, originalIdx >= 0 ? originalIdx : idx);
                                        },
                                      )
                                    : GridView.builder(
                                        padding: const EdgeInsets.all(8),
                                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: _columnCount,
                                          mainAxisExtent: 72,
                                          crossAxisSpacing: 8,
                                          mainAxisSpacing: 8,
                                        ),
                                        itemCount: _displayedItems.length,
                                        itemBuilder: (context, idx) {
                                          final item = _displayedItems[idx];
                                          final originalIdx = _items.indexOf(item);
                                          return _buildCompactGridCard(item, originalIdx >= 0 ? originalIdx : idx);
                                        },
                                      ),
                          ),
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      const Divider(color: AppColors.border, height: 1),
      const SizedBox(height: 14),

            // 3. Bottom Summary & Actions Footer (wrapped with LayoutBuilder & SingleChildScrollView to eliminate any overflow)
            LayoutBuilder(
              builder: (context, footerConstraints) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: footerConstraints.maxWidth),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Summary Badges
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
                              ),
                              child: Text(
                                'Total Numbers: ${_items.length}',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 13),
                              ),
                            ),
                            const SizedBox(width: 10),
                            ValueListenableBuilder<double>(
                              valueListenable: _totalAmountNotifier,
                              builder: (context, total, _) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppColors.success.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: AppColors.success.withValues(alpha: 0.5)),
                                  ),
                                  child: Text(
                                    'Total Amount: ₹${total.toStringAsFixed(0)}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.success, fontSize: 13),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),

                        const SizedBox(width: 16),

                        // Action Buttons
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 🗑️ Reject Current Photo / Parcha Button
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.error,
                                side: const BorderSide(color: AppColors.error),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              icon: const Icon(Icons.delete_outline_rounded, size: 16),
                              label: Text(
                                _allImageBytesList.length > 1
                                    ? 'Reject Parcha ${_currentImageIndex + 1}'
                                    : 'Reject Photo',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              onPressed: _isSaving ? null : _confirmRejectCurrentPhoto,
                            ),
                            if (_allImageBytesList.length > 1) ...[
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red.shade300,
                                  side: BorderSide(color: Colors.red.shade700),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                icon: const Icon(Icons.delete_sweep_rounded, size: 15),
                                label: const Text('Reject All', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                onPressed: _isSaving ? null : _confirmRejectAllPhotos,
                              ),
                            ],
                            const SizedBox(width: 10),
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Close', style: TextStyle(color: AppColors.textSecondary)),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.success,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              icon: _isSaving
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                                  : const Icon(Icons.check_circle_outline_rounded, size: 18),
                              label: Text(
                                _isSaving ? 'Saving...' : 'Confirm & Book All (${_items.length}) [Ctrl+Enter]',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              onPressed: _isSaving ? null : _saveAllConfirmedTickets,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      ),
    );
  }

  int _columnCount = 2; // Defaults to 2 columns matching physical lottery parchas

  Widget _buildColumnSelectorBtn(int cols, String label, IconData icon) {
    final isSelected = _columnCount == cols;
    return InkWell(
      onTap: () => setState(() => _columnCount = cols),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: isSelected ? AppColors.primary : AppColors.textSecondary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFullListRow(GeminiScannedItem item, int idx) {
    final isMissing = item.series == '?' || item.series.isEmpty;
    final isSelected = _selectedItems.contains(item);
    final ctrls = _getControllers(item);
    return Container(
      key: ValueKey('full_row_${item.hashCode}'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: isSelected
          ? AppColors.primary.withAlpha(35)
          : (isMissing ? Colors.amber.withValues(alpha: 0.12) : null),
      child: Row(
        children: [
          // Selection Checkbox
          InkWell(
            onTap: () => _toggleItemSelection(item),
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(
                isSelected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                size: 16,
                color: isSelected ? AppColors.primary : Colors.grey.shade600,
              ),
            ),
          ),
          // Index & Photo Tag
          SizedBox(
            width: _allImageBytesList.length > 1 ? 62 : 28,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${idx + 1}',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textSecondary, fontSize: 12),
                ),
                if (_allImageBytesList.length > 1) ...[
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () {
                      if (_currentImageIndex != item.photoIndex) {
                        setState(() => _currentImageIndex = item.photoIndex);
                      }
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: item.photoIndex == _currentImageIndex
                            ? AppColors.primary.withValues(alpha: 0.25)
                            : const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: item.photoIndex == _currentImageIndex ? AppColors.primary : Colors.transparent,
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        'P${item.photoIndex + 1}',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: item.photoIndex == _currentImageIndex ? AppColors.primary : Colors.white70,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Series Input
          SizedBox(
            width: 90,
            child: TextField(
              key: ValueKey('full_ser_${item.hashCode}'),
              controller: ctrls.seriesCtrl,
              focusNode: ctrls.seriesFocus,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: isMissing ? Colors.amber : AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                labelText: isMissing ? 'Series ⚠️' : 'Series *',
                labelStyle: TextStyle(
                  color: isMissing ? Colors.amber : AppColors.textSecondary,
                  fontWeight: isMissing ? FontWeight.bold : FontWeight.normal,
                ),
                hintText: 'e.g. 12',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(
                    color: isMissing ? Colors.amber : AppColors.border,
                    width: isMissing ? 1.5 : 1.0,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(
                    color: isMissing ? Colors.amber : AppColors.border,
                    width: isMissing ? 1.5 : 1.0,
                  ),
                ),
              ),
              onChanged: (val) {
                final clean = val.trim().toUpperCase();
                item.series = clean;
                final p = _getPriceForSeries(clean);
                if (p > 0) {
                  item.amount = p;
                  ctrls.amountCtrl.text = p % 1 == 0 ? p.toInt().toString() : p.toStringAsFixed(2);
                }
                _totalAmountNotifier.value = _totalAmount;
              },
              onSubmitted: (_) => ctrls.ticketFocus.requestFocus(),
            ),
          ),
          const SizedBox(width: 8),

          // 5-Digit Ticket No Input
          Expanded(
            flex: 2,
            child: TextField(
              key: ValueKey('full_tkt_${item.hashCode}'),
              controller: ctrls.ticketCtrl,
              focusNode: ctrls.ticketFocus,
              maxLength: 5,
              style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Number (5-Digit) *',
                hintText: 'e.g. 69476',
                isDense: true,
                counterText: '',
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
              ),
              onChanged: (val) => item.ticketNo = val.trim(),
              onSubmitted: (_) => _moveToNextRow(idx),
            ),
          ),
          const SizedBox(width: 8),

          // Rate / Amount Input
          SizedBox(
            width: 85,
            child: TextField(
              key: ValueKey('full_amt_${item.hashCode}'),
              controller: ctrls.amountCtrl,
              focusNode: ctrls.amountFocus,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.success, fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Rate (₹)',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
              ),
              onChanged: (val) {
                item.amount = double.tryParse(val.trim()) ?? 0.0;
                _totalAmountNotifier.value = _totalAmount;
              },
              onSubmitted: (_) => ctrls.sellerFocus.requestFocus(),
            ),
          ),
          const SizedBox(width: 8),

          // Seller / Customer Input
          Expanded(
            flex: 2,
            child: TextField(
              key: ValueKey('full_seller_${item.hashCode}'),
              controller: ctrls.sellerCtrl,
              focusNode: ctrls.sellerFocus,
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                labelText: 'Seller / Customer',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
              ),
              onChanged: (val) => item.sellerName = val.trim(),
              onSubmitted: (_) => _moveToNextRow(idx),
            ),
          ),
          const SizedBox(width: 4),

          // Delete Button
          IconButton(
            icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 18),
            tooltip: 'Remove',
            onPressed: () => _deleteItem(item),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactGridCard(GeminiScannedItem item, int idx) {
    final isMissing = item.series == '?' || item.series.isEmpty;
    final isSelected = _selectedItems.contains(item);
    final ctrls = _getControllers(item);
    return Container(
      key: ValueKey('compact_card_${item.hashCode}'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isSelected
            ? AppColors.primary.withAlpha(35)
            : (isMissing ? Colors.amber.withValues(alpha: 0.14) : AppColors.surfaceContainerLowest),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSelected
              ? AppColors.primary
              : (isMissing ? Colors.amber.shade600 : AppColors.border),
          width: isSelected ? 1.6 : (isMissing ? 1.5 : 1.0),
        ),
      ),
      child: Row(
        children: [
          // Selection Checkbox
          InkWell(
            onTap: () => _toggleItemSelection(item),
            child: Padding(
              padding: const EdgeInsets.only(right: 5),
              child: Icon(
                isSelected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                size: 16,
                color: isSelected ? AppColors.primary : Colors.grey.shade600,
              ),
            ),
          ),
          // Index Badge & Photo Tag
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: isMissing ? Colors.amber.shade800 : AppColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '#${idx + 1}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                    color: isMissing ? Colors.black : AppColors.textSecondary,
                  ),
                ),
              ),
              if (_allImageBytesList.length > 1) ...[
                const SizedBox(width: 3),
                InkWell(
                  onTap: () {
                    if (_currentImageIndex != item.photoIndex) {
                      setState(() => _currentImageIndex = item.photoIndex);
                    }
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: item.photoIndex == _currentImageIndex
                          ? AppColors.primary.withValues(alpha: 0.25)
                          : const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: item.photoIndex == _currentImageIndex ? AppColors.primary : Colors.transparent,
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      'P${item.photoIndex + 1}',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: item.photoIndex == _currentImageIndex ? AppColors.primary : Colors.white70,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(width: 6),

          // Compact Series Input
          SizedBox(
            width: 58,
            child: TextField(
              key: ValueKey('compact_ser_${item.hashCode}'),
              controller: ctrls.seriesCtrl,
              focusNode: ctrls.seriesFocus,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: isMissing ? Colors.amberAccent : AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                labelText: isMissing ? 'Ser ⚠️' : 'Ser',
                labelStyle: TextStyle(
                  fontSize: 10,
                  color: isMissing ? Colors.amber : AppColors.textSecondary,
                  fontWeight: isMissing ? FontWeight.bold : FontWeight.normal,
                ),
                hintText: '12',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
              ),
              onChanged: (val) {
                final clean = val.trim().toUpperCase();
                item.series = clean;
                final p = _getPriceForSeries(clean);
                if (p > 0) {
                  item.amount = p;
                  ctrls.amountCtrl.text = p % 1 == 0 ? p.toInt().toString() : p.toStringAsFixed(1);
                }
                _totalAmountNotifier.value = _totalAmount;
              },
              onSubmitted: (_) => ctrls.ticketFocus.requestFocus(),
            ),
          ),
          const SizedBox(width: 6),

          // 5-Digit Ticket Input
          Expanded(
            child: TextField(
              key: ValueKey('compact_tkt_${item.hashCode}'),
              controller: ctrls.ticketCtrl,
              focusNode: ctrls.ticketFocus,
              maxLength: 5,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w900,
                fontSize: 13,
                letterSpacing: 0.5,
              ),
              decoration: InputDecoration(
                labelText: 'Number',
                labelStyle: const TextStyle(fontSize: 10),
                hintText: '69476',
                isDense: true,
                counterText: '',
                contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
              ),
              onChanged: (val) => item.ticketNo = val.trim(),
              onSubmitted: (_) => _moveToNextRow(idx),
            ),
          ),
          const SizedBox(width: 6),

          // Rate (₹) Input
          SizedBox(
            width: 52,
            child: TextField(
              key: ValueKey('compact_amt_${item.hashCode}'),
              controller: ctrls.amountCtrl,
              focusNode: ctrls.amountFocus,
              keyboardType: TextInputType.number,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.success,
                fontSize: 11,
              ),
              decoration: InputDecoration(
                labelText: '₹',
                labelStyle: const TextStyle(fontSize: 10, color: AppColors.success),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
              ),
              onChanged: (val) {
                item.amount = double.tryParse(val.trim()) ?? 0.0;
                _totalAmountNotifier.value = _totalAmount;
              },
              onSubmitted: (_) => _moveToNextRow(idx),
            ),
          ),

          // Delete
          InkWell(
            onTap: () => _deleteItem(item),
            borderRadius: BorderRadius.circular(4),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close, size: 15, color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}
