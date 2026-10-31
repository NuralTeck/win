import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../bookings/services/gemini_scanner_service.dart';
import '../../settings/viewmodels/series_price_viewmodel.dart';
import '../../../core/database/database_service.dart';
import '../models/voucher_model.dart';
import '../models/unsold_model.dart';
import '../viewmodels/voucher_viewmodel.dart';
import '../viewmodels/unsold_viewmodel.dart';
import '../../sellers/viewmodels/seller_customer_viewmodel.dart';
import 'searchable_dealer_picker_dialog.dart';

class _FastVoucher {
  final String partyLower;
  final String dealerLower;
  final String dateClean;
  final String shiftLower;
  final String seriesUpper;
  final String seriesNum;
  final int start;
  final int end;
  final String partyName;

  _FastVoucher({
    required this.partyLower,
    required this.dealerLower,
    required this.dateClean,
    required this.shiftLower,
    required this.seriesUpper,
    required this.seriesNum,
    required this.start,
    required this.end,
    required this.partyName,
  });
}

enum StockScanMode { voucher, unsold }

class AiStockScanReviewDialog extends ConsumerStatefulWidget {
  final Uint8List imageBytes;
  final List<Uint8List>? allImageBytes;
  final List<GeminiScannedItem> initialItems;
  final StockScanMode mode;
  final String activeShift;
  final DateTime activeDate;
  final String defaultParty;

  const AiStockScanReviewDialog({
    super.key,
    required this.imageBytes,
    this.allImageBytes,
    required this.initialItems,
    required this.mode,
    required this.activeShift,
    required this.activeDate,
    required this.defaultParty,
  });

  @override
  ConsumerState<AiStockScanReviewDialog> createState() => _AiStockScanReviewDialogState();
}

class _AiStockScanReviewDialogState extends ConsumerState<AiStockScanReviewDialog> {
  late List<GeminiScannedItem> _items;
  late TextEditingController _partyCtrl;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String _selectedSeriesFilter = 'ALL';
  String _selectedDateFilter = 'ALL';
  String _selectedShiftFilter = 'ALL';
  String _selectedStatusFilter = 'ALL'; // 'ALL', 'UNMATCHED', 'VALID'
  bool _isSaving = false;
  bool _isImageMinimized = false;
  int _currentImageIndex = 0;
  bool _filterByCurrentPhoto = true; // 📸 Strictly show only active slip's numbers by default
  List<Uint8List> get _imagesList {
    if (widget.allImageBytes != null && widget.allImageBytes!.isNotEmpty) {
      return widget.allImageBytes!;
    }
    return [widget.imageBytes];
  }
  late String _selectedShift;
  late DateTime _activeDate;
  final Set<GeminiScannedItem> _selectedItems = {};
  int? _lastSelectedIdx;
  GeminiScannedItem? _activeEditingItem;
  bool _multiCursorSyncEnabled = true;
  bool _showFindReplaceBar = false;
  int _multiCursorOffsetFromEnd = 3;
  final TextEditingController _findCtrl = TextEditingController();
  final TextEditingController _replaceCtrl = TextEditingController();

  void _handleCursorOffsetChanged(int offsetFromEnd) {
    if (_multiCursorOffsetFromEnd != offsetFromEnd) {
      setState(() {
        _multiCursorOffsetFromEnd = offsetFromEnd;
      });
    }
  }
  List<VoucherModel> _allVouchers = [];
  List<_FastVoucher> _fastVouchers = [];
  List<UnsoldModel> _allUnsold = [];

  // High-performance status and count cache
  final Map<GeminiScannedItem, String?> _validationCache = {};
  int _cachedUnmatchedCount = 0;
  int _cachedNotInVoucherCount = 0;
  int _cachedAlreadyIssuedCount = 0;
  int _cachedValidCount = 0;
  int _cachedAiDoubtsCount = 0;

  // 🏢 Dealer & Sub-Seller Network Hierarchy
  List<String> _availableDealers = [];
  Map<String, List<String>> _dealerToSellersMap = {};
  String? _selectedDealer;
  String? _selectedSubSeller;

  // Manual fast entry controllers
  final TextEditingController _manualSeriesCtrl = TextEditingController(text: '12');
  final TextEditingController _manualTicketCtrl = TextEditingController();
  final FocusNode _manualTicketFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _selectedShift = widget.activeShift.isNotEmpty ? widget.activeShift : 'Dear 1 PM';
    _activeDate = widget.activeDate;
    final initialParty = widget.defaultParty.isNotEmpty ? widget.defaultParty : 'Walk-in Party';
    _partyCtrl = TextEditingController(text: initialParty);
    _items = GeminiScannerService.instance.condenseIntoRanges(widget.initialItems);
    
    // Auto-adopt detected date from parsed items if available, always aligning year to active session year!
    final firstItemDate = _items.where((it) => it.targetDate != null && it.targetDate!.isNotEmpty).firstOrNull?.targetDate;
    if (firstItemDate != null) {
      final parsed = DateTime.tryParse(firstItemDate);
      if (parsed != null) {
        _activeDate = DateTime(widget.activeDate.year, parsed.month, parsed.day);
      }
    }

    // Normalize all items to the active session year (prevents 2021 vs 2026 mismatch)
    final alignedDateStr = DateFormat('yyyy-MM-dd').format(_activeDate);
    for (final it in _items) {
      if (it.targetDate != null && it.targetDate!.isNotEmpty) {
        final p = DateTime.tryParse(it.targetDate!);
        if (p != null) {
          it.targetDate = DateFormat('yyyy-MM-dd').format(DateTime(widget.activeDate.year, p.month, p.day));
        } else {
          it.targetDate = alignedDateStr;
        }
      } else {
        it.targetDate = alignedDateStr;
      }
    }
    
    _buildFastVouchers();
    _refreshValidationCache();
    _loadAllVouchers();
    _loadAllUnsold();
    _recalculateAllPrices();
    _loadDealersAndSellers();
  }

  void _loadDealersAndSellers() {
    final list = ref.read(sellerCustomerViewModelProvider).sellers;
    if (list.isEmpty) {
      ref.read(sellerCustomerViewModelProvider.notifier).loadSellers();
      return;
    }
    final dealers = <String>[];
    final map = <String, List<String>>{};

    for (final s in list) {
      final name = s.name.trim();
      if (name.isEmpty) continue;
      if (s.isDealer) {
        dealers.add(name);
        map[name] = [];
        map[name.toLowerCase()] = [];
      }
    }
    dealers.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    for (final s in list) {
      final name = s.name.trim();
      if (name.isEmpty || s.isDealer) continue;
      final parent = (s.parentDealer ?? '').trim();
      if (parent.isNotEmpty) {
        if (map.containsKey(parent)) {
          map[parent]!.add(name);
        }
        final pLower = parent.toLowerCase();
        if (map.containsKey(pLower) && pLower != parent) {
          map[pLower]!.add(name);
        }
      }
    }
    for (final l in map.values) {
      l.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    }

    if (mounted) {
      setState(() {
        _availableDealers = dealers;
        _dealerToSellersMap = map;

        if (_partyCtrl.text.isNotEmpty) {
          final p = _partyCtrl.text.trim();
          if (dealers.contains(p)) {
            _selectedDealer = p;
            _selectedSubSeller = null;
          } else {
            for (final d in dealers) {
              if (map[d]?.contains(p) ?? false) {
                _selectedDealer = d;
                _selectedSubSeller = p;
                break;
              }
            }
          }
        }
      });
    }
  }

  void _buildFastVouchers() {
    final src = _allVouchers.isNotEmpty ? _allVouchers : ref.read(voucherViewModelProvider).vouchers;
    final list = <_FastVoucher>[];
    for (final v in src) {
      final s = int.tryParse(v.fromTicket.replaceAll(RegExp(r'\D'), ''));
      final e = int.tryParse(v.toTicket.replaceAll(RegExp(r'\D'), '')) ?? s;
      if (s == null) continue;
      final ser = v.series.trim().toUpperCase();
      list.add(_FastVoucher(
        partyLower: v.partyName.trim().toLowerCase(),
        dealerLower: v.effectiveDealer.trim().toLowerCase(),
        dateClean: v.date.replaceAll('/', '-').replaceAll('.', '-').trim(),
        shiftLower: v.drawShift.trim().toLowerCase(),
        seriesUpper: ser,
        seriesNum: ser.replaceAll(RegExp(r'\D'), ''),
        start: s,
        end: e ?? s,
        partyName: v.partyName.trim(),
      ));
    }
    _fastVouchers = list;
  }

  // 🛡️ Robust Date & Shift Normalization Helpers
  static String _normalizeDateToYmd(String d) {
    final clean = d.replaceAll('/', '-').replaceAll('.', '-').trim();
    final parts = clean.split('-');
    if (parts.length >= 3) {
      if (parts[0].length == 4) {
        final y = parts[0];
        final m = parts[1].padLeft(2, '0');
        final day = parts[2].padLeft(2, '0');
        return '$y-$m-$day';
      } else {
        final day = parts[0].padLeft(2, '0');
        final m = parts[1].padLeft(2, '0');
        var y = parts[2];
        if (y.length == 2) y = '20$y';
        return '$y-$m-$day';
      }
    }
    return clean;
  }

  static String _extractMonthDay(String d) {
    final clean = d.replaceAll('/', '-').replaceAll('.', '-').trim();
    final parts = clean.split('-');
    if (parts.length >= 3) {
      if (parts[0].length == 4) {
        return '${parts[1].padLeft(2, '0')}-${parts[2].padLeft(2, '0')}';
      } else {
        return '${parts[1].padLeft(2, '0')}-${parts[0].padLeft(2, '0')}';
      }
    }
    return clean;
  }

  static String _canonicalShift(String s) {
    final lower = s.toLowerCase().trim();
    if (lower == 'all') return 'all';
    if (lower.contains('mor') || lower.contains('1')) return '1';
    if (lower.contains('day') || lower.contains('6')) return '6';
    if (lower.contains('eve') || lower.contains('nig') || lower.contains('8') || lower.contains('night')) return '8';
    return lower.replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  void _refreshValidationCache() {
    _validationCache.clear();
    int unmatch = 0;
    int notInVouch = 0;
    int already = 0;
    int valid = 0;
    int doubts = 0;

    // Track internal duplicates within the current reviewed batch
    final seenRanges = <String, GeminiScannedItem>{};

    for (final item in _items) {
      if (item.aiDoubt != null && item.aiDoubt!.isNotEmpty) {
        doubts++;
      }

      final from = item.fromTicket.trim();
      final to = item.toTicket.trim();
      final startI = int.tryParse(from);
      final endI = int.tryParse(to);
      final cleanSer = item.series.trim().toUpperCase();
      final dateStr = DateFormat('yyyy-MM-dd').format(_activeDate);
      final rawItemDate = (item.targetDate != null && item.targetDate!.isNotEmpty) ? item.targetDate! : dateStr;
      final normItemDate = _normalizeDateToYmd(rawItemDate);
      final rawItemShift = (item.drawShift != null && item.drawShift!.isNotEmpty) ? item.drawShift! : _selectedShift;
      final itemCanonicalShift = _canonicalShift(rawItemShift);

      bool isBatchDuplicate = false;
      if (startI != null && endI != null) {
        for (final entry in seenRanges.entries) {
          final parts = entry.key.split('_');
          if (parts.length >= 3 && parts[0] == normItemDate && parts[1] == itemCanonicalShift && parts[2] == cleanSer) {
            final prevFrom = int.tryParse(entry.value.fromTicket) ?? 0;
            final prevTo = int.tryParse(entry.value.toTicket) ?? prevFrom;
            if (startI <= prevTo && endI >= prevFrom) {
              isBatchDuplicate = true;
              break;
            }
          }
        }
      }

      String? status;
      if (isBatchDuplicate) {
        status = 'Duplicate in Scan';
      } else {
        status = _computeItemValidationStatus(item);
      }

      _validationCache[item] = status;

      if (startI != null && endI != null && !isBatchDuplicate) {
        seenRanges['${normItemDate}_${itemCanonicalShift}_$cleanSer'] = item;
      }

      if (status != null) {
        unmatch++;
        if (status.contains('Not in Voucher') || status.contains('Issued to')) notInVouch++;
        if (status.contains('Already') || status.contains('Duplicate')) already++;
      } else {
        valid++;
      }
    }

    _cachedUnmatchedCount = unmatch;
    _cachedNotInVoucherCount = notInVouch;
    _cachedAlreadyIssuedCount = already;
    _cachedValidCount = valid;
    _cachedAiDoubtsCount = doubts;
  }

  void _showAiDoubtsModal() {
    final doubtfulItems = _items.where((it) => it.aiDoubt != null && it.aiDoubt!.isNotEmpty).toList();
    final generalConfusions = GeminiScannerService.instance.lastAiConfusions;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: const Color(0xFFF59E0B).withAlpha(120)),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withAlpha(30),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.help_outline_rounded, color: Color(0xFFF59E0B), size: 22),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AI Parcha Scanner Doubts & Notes',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  Text(
                    'AI ko in jagahon par confusion ya doubt tha — please cross-check:',
                    style: TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (generalConfusions.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.withAlpha(80)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '📝 General Parcha Notes from AI:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.amberAccent),
                      ),
                      const SizedBox(height: 4),
                      ...generalConfusions.map((c) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('• ', style: TextStyle(color: Colors.amberAccent)),
                            Expanded(
                              child: Text(c, style: const TextStyle(color: Colors.white, fontSize: 11.5)),
                            ),
                          ],
                        ),
                      )),
                    ],
                  ),
                ),
              ],
              if (doubtfulItems.isEmpty && generalConfusions.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(
                    child: Text(
                      '✅ AI had 0 doubts on this parcha! Everything was parsed clearly.',
                      style: TextStyle(color: Colors.greenAccent, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ),
                )
              else if (doubtfulItems.isNotEmpty) ...[
                Text(
                  '${doubtfulItems.length} Items with Ambiguous / Unclear Handwriting:',
                  style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 12),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: doubtfulItems.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (c, i) {
                      final item = doubtfulItems[i];
                      final rowNum = _items.indexOf(item) + 1;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFF59E0B).withAlpha(100)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text('#$rowNum', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Ser ${item.series} • ${item.ticketNo}',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white)),
                                  const SizedBox(height: 2),
                                  Text('⚠️ ${item.aiDoubt}',
                                      style: const TextStyle(fontSize: 11, color: Color(0xFFFBBF24))),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFD97706),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () {
                                Navigator.pop(ctx);
                                setState(() {
                                  _selectedStatusFilter = 'AI_DOUBTS';
                                });
                              },
                              child: const Text('Edit', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: Colors.grey)),
          ),
          if (doubtfulItems.isNotEmpty)
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() {
                  _selectedStatusFilter = 'AI_DOUBTS';
                });
              },
              icon: const Icon(Icons.filter_list_rounded, size: 14),
              label: const Text('Filter Doubts in Table'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
                foregroundColor: Colors.black,
              ),
            ),
        ],
      ),
    );
  }

  void _refreshSingleItemValidation(GeminiScannedItem item) {
    final oldStatus = _validationCache[item];
    final newStatus = _computeItemValidationStatus(item);
    _validationCache[item] = newStatus;

    if (oldStatus != newStatus) {
      if (oldStatus != null) {
        _cachedUnmatchedCount--;
        if (oldStatus.contains('Not in Voucher')) _cachedNotInVoucherCount--;
        if (oldStatus.contains('Already')) _cachedAlreadyIssuedCount--;
      } else {
        _cachedValidCount--;
      }

      if (newStatus != null) {
        _cachedUnmatchedCount++;
        if (newStatus.contains('Not in Voucher')) _cachedNotInVoucherCount++;
        if (newStatus.contains('Already')) _cachedAlreadyIssuedCount++;
      } else {
        _cachedValidCount++;
      }
    }
  }

  Future<void> _loadAllVouchers() async {
    try {
      final rows = await DatabaseService.instance.getVouchers();
      if (mounted) {
        _allVouchers = rows.map((r) => VoucherModel.fromMap(r)).toList();
        _buildFastVouchers();
        _refreshValidationCache();
        setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _loadAllUnsold() async {
    try {
      final rows = await DatabaseService.instance.getUnsoldTickets();
      if (mounted) {
        _allUnsold = rows.map((r) => UnsoldModel.fromMap(r)).toList();
        _refreshValidationCache();
        setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _pickMainDate() async {
    final isVoucher = widget.mode == StockScanMode.voucher;
    final picked = await showDatePicker(
      context: context,
      initialDate: _activeDate,
      firstDate: DateTime(1970),
      lastDate: DateTime(2999),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.dark(
            primary: isVoucher ? const Color(0xFF38BDF8) : const Color(0xFFF87171),
            surface: const Color(0xFF1E293B),
          ),
          dialogTheme: const DialogThemeData(
            backgroundColor: Color(0xFF0F172A),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      final formatted = DateFormat('yyyy-MM-dd').format(picked);
      setState(() {
        _activeDate = picked;
        for (final it in _items) {
          it.targetDate = formatted;
        }
        _refreshValidationCache();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📅 Updated Date to ${DateFormat('dd-MM-yyyy').format(picked)} for ALL ${_items.length} items!'),
            backgroundColor: const Color(0xFF166534),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _partyCtrl.dispose();
    _searchCtrl.dispose();
    _findCtrl.dispose();
    _replaceCtrl.dispose();
    _manualSeriesCtrl.dispose();
    _manualTicketCtrl.dispose();
    _manualTicketFocusNode.dispose();
    super.dispose();
  }

  void _recalculateAllPrices() {
    final seriesState = ref.read(seriesPriceViewModelProvider);
    for (final item in _items) {
      if (item.series.isNotEmpty && item.series != '?') {
        final p = seriesState.getPriceForSeries(item.series);
        item.amount = p * (item.quantity > 0 ? item.quantity : 1);
      }
    }
  }

  double _getPriceForSeries(String series) {
    if (series.isEmpty || series == '?') return 0.0;
    final seriesState = ref.read(seriesPriceViewModelProvider);
    return seriesState.getPriceForSeries(series);
  }

  double get _totalAmount => _items.fold(0.0, (sum, i) => sum + i.amount);
  int get _totalTickets => _items.fold(0, (sum, i) => sum + (i.quantity > 0 ? i.quantity : 1));

  int get _missingSeriesCount =>
      _items.where((it) => it.series == '?' || it.series.trim().isEmpty).length;

  int get _unmatchedCount => _cachedUnmatchedCount;
  int get _alreadyIssuedCount => _cachedAlreadyIssuedCount;
  int get _notInVoucherCount => _cachedNotInVoucherCount;
  int get _validCount => _cachedValidCount;

  void _removeAlreadyIssuedItems() {
    setState(() {
      _items.removeWhere((it) {
        final s = _getItemValidationStatus(it);
        return s != null && (s.contains('Already in Voucher') || s.contains('Already Returned'));
      });
      _refreshValidationCache();
      _recalculateAllPrices();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🗑️  Removed all already issued / duplicate items!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _removeNotInVoucherItems() {
    final count = _notInVoucherCount;
    setState(() {
      _items.removeWhere((it) {
        final s = _getItemValidationStatus(it);
        return s != null && s.contains('Not in Voucher');
      });
      _refreshValidationCache();
      _recalculateAllPrices();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🗑️ Removed $count tickets that were not in any voucher!'),
        backgroundColor: const Color(0xFF166534),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Set<String> get _availableSeriesList {
    final s = <String>{};
    for (final it in _items) {
      if (it.series.isNotEmpty) s.add(it.series);
    }
    return s;
  }

  List<String> get _availableDatesList {
    final d = <String>{};
    for (final it in _items) {
      if (it.targetDate != null && it.targetDate!.isNotEmpty) {
        d.add(it.targetDate!);
      }
    }
    final sorted = d.toList()..sort();
    return sorted;
  }

  List<String> get _availableShiftsList {
    final s = <String>{};
    for (final it in _items) {
      final sh = (it.drawShift != null && it.drawShift!.isNotEmpty) ? it.drawShift! : _selectedShift;
      s.add(sh);
    }
    final list = s.toList();
    list.sort((a, b) => a.compareTo(b));
    return list;
  }

  List<GeminiScannedItem> get _displayedItems {
    var filtered = _items;
    // 📸 Strictly filter by current photo/slip if multiple slips uploaded
    if (_imagesList.length > 1 && _filterByCurrentPhoto) {
      filtered = filtered.where((it) => it == _activeEditingItem || it.photoIndex == _currentImageIndex).toList();
    }
    if (_selectedSeriesFilter != 'ALL') {
      if (_selectedSeriesFilter == '?') {
        filtered = filtered.where((it) => it == _activeEditingItem || it.series == '?' || it.series.trim().isEmpty).toList();
      } else {
        filtered = filtered.where((it) => it == _activeEditingItem || it.series == _selectedSeriesFilter).toList();
      }
    }

    if (_selectedDateFilter != 'ALL') {
      filtered = filtered.where((it) => it == _activeEditingItem || it.targetDate == _selectedDateFilter).toList();
    }

    if (_selectedShiftFilter != 'ALL') {
      filtered = filtered.where((it) {
        if (it == _activeEditingItem) return true;
        final sh = (it.drawShift != null && it.drawShift!.isNotEmpty) ? it.drawShift! : _selectedShift;
        return sh == _selectedShiftFilter;
      }).toList();
    }

    if (_selectedStatusFilter == 'NOT_IN_VOUCHER') {
      filtered = filtered.where((it) {
        if (it == _activeEditingItem) return true;
        final s = _validationCache[it];
        return s != null && s.contains('Not in Voucher');
      }).toList();
    } else if (_selectedStatusFilter == 'UNMATCHED') {
      filtered = filtered.where((it) {
        if (it == _activeEditingItem) return true;
        return _validationCache[it] != null;
      }).toList();
    } else if (_selectedStatusFilter == 'VALID') {
      filtered = filtered.where((it) {
        if (it == _activeEditingItem) return true;
        return _validationCache[it] == null;
      }).toList();
    } else if (_selectedStatusFilter == 'AI_DOUBTS') {
      filtered = filtered.where((it) {
        if (it == _activeEditingItem) return true;
        return it.aiDoubt != null && it.aiDoubt!.isNotEmpty;
      }).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered.where((it) {
        if (it == _activeEditingItem) return true;
        return it.ticketNo.toLowerCase().contains(q) ||
            it.series.toLowerCase().contains(q) ||
            (it.targetDate != null && it.targetDate!.contains(q));
      }).toList();
    }

    return filtered;
  }

  void _handleRowTap(int idx, GeminiScannedItem item) {
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    setState(() {
      if (isShift && _lastSelectedIdx != null) {
        final displayed = _displayedItems;
        final start = _lastSelectedIdx! < idx ? _lastSelectedIdx! : idx;
        final end = _lastSelectedIdx! > idx ? _lastSelectedIdx! : idx;
        for (int i = start; i <= end && i < displayed.length; i++) {
          _selectedItems.add(displayed[i]);
        }
      } else {
        if (_selectedItems.contains(item)) {
          _selectedItems.remove(item);
        } else {
          _selectedItems.add(item);
        }
        _lastSelectedIdx = idx;
      }
    });
  }

  void _toggleSelectAll() {
    setState(() {
      final displayed = _displayedItems;
      if (_selectedItems.containsAll(displayed) && _selectedItems.isNotEmpty) {
        _selectedItems.removeAll(displayed);
      } else {
        _selectedItems.addAll(displayed);
      }
    });
  }

  void _applySeriesToSelected(String series) {
    if (_selectedItems.isEmpty) return;
    final clean = series.trim().toUpperCase();
    if (clean.isEmpty) return;
    setState(() {
      for (final it in _selectedItems) {
        it.series = clean;
      }
      _recalculateAllPrices();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ Set Series $clean on ${_selectedItems.length} selected items'),
        backgroundColor: const Color(0xFF166534),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _applyDateToSelected() async {
    if (_selectedItems.isEmpty) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.activeDate,
      firstDate: DateTime(1970),
      lastDate: DateTime(2999),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF3B82F6),
            surface: Color(0xFF1E293B),
          ),
          dialogTheme: const DialogThemeData(
            backgroundColor: Color(0xFF0F172A),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      final formatted = DateFormat('yyyy-MM-dd').format(picked);
      setState(() {
        for (final it in _selectedItems) {
          it.targetDate = formatted;
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Updated Date to $formatted for ${_selectedItems.length} items'),
            backgroundColor: const Color(0xFF166534),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _deleteSelectedItems() {
    if (_selectedItems.isEmpty) return;
    final count = _selectedItems.length;
    setState(() {
      _items.removeWhere((it) => _selectedItems.contains(it));
      _selectedItems.clear();
      _lastSelectedIdx = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🗑️ Deleted $count selected items'),
        backgroundColor: const Color(0xFF991B1B),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _parseAndCalculateItem(GeminiScannedItem it) {
    final val = it.ticketNo;
    if (val.contains('-')) {
      final parts = val.split('-');
      it.fromTicket = parts.first.trim();
      it.toTicket = parts.last.trim();
      final f = int.tryParse(it.fromTicket);
      final t = int.tryParse(it.toTicket);
      if (f != null && t != null && t >= f) {
        it.quantity = (t - f) + 1;
      } else {
        it.quantity = 1;
      }
    } else {
      it.fromTicket = val.trim();
      it.toTicket = val.trim();
      it.quantity = 1;
    }
    final rate = _getPriceForSeries(it.series);
    it.amount = rate * it.quantity;
    _refreshSingleItemValidation(it);
  }

  void _multiCursorBackspace() {
    if (_selectedItems.isEmpty) return;
    setState(() {
      for (final it in _selectedItems) {
        final text = it.ticketNo;
        final cursorIdx = text.length - _multiCursorOffsetFromEnd;
        if (cursorIdx > 0 && cursorIdx <= text.length) {
          final updated = text.substring(0, cursorIdx - 1) + text.substring(cursorIdx);
          it.ticketNo = updated;
          _parseAndCalculateItem(it);
        }
      }
    });
  }

  void _multiCursorDelete() {
    if (_selectedItems.isEmpty) return;
    setState(() {
      for (final it in _selectedItems) {
        final text = it.ticketNo;
        final cursorIdx = text.length - _multiCursorOffsetFromEnd;
        if (cursorIdx >= 0 && cursorIdx < text.length) {
          final updated = text.substring(0, cursorIdx) + text.substring(cursorIdx + 1);
          it.ticketNo = updated;
          _parseAndCalculateItem(it);
        }
      }
      if (_multiCursorOffsetFromEnd > 0) {
        _multiCursorOffsetFromEnd--;
      }
    });
  }

  void _multiCursorInsert(String char) {
    if (_selectedItems.isEmpty) return;
    setState(() {
      for (final it in _selectedItems) {
        final text = it.ticketNo;
        int cursorIdx = text.length - _multiCursorOffsetFromEnd;
        if (cursorIdx < 0) cursorIdx = 0;
        if (cursorIdx > text.length) cursorIdx = text.length;

        final updated = text.substring(0, cursorIdx) + char + text.substring(cursorIdx);
        it.ticketNo = updated;
        _parseAndCalculateItem(it);
      }
    });
  }

  void _addAdjacentRowToMultiCursor(int direction) {
    final displayed = _displayedItems;
    if (displayed.isEmpty) return;

    setState(() {
      if (_lastSelectedIdx == null) {
        _lastSelectedIdx = 0;
        _selectedItems.add(displayed[0]);
      } else {
        final nextIdx = (_lastSelectedIdx! + direction).clamp(0, displayed.length - 1);
        _selectedItems.add(displayed[nextIdx]);
        _lastSelectedIdx = nextIdx;
      }
    });
  }

  String _applyStringDelta({
    required String oldSource,
    required String newSource,
    required String oldTarget,
  }) {
    if (oldSource == newSource) return oldTarget;

    int prefixLen = 0;
    while (prefixLen < oldSource.length &&
        prefixLen < newSource.length &&
        oldSource[prefixLen] == newSource[prefixLen]) {
      prefixLen++;
    }

    int suffixLen = 0;
    while (suffixLen < (oldSource.length - prefixLen) &&
        suffixLen < (newSource.length - prefixLen) &&
        oldSource[oldSource.length - 1 - suffixLen] == newSource[newSource.length - 1 - suffixLen]) {
      suffixLen++;
    }

    final insertedPart = newSource.substring(prefixLen, newSource.length - suffixLen);
    final deletedLen = (oldSource.length - suffixLen) - prefixLen;

    if (oldTarget.length >= suffixLen + deletedLen) {
      final targetDeleteStart = oldTarget.length - suffixLen - deletedLen;
      final before = oldTarget.substring(0, targetDeleteStart);
      final after = oldTarget.substring(oldTarget.length - suffixLen);
      return '$before$insertedPart$after';
    } else if (oldTarget.length >= prefixLen + deletedLen) {
      final before = oldTarget.substring(0, prefixLen);
      final after = oldTarget.substring(prefixLen + deletedLen);
      return '$before$insertedPart$after';
    } else {
      return '$oldTarget$insertedPart';
    }
  }

  void _handleMultiCursorSync(GeminiScannedItem sourceItem, String oldVal, String newVal, String field) {
    if (!_multiCursorSyncEnabled || _selectedItems.length <= 1) return;
    if (!_selectedItems.contains(sourceItem)) return;

    for (final other in _selectedItems) {
      if (other == sourceItem) continue;
      if (field == 'series') {
        other.series = newVal.trim().toUpperCase();
        final rate = _getPriceForSeries(other.series);
        other.amount = rate * other.quantity;
      } else if (field == 'ticket') {
        final updatedTicket = _applyStringDelta(
          oldSource: oldVal,
          newSource: newVal,
          oldTarget: other.ticketNo,
        );

        other.ticketNo = updatedTicket;
        _parseAndCalculateItem(other);
      }
      _refreshSingleItemValidation(other);
    }
    setState(() {});
  }

  void _executeFindReplace({bool selectedOnly = true}) {
    final find = _findCtrl.text;
    final replace = _replaceCtrl.text;
    if (find.isEmpty) return;

    final targetList = selectedOnly && _selectedItems.isNotEmpty ? _selectedItems.toList() : _items;
    int replacedCount = 0;
    setState(() {
      for (final it in targetList) {
        bool changed = false;
        if (it.ticketNo.contains(find)) {
          final updated = it.ticketNo.replaceAll(find, replace);
          it.ticketNo = updated;
          if (updated.contains('-')) {
            final p = updated.split('-');
            it.fromTicket = p.first.trim();
            it.toTicket = p.last.trim();
            final f = int.tryParse(it.fromTicket);
            final t = int.tryParse(it.toTicket);
            it.quantity = (f != null && t != null && t >= f) ? (t - f) + 1 : 1;
          } else {
            it.fromTicket = updated.trim();
            it.toTicket = updated.trim();
            it.quantity = 1;
          }
          final rate = _getPriceForSeries(it.series);
          it.amount = rate * it.quantity;
          changed = true;
        }
        if (it.series.contains(find)) {
          it.series = it.series.replaceAll(find, replace).trim().toUpperCase();
          final rate = _getPriceForSeries(it.series);
          it.amount = rate * it.quantity;
          changed = true;
        }
        if (changed) {
          replacedCount++;
          _refreshSingleItemValidation(it);
        }
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🔍 Replaced in $replacedCount items!'),
        backgroundColor: const Color(0xFF166534),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _openMultiLineEditorDialog() {
    final targetItems = _selectedItems.isNotEmpty ? _selectedItems.toList() : _items;
    if (targetItems.isEmpty) return;

    final initialText = targetItems.map((e) => e.ticketNo).join('\n');
    final ctrl = TextEditingController(text: initialText);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFF38BDF8), width: 1.5),
          ),
          title: Row(
            children: [
              const Icon(Icons.edit_note_rounded, color: Color(0xFF38BDF8), size: 22),
              const SizedBox(width: 8),
              Text(
                'Multi-Line Batch Editor (${targetItems.length} Lines)',
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white70, size: 18),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Edit lines simultaneously. Each line corresponds to one row in the table.',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                ),
                const SizedBox(height: 10),
                Container(
                  height: 220,
                  decoration: BoxDecoration(
                    color: const Color(0xFF020617),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: TextField(
                    controller: ctrl,
                    maxLines: null,
                    expands: true,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: Color(0xFF38BDF8),
                      height: 1.4,
                      letterSpacing: 0.5,
                    ),
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.all(12),
                      border: InputBorder.none,
                      hintText: 'Enter ticket numbers or ranges line by line...',
                      hintStyle: TextStyle(color: Color(0xFF475569)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        final lines = ctrl.text.split('\n');
                        final fixed = lines.map((l) {
                          final p = l.split('-');
                          if (p.length == 2) {
                            final f = p[0].trim();
                            final t = p[1].trim();
                            if (t.length == 7 && f.length == 5) {
                              return '$f - ${f.substring(0, 2)}${t.substring(4)}';
                            }
                          }
                          return l;
                        }).join('\n');
                        ctrl.text = fixed;
                        setDlgState(() {});
                      },
                      icon: const Icon(Icons.auto_fix_high_rounded, size: 14, color: Color(0xFFFBBF24)),
                      label: const Text('Auto-Trim 7-Digits', style: TextStyle(fontSize: 11, color: Color(0xFFFBBF24))),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                final newLines = ctrl.text.split('\n');
                setState(() {
                  for (int i = 0; i < targetItems.length && i < newLines.length; i++) {
                    final it = targetItems[i];
                    final line = newLines[i].trim();
                    if (line.isEmpty) continue;
                    it.ticketNo = line;
                    if (line.contains('-')) {
                      final parts = line.split('-');
                      it.fromTicket = parts.first.trim();
                      it.toTicket = parts.last.trim();
                      final f = int.tryParse(it.fromTicket);
                      final t = int.tryParse(it.toTicket);
                      it.quantity = (f != null && t != null && t >= f) ? (t - f) + 1 : 1;
                    } else {
                      it.fromTicket = line;
                      it.toTicket = line;
                      it.quantity = 1;
                    }
                    final rate = _getPriceForSeries(it.series);
                    it.amount = rate * it.quantity;
                    _refreshSingleItemValidation(it);
                  }
                });
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('✅ Updated ${targetItems.length} rows from Multi-Line editor!'),
                    backgroundColor: const Color(0xFF166534),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              child: const Text('Apply to Rows', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _autoFixMalformedRanges() {
    final targetList = _selectedItems.isNotEmpty ? _selectedItems.toList() : _items;
    int fixedCount = 0;
    setState(() {
      final List<GeminiScannedItem> newSplitItems = [];
      for (final it in targetList) {
        final parts = it.ticketNo.split('-');
        if (parts.length == 2) {
          final fStr = parts[0].trim();
          final tStr = parts[1].trim();
          if (tStr.length == 7 && fStr.length == 5) {
            final prefix1 = fStr.substring(0, 2);
            final prefix2 = tStr.substring(2, 4);
            final last3 = tStr.substring(4);

            final newTo1 = '$prefix1$last3';
            it.ticketNo = '$fStr - $newTo1';
            it.fromTicket = fStr;
            it.toTicket = newTo1;
            final fNum = int.tryParse(fStr) ?? 0;
            final tNum = int.tryParse(newTo1) ?? fNum;
            it.quantity = (tNum >= fNum) ? (tNum - fNum) + 1 : 50;
            final rate = _getPriceForSeries(it.series);
            it.amount = rate * it.quantity;
            fixedCount++;

            if (int.tryParse(prefix2) != null) {
              final start3 = fStr.substring(2);
              final newFrom2 = '$prefix2$start3';
              final newTo2 = '$prefix2$last3';
              final clone = GeminiScannedItem(
                series: it.series,
                ticketNo: '$newFrom2 - $newTo2',
                fromTicket: newFrom2,
                toTicket: newTo2,
                quantity: it.quantity,
                amount: it.amount,
                sellerName: it.sellerName,
                targetDate: it.targetDate,
                drawShift: it.drawShift,
              );
              newSplitItems.add(clone);
            }
          } else if (tStr.length > 5 && fStr.length == 5) {
            final prefix = fStr.substring(0, 2);
            final last3 = tStr.substring(tStr.length - 3);
            final newTo = '$prefix$last3';
            it.ticketNo = '$fStr - $newTo';
            it.fromTicket = fStr;
            it.toTicket = newTo;
            final fNum = int.tryParse(fStr) ?? 0;
            final tNum = int.tryParse(newTo) ?? fNum;
            it.quantity = (tNum >= fNum) ? (tNum - fNum) + 1 : 1;
            final rate = _getPriceForSeries(it.series);
            it.amount = rate * it.quantity;
            fixedCount++;
          }
        }
      }
      if (newSplitItems.isNotEmpty) {
        _items.addAll(newSplitItems);
      }
      _refreshValidationCache();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✂️ Auto-fixed $fixedCount ranges to valid 50-ticket ranges!'),
        backgroundColor: const Color(0xFF166534),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Widget _buildReviewBulkActionBar(Color primaryColor) {
    if (_selectedItems.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(6, 4, 6, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1B4B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.indigoAccent.withAlpha(180), width: 1.5),
        boxShadow: [
          BoxShadow(color: Colors.indigo.withAlpha(100), blurRadius: 12, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.indigoAccent,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      '${_selectedItems.length} Selected (Shift+Click Range)',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('Set Series:', style: TextStyle(color: Colors.grey, fontSize: 10.5, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 4),
                  ...['12', '20', '24', '36', '40', '60'].map((s) => Padding(
                    padding: const EdgeInsets.only(right: 3),
                    child: InkWell(
                      onTap: () => _applySeriesToSelected(s),
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFF818CF8)),
                        ),
                        child: Text('Ser $s', style: const TextStyle(color: Color(0xFFC7D2FE), fontWeight: FontWeight.bold, fontSize: 10)),
                      ),
                    ),
                  )),
                  const SizedBox(width: 6),
                  // Set Date Button
                  OutlinedButton.icon(
                    onPressed: _applyDateToSelected,
                    icon: const Icon(Icons.calendar_month, size: 12, color: Color(0xFFFBBF24)),
                    label: const Text('Set Date', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFFFBBF24))),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFFBBF24)),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: const Size(50, 26),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Set Shift Menu Button
                  PopupMenuButton<String>(
                    tooltip: 'Set Shift for Selected Items',
                    onSelected: (selectedShift) {
                      setState(() {
                        for (final it in _selectedItems) {
                          it.drawShift = selectedShift;
                          _refreshSingleItemValidation(it);
                        }
                      });
                    },
                    color: const Color(0xFF1E293B),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    itemBuilder: (ctx) => const [
                      PopupMenuItem(value: 'Dear 1 PM', child: Text('Dear 1 PM', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 12))),
                      PopupMenuItem(value: 'Dear 6 PM', child: Text('Dear 6 PM', style: TextStyle(color: Color(0xFFA78BFA), fontWeight: FontWeight.bold, fontSize: 12))),
                      PopupMenuItem(value: 'Dear 8 PM', child: Text('Dear 8 PM', style: TextStyle(color: Color(0xFFF472B6), fontWeight: FontWeight.bold, fontSize: 12))),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFFA78BFA)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.schedule_rounded, size: 12, color: Color(0xFFA78BFA)),
                          SizedBox(width: 4),
                          Text('Set Shift ▾', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFFA78BFA))),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Multi-Line Edit Button (Ctrl+M)
                  ElevatedButton.icon(
                    onPressed: _openMultiLineEditorDialog,
                    icon: const Icon(Icons.edit_note_rounded, size: 13, color: Colors.white),
                    label: const Text('📝 Multi-Line', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: const Size(50, 26),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                        side: const BorderSide(color: Color(0xFF60A5FA)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Multi-Cursor Sync Toggle Button
                  InkWell(
                    onTap: () {
                      setState(() {
                        _multiCursorSyncEnabled = !_multiCursorSyncEnabled;
                      });
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _multiCursorSyncEnabled ? const Color(0xFF0369A1) : const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: _multiCursorSyncEnabled ? const Color(0xFF38BDF8) : const Color(0xFF475569)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.bolt_rounded, size: 13, color: _multiCursorSyncEnabled ? Colors.white : Colors.grey.shade400),
                          const SizedBox(width: 4),
                          Text(
                            _multiCursorSyncEnabled ? '⚡ Cursor: ON' : '⚡ Cursor: OFF',
                            style: TextStyle(
                              color: _multiCursorSyncEnabled ? Colors.white : Colors.grey.shade400,
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Auto-Fix 7-Digit / Bad Ranges Button
                  ElevatedButton.icon(
                    onPressed: _autoFixMalformedRanges,
                    icon: const Icon(Icons.auto_fix_high_rounded, size: 12, color: Color(0xFFFBBF24)),
                    label: const Text('✂️ Fix Ranges', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFFFDE68A))),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF78350F),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: const Size(50, 26),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                        side: const BorderSide(color: Color(0xFFFBBF24)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Find & Replace Button (Ctrl+H)
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _showFindReplaceBar = !_showFindReplaceBar),
                    icon: const Icon(Icons.find_replace_rounded, size: 12, color: Color(0xFF38BDF8)),
                    label: Text(_showFindReplaceBar ? 'Close Find' : 'Find/Replace', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF38BDF8))),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF38BDF8)),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: const Size(50, 26),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Delete Button
                  ElevatedButton.icon(
                    onPressed: _deleteSelectedItems,
                    icon: const Icon(Icons.delete_outline, size: 12),
                    label: const Text('Delete', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: const Size(50, 26),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Clear Selection
          IconButton(
            tooltip: 'Deselect All',
            icon: const Icon(Icons.close, size: 14, color: Colors.white70),
            onPressed: () => setState(() {
              _selectedItems.clear();
              _lastSelectedIdx = null;
            }),
          ),
        ],
      ),
    );
  }

  void _applySeriesToAllMissing(String newSeries) {
    if (newSeries.trim().isEmpty) return;
    setState(() {
      final clean = newSeries.trim().toUpperCase();
      final defaultAmt = _getPriceForSeries(clean);
      for (final item in _items) {
        if (item.series == '?' || item.series.trim().isEmpty) {
          item.series = clean;
          item.amount = defaultAmt;
        }
      }
      _recalculateAllPrices();
    });
  }

  void _applySeriesToAll(String newSeries) {
    if (newSeries.trim().isEmpty) return;
    setState(() {
      final clean = newSeries.trim().toUpperCase();
      final defaultAmt = _getPriceForSeries(clean);
      for (final item in _items) {
        item.series = clean;
        item.amount = defaultAmt;
      }
      _recalculateAllPrices();
    });
  }

  String? _getItemValidationStatus(GeminiScannedItem item) {
    return _validationCache.containsKey(item)
        ? _validationCache[item]
        : _computeItemValidationStatus(item);
  }

  String? _computeItemValidationStatus(GeminiScannedItem item) {
    final from = item.fromTicket.trim();
    final to = item.toTicket.trim();
    if (from.length != 5 || to.length != 5) return 'Invalid Number';
    final cleanSer = item.series.trim().toUpperCase();
    if (cleanSer == '?' || cleanSer.isEmpty) return 'Missing Series';

    final partyName = _partyCtrl.text.trim();
    final partyLower = partyName.toLowerCase();
    final cleanP2 = partyLower.replaceAll(RegExp(r'[^a-z0-9]'), '');

    final dateStr = DateFormat('yyyy-MM-dd').format(_activeDate);
    final rawItemDate = (item.targetDate != null && item.targetDate!.isNotEmpty) ? item.targetDate! : dateStr;
    final itemDate = _normalizeDateToYmd(rawItemDate);
    final itemMd = _extractMonthDay(rawItemDate);

    final rawItemShift = (item.drawShift != null && item.drawShift!.isNotEmpty) ? item.drawShift! : _selectedShift;
    final itemCanonicalShift = _canonicalShift(rawItemShift);

    final startI = int.tryParse(from);
    final endI = int.tryParse(to);
    if (startI == null || endI == null || endI < startI) return 'Invalid Range';

    final serNumItem = cleanSer.replaceAll(RegExp(r'\D'), '');

    if (widget.mode == StockScanMode.voucher) {
      for (final v in _fastVouchers) {
        final normVDate = _normalizeDateToYmd(v.dateClean);
        final vMd = _extractMonthDay(v.dateClean);
        final matchesDate = normVDate == itemDate || vMd == itemMd || v.dateClean == rawItemDate;
        if (matchesDate && (v.seriesUpper == cleanSer || (serNumItem.isNotEmpty && v.seriesNum == serNumItem))) {
          final vCanonicalShift = _canonicalShift(v.shiftLower);
          final matchesShift = itemCanonicalShift == 'all' ||
              vCanonicalShift == 'all' ||
              vCanonicalShift == itemCanonicalShift;
          final cleanP1 = v.partyLower.replaceAll(RegExp(r'[^a-z0-9]'), '');
          final isSameParty = partyName.isNotEmpty &&
              partyName != 'Walk-in Party' &&
              (cleanP1 == cleanP2 ||
               v.partyLower == partyLower ||
               v.partyLower.contains(partyLower) ||
               partyLower.contains(v.partyLower));
          if (matchesShift && isSameParty && startI <= v.end && endI >= v.start) {
            return 'Already in Voucher (${v.partyName})';
          }
        }
      }
    } else {
      // Unsold Mode: strictly verify that ticket was actually issued in a voucher!
      bool wasIssuedToThisParty = false;
      String? issuedToOtherParty;
      bool foundInAnyVoucher = false;

      for (final v in _fastVouchers) {
        // 1. Date matching: exact date or MM-DD match
        final normVDate = _normalizeDateToYmd(v.dateClean);
        final vMd = _extractMonthDay(v.dateClean);
        final matchesDate = normVDate == itemDate || vMd == itemMd || v.dateClean == rawItemDate;
        if (!matchesDate) continue;

        // 2. Shift matching: canonical 1, 6, 8 or 'all'
        final vCanonicalShift = _canonicalShift(v.shiftLower);
        final matchesShift = itemCanonicalShift == 'all' ||
            vCanonicalShift == 'all' ||
            vCanonicalShift == itemCanonicalShift;
        if (!matchesShift) continue;

        // 3. Series matching:
        final matchesSeries = v.seriesUpper == cleanSer || (serNumItem.isNotEmpty && v.seriesNum == serNumItem);
        if (!matchesSeries) continue;

        // 4. Ticket Range matching:
        if (startI >= v.start && endI <= v.end) {
          foundInAnyVoucher = true;
          final cleanP1 = v.partyLower.replaceAll(RegExp(r'[^a-z0-9]'), '');
          final cleanD1 = v.dealerLower.replaceAll(RegExp(r'[^a-z0-9]'), '');
          final isThisParty = partyName.isNotEmpty &&
              partyName != 'Walk-in Party' &&
              (cleanP1 == cleanP2 ||
               cleanP1.contains(cleanP2) ||
               cleanP2.contains(cleanP1) ||
               v.partyLower == partyLower ||
               v.partyLower.contains(partyLower) ||
               partyLower.contains(v.partyLower) ||
               // 🏢 DEALER HIERARCHY MATCH: If Unsold is submitted under the Dealer's name!
               cleanD1 == cleanP2 ||
               cleanD1.contains(cleanP2) ||
               cleanP2.contains(cleanD1) ||
               v.dealerLower == partyLower);

          if (isThisParty) {
            wasIssuedToThisParty = true;
            break;
          } else {
            issuedToOtherParty = v.partyName;
          }
        }
      }

      if (partyName.isNotEmpty && partyName != 'Walk-in Party') {
        if (!wasIssuedToThisParty) {
          if (issuedToOtherParty != null && issuedToOtherParty.isNotEmpty) {
            return 'Issued to $issuedToOtherParty';
          }
          return 'Not in Voucher ($partyName)';
        }
      } else {
        if (!foundInAnyVoucher) {
          return 'Not in Voucher';
        }
      }

      // 5. 🚫 BLOCK ALL DUPLICATE UNSOLD RETURNS (Regardless of party variations)
      final unsoldSource = _allUnsold.isNotEmpty
          ? _allUnsold
          : ref.read(unsoldViewModelProvider).unsoldList;
      for (final u in unsoldSource) {
        final normUDate = _normalizeDateToYmd(u.date);
        final uMd = _extractMonthDay(u.date);
        final matchesDate = normUDate == itemDate || uMd == itemMd || u.date == rawItemDate;
        if (!matchesDate) continue;

        final uCanonicalShift = _canonicalShift(u.drawShift);
        final matchesShift = itemCanonicalShift == 'all' ||
            uCanonicalShift == 'all' ||
            uCanonicalShift == itemCanonicalShift;
        if (!matchesShift) continue;

        final uSer = u.series.trim().toUpperCase();
        final uSerNum = uSer.replaceAll(RegExp(r'\D'), '');
        final matchesSeries = uSer == cleanSer || (serNumItem.isNotEmpty && uSerNum == serNumItem);
        if (!matchesSeries) continue;

        final startU = int.tryParse(u.fromTicket);
        final endU = int.tryParse(u.toTicket);
        if (startU != null && endU != null) {
          if (startI <= endU && endI >= startU) {
            return 'Already Returned (${u.partyName})';
          }
        }
      }
    }

    return null; // OK
  }

  void _addManualTicket() {
    final tkt = _manualTicketCtrl.text.trim();
    if (tkt.isEmpty) {
      _manualTicketFocusNode.requestFocus();
      return;
    }

    final ser = _manualSeriesCtrl.text.trim().isNotEmpty
        ? _manualSeriesCtrl.text.trim().toUpperCase()
        : '12';

    // ⚡ SMART PARCHA PARSER — supports all entry formats:
    // 1. "52385"         → single ticket
    // 2. "52150-52199"   → full 5-digit range
    // 3. "52150-99"      → abbreviated TO (first 3 of FROM + '99' = 52199)
    // 4. "52150-99-50"   → parcha format (IGNORE written qty '50', calc from range)
    // Quantity is ALWAYS calculated from (toTicket - fromTicket + 1).

    String fromTicket = '';
    String toTicket = '';

    // Format 4 & 3: AAAAA-BB-CC or AAAAA-BB (2-digit abbreviated TO)
    final parchaMatch = RegExp(r'^(\d{5})-(\d{2})(?:-\d+)?$').firstMatch(tkt);
    if (parchaMatch != null) {
      fromTicket = parchaMatch.group(1)!;
      final prefix3 = fromTicket.substring(0, 3);
      final last2 = parchaMatch.group(2)!;
      toTicket = '$prefix3$last2';
    }

    // Format 2: AAAAA-BBBBB (two full 5-digit numbers)
    if (fromTicket.isEmpty) {
      final range5Match = RegExp(r'^(\d{5})[-~](\d{5})$').firstMatch(tkt);
      if (range5Match != null) {
        fromTicket = range5Match.group(1)!;
        toTicket = range5Match.group(2)!;
      }
    }

    // Format 1: single 5-digit number
    if (fromTicket.isEmpty && RegExp(r'^\d{5}$').hasMatch(tkt)) {
      fromTicket = tkt;
      toTicket = tkt;
    }

    if (fromTicket.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Format: 52385  या  52150-99  या  52150-99-10  या  52150-52199'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      _manualTicketFocusNode.requestFocus();
      return;
    }

    // ALWAYS calculate qty from ticket range (IGNORE any written quantity)
    final fNum = int.tryParse(fromTicket) ?? 0;
    final tNum = int.tryParse(toTicket) ?? fNum;
    final qty = (tNum >= fNum) ? (tNum - fNum) + 1 : 1;
    final rate = _getPriceForSeries(ser);
    final amt = rate * qty;

    setState(() {
      final newItem = GeminiScannedItem(
        series: ser,
        ticketNo: qty > 1 ? '$fromTicket - $toTicket' : fromTicket,
        fromTicket: fromTicket,
        toTicket: toTicket,
        amount: amt,
        quantity: qty,
        sellerName: _partyCtrl.text.trim(),
        photoIndex: _currentImageIndex,
      );
      _items.add(newItem);
      _refreshValidationCache();
      _manualTicketCtrl.clear();
      _manualTicketFocusNode.requestFocus();
    });
  }

  String _sanitizeTargetDate(String? rawDate, String fallbackDate) {
    if (rawDate == null || rawDate.trim().isEmpty) return fallbackDate;
    final clean = rawDate.trim().replaceAll(RegExp(r'[^\d\/\-]'), '');
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(clean)) return clean;
    final dmy = RegExp(r'^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{4})$').firstMatch(clean);
    if (dmy != null) {
      return '${dmy.group(3)}-${dmy.group(2)!.padLeft(2, '0')}-${dmy.group(1)!.padLeft(2, '0')}';
    }
    final dm = RegExp(r'^(\d{1,2})[\/\-](\d{1,2})[\/\-]?$').firstMatch(clean);
    if (dm != null) {
      final now = DateTime.now();
      return '${now.year}-${dm.group(2)!.padLeft(2, '0')}-${dm.group(1)!.padLeft(2, '0')}';
    }
    final dOnly = RegExp(r'^(\d{1,2})[\/\-]?$').firstMatch(clean);
    if (dOnly != null) {
      final d = int.tryParse(dOnly.group(1)!);
      if (d != null && d >= 1 && d <= 31) {
        final now = DateTime.now();
        return '${now.year}-${now.month.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
      }
    }
    return fallbackDate;
  }

  Future<void> _saveAllParsedEntries() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️  No valid tickets found to save!'), backgroundColor: Colors.orangeAccent),
      );
      return;
    }

    final dateStr = DateFormat('yyyy-MM-dd').format(_activeDate);
    final partyName = _partyCtrl.text.trim().isNotEmpty ? _partyCtrl.text.trim() : widget.defaultParty;

    // Check for internal duplicates within the batch and already returned tickets in DB
    final seen = <String>{};
    final validItems = <GeminiScannedItem>[];
    final invalidErrors = <String>[];
    int duplicateSkippedCount = 0;

    for (final it in _items) {
      final itemDate = _sanitizeTargetDate(it.targetDate, dateStr);
      final normDate = _normalizeDateToYmd(itemDate);
      final canShift = _canonicalShift(it.drawShift ?? _selectedShift);
      final key = widget.mode == StockScanMode.unsold
          ? '${normDate}_${canShift}_${it.series.toUpperCase()}_${it.ticketNo}'
          : '${partyName.trim().toLowerCase()}_${normDate}_${canShift}_${it.series.toUpperCase()}_${it.ticketNo}';

      if (seen.contains(key)) {
        invalidErrors.add('Duplicate in scan: Ser ${it.series} #${it.ticketNo} ($itemDate)');
        duplicateSkippedCount++;
        continue;
      }
      seen.add(key);

      // Check against existing unsold tickets in SQLite to block duplicate unsold returns
      if (widget.mode == StockScanMode.unsold) {
        final status = _validationCache[it] ?? _computeItemValidationStatus(it);
        if (status != null && (status.contains('Already Returned') || status.contains('Already in Voucher') || status.contains('Duplicate'))) {
          invalidErrors.add('Already in database: Ser ${it.series} #${it.ticketNo} ($status)');
          duplicateSkippedCount++;
          continue;
        }
      }

      validItems.add(it);
    }

    if (validItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️  All items were duplicates or already processed! Nothing to save.'), backgroundColor: Colors.orangeAccent),
      );
      return;
    }

    setState(() => _isSaving = true);
    final now = DateTime.now();

    try {
      if (widget.mode == StockScanMode.voucher) {
        final effectiveDealer = _selectedDealer ?? partyName;
        final effectiveParty = _selectedSubSeller ?? effectiveDealer;
        final List<VoucherModel> vouchersToSave = [];
        for (int i = 0; i < validItems.length; i++) {
          final it = validItems[i];
          final voucherNo = 'VOUCH-${DateFormat('HHmmss').format(now)}-$i';
          final rate = it.amount / (it.quantity > 0 ? it.quantity : 1);
          final fTkt = it.fromTicket.isNotEmpty ? it.fromTicket : (it.ticketNo.contains('-') ? it.ticketNo.split('-').first.trim() : it.ticketNo);
          final tTkt = it.toTicket.isNotEmpty ? it.toTicket : (it.ticketNo.contains('-') ? it.ticketNo.split('-').last.trim() : it.ticketNo);
          final entryDate = _sanitizeTargetDate(it.targetDate, dateStr);
          final itemShift = (it.drawShift != null && it.drawShift!.isNotEmpty) ? it.drawShift! : _selectedShift;
          vouchersToSave.add(
            VoucherModel(
              id: 'vouch_${now.microsecondsSinceEpoch}_$i',
              voucherNo: voucherNo,
              date: entryDate,
              drawShift: itemShift,
              partyName: effectiveParty,
              dealerName: effectiveDealer,
              series: it.series.isNotEmpty ? it.series : '12',
              fromTicket: fTkt,
              toTicket: tTkt,
              totalQty: it.quantity > 0 ? it.quantity : 1,
              pricePerTicket: rate,
              totalAmount: it.amount,
              createdAt: now,
            ),
          );
        }
        await ref.read(voucherViewModelProvider.notifier).addVouchersBatch(vouchersToSave);
      } else {
        final effectiveDealer = _selectedDealer ?? partyName;
        final List<UnsoldModel> unsoldToSave = [];
        for (int i = 0; i < validItems.length; i++) {
          final it = validItems[i];
          final returnNo = 'RET-${DateFormat('HHmmss').format(now)}-$i';
          final rate = it.amount / (it.quantity > 0 ? it.quantity : 1);
          final fTkt = it.fromTicket.isNotEmpty ? it.fromTicket : (it.ticketNo.contains('-') ? it.ticketNo.split('-').first.trim() : it.ticketNo);
          final tTkt = it.toTicket.isNotEmpty ? it.toTicket : (it.ticketNo.contains('-') ? it.ticketNo.split('-').last.trim() : it.ticketNo);
          final entryDate = _sanitizeTargetDate(it.targetDate, dateStr);
          final itemShift = (it.drawShift != null && it.drawShift!.isNotEmpty) ? it.drawShift! : _selectedShift;

          // 🌳 SMART BRANCH RESOLUTION FOR UNSOLD:
          // Match ticket range to the specific Sub-Seller originally issued these tickets
          String itemParty = effectiveDealer;
          final fNum = int.tryParse(fTkt);
          final tNum = int.tryParse(tTkt) ?? fNum;
          if (fNum != null && tNum != null) {
            for (final v in _fastVouchers) {
              if (v.seriesUpper == it.series.trim().toUpperCase() &&
                  (v.dealerLower == effectiveDealer.toLowerCase() || v.partyLower == effectiveDealer.toLowerCase())) {
                if (fNum >= v.start && tNum <= v.end) {
                  itemParty = v.partyName;
                  break;
                }
              }
            }
          }

          unsoldToSave.add(
            UnsoldModel(
              id: 'unsold_${now.microsecondsSinceEpoch}_$i',
              returnNo: returnNo,
              date: entryDate,
              drawShift: itemShift,
              partyName: itemParty,
              dealerName: effectiveDealer,
              series: it.series.isNotEmpty ? it.series : '12',
              fromTicket: fTkt,
              toTicket: tTkt,
              totalQty: it.quantity > 0 ? it.quantity : 1,
              pricePerTicket: rate,
              totalAmount: it.amount,
              createdAt: now,
            ),
          );
        }
        await ref.read(unsoldViewModelProvider.notifier).addUnsoldBatch(unsoldToSave);
      }

      GeminiScannerService.instance.lastStockScanSession = null;

      if (mounted) {
        if (duplicateSkippedCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('ℹ️ $duplicateSkippedCount duplicate/already returned tickets were skipped!'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error saving entries: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _exportScannedEntries() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ No scanned items to export!'), backgroundColor: Colors.amber),
      );
      return;
    }

    try {
      final isVoucher = widget.mode == StockScanMode.voucher;
      final dateStr = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final defaultFileName = isVoucher ? 'voucher_scan_$dateStr.csv' : 'unsold_scan_$dateStr.csv';
      final partyName = _partyCtrl.text.trim().isNotEmpty ? _partyCtrl.text.trim() : widget.defaultParty;

      String? filePath = await FilePicker.platform.saveFile(
        dialogTitle: isVoucher ? 'Export Scanned Vouchers CSV' : 'Export Scanned Unsold CSV',
        fileName: defaultFileName,
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (filePath == null) {
        final docsDir = Platform.environment['USERPROFILE'] != null
            ? '${Platform.environment['USERPROFILE']}\\Documents'
            : Directory.systemTemp.path;
        filePath = '$docsDir\\$defaultFileName';
      }

      final buffer = StringBuffer();
      buffer.writeln('No,Date,Party/Seller,Series,Ticket Range,From Ticket,To Ticket,Quantity,Amount (Rs),Status');

      for (int i = 0; i < _items.length; i++) {
        final it = _items[i];
        final tDate = it.targetDate != null && it.targetDate!.isNotEmpty
            ? it.targetDate!
            : DateFormat('yyyy-MM-dd').format(widget.activeDate);
        final status = _getItemValidationStatus(it) ?? 'Valid';

        buffer.writeln(
          '${i + 1},"$tDate","$partyName","${it.series}","${it.ticketNo}","${it.fromTicket}","${it.toTicket}",${it.quantity},${it.amount.toStringAsFixed(2)},"$status"',
        );
      }

      final file = File(filePath);
      await file.writeAsString(buffer.toString());

      // Also copy to clipboard for quick pasting
      await Clipboard.setData(ClipboardData(text: buffer.toString()));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📊 Exported ${_items.length} records to: $filePath (Copied to Clipboard)'),
            backgroundColor: const Color(0xFF166534),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(sellerCustomerViewModelProvider);
    ref.listen<SellerCustomerState>(sellerCustomerViewModelProvider, (prev, next) {
      _loadDealersAndSellers();
    });

    final isVoucher = widget.mode == StockScanMode.voucher;
    final primaryColor = isVoucher ? const Color(0xFF3B82F6) : const Color(0xFFEF4444);
    final primaryGlow = isVoucher ? const Color(0xFF1D4ED8) : const Color(0xFFDC2626);
    final modeTitle = isVoucher ? 'AI VOUCHER PARCHA REVIEW' : 'AI UNSOLD PARCHA REVIEW';
    final dateStr = DateFormat('dd-MM-yyyy').format(_activeDate);
    final missingCount = _missingSeriesCount;
    final validCount = _validCount;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Focus(
        autofocus: false,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            final isAlt = HardwareKeyboard.instance.isAltPressed;
            final isCtrl = HardwareKeyboard.instance.isControlPressed;

            if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyM) {
              _openMultiLineEditorDialog();
              return KeyEventResult.handled;
            }

            if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyH) {
              setState(() => _showFindReplaceBar = !_showFindReplaceBar);
              return KeyEventResult.handled;
            }

            if ((isAlt || (isCtrl && isAlt)) && event.logicalKey == LogicalKeyboardKey.arrowDown) {
              _addAdjacentRowToMultiCursor(1);
              return KeyEventResult.handled;
            }

            if ((isAlt || (isCtrl && isAlt)) && event.logicalKey == LogicalKeyboardKey.arrowUp) {
              _addAdjacentRowToMultiCursor(-1);
              return KeyEventResult.handled;
            }

            if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyD) {
              _addAdjacentRowToMultiCursor(1);
              return KeyEventResult.handled;
            }

            // ⚡ Multi-Cursor direct keyboard editing (syncs across all selected rows):
            if (_multiCursorSyncEnabled && _selectedItems.length > 1) {
              if (event.logicalKey == LogicalKeyboardKey.backspace) {
                _multiCursorBackspace();
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.delete) {
                _multiCursorDelete();
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                setState(() {
                  _multiCursorOffsetFromEnd++;
                });
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                setState(() {
                  if (_multiCursorOffsetFromEnd > 0) _multiCursorOffsetFromEnd--;
                });
                return KeyEventResult.handled;
              }

              final char = event.character;
              if (char != null && char.isNotEmpty && !isCtrl && !isAlt && char.codeUnitAt(0) >= 32) {
                _multiCursorInsert(char);
                return KeyEventResult.handled;
              }
            }
          }
          return KeyEventResult.ignored;
        },
        child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF080C1A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: primaryColor.withAlpha(80), width: 1.5),
          boxShadow: [
            BoxShadow(color: primaryGlow.withAlpha(60), blurRadius: 60, spreadRadius: 0),
            BoxShadow(color: Colors.black.withAlpha(240), blurRadius: 30, spreadRadius: 10),
          ],
        ),
        child: Column(
          children: [
            // ── HEADER ────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [primaryColor.withAlpha(30), const Color(0xFF0F172A)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(bottom: BorderSide(color: primaryColor.withAlpha(40))),
              ),
              child: Row(
                children: [
                  // Icon Badge
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [primaryColor, primaryGlow]),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [BoxShadow(color: primaryColor.withAlpha(120), blurRadius: 12)],
                    ),
                    child: const Icon(Icons.document_scanner_rounded, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(modeTitle,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 13.5, color: Colors.white, letterSpacing: 0.8)),
                      const SizedBox(height: 3),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Interactive Shift Switcher Dropdown
                          Container(
                            height: 22,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: primaryColor.withAlpha(120)),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedShift,
                                dropdownColor: const Color(0xFF0F172A),
                                icon: Icon(Icons.arrow_drop_down, color: primaryColor, size: 14),
                                style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 10.5),
                                items: const [
                                  DropdownMenuItem(value: 'Dear 1 PM', child: Text('Dear 1 PM')),
                                  DropdownMenuItem(value: 'Dear 6 PM', child: Text('Dear 6 PM')),
                                  DropdownMenuItem(value: 'Dear 8 PM', child: Text('Dear 8 PM')),
                                ],
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() {
                                      _selectedShift = val;
                                      _refreshValidationCache();
                                    });
                                  }
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Clickable Interactive Date Button
                          InkWell(
                            onTap: _pickMainDate,
                            borderRadius: BorderRadius.circular(5),
                            child: Container(
                              height: 22,
                              padding: const EdgeInsets.symmetric(horizontal: 7),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: const Color(0xFFFBBF24).withAlpha(150)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.calendar_today_rounded, size: 10, color: Color(0xFFFBBF24)),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Date: $dateStr ✎',
                                    style: const TextStyle(color: Color(0xFFFBBF24), fontWeight: FontWeight.bold, fontSize: 10.5),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),

                  // Stats Pills
                  _statPill('${_items.length}', 'Ranges', const Color(0xFF334155), Colors.white70),
                  const SizedBox(width: 6),
                  _statPill('$_totalTickets', 'Tickets', const Color(0xFF1E3A5F), const Color(0xFF60A5FA)),
                  const SizedBox(width: 6),
                  if (_unmatchedCount > 0)
                    _statPill('$_unmatchedCount', 'Issues', const Color(0xFF450A0A), const Color(0xFFF87171)),
                  if (_unmatchedCount > 0) const SizedBox(width: 6),
                  _statPill('₹${_totalAmount >= 100000 ? '${(_totalAmount / 100000).toStringAsFixed(1)}L' : _totalAmount.toStringAsFixed(0)}',
                      'Value', const Color(0xFF1C1A05), const Color(0xFFFBBF24)),

                  const Spacer(),

                  // 🏢 1. Main Dealer Selector
                  Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _selectedDealer != null ? const Color(0xFFF59E0B) : Colors.redAccent.withAlpha(180),
                        width: 1.2,
                      ),
                    ),
                    child: InkWell(
                      onTap: () async {
                        final chosen = await SearchableDealerPickerDialog.show(
                          context: context,
                          dealers: _availableDealers,
                          dealerToSellersMap: _dealerToSellersMap,
                          selectedDealer: _selectedDealer,
                          title: 'Select Dealer (${_availableDealers.length})',
                          allowAllOption: false,
                        );
                        if (chosen != null) {
                          setState(() {
                            _selectedDealer = chosen;
                            _selectedSubSeller = null;
                            _partyCtrl.text = _selectedDealer!;
                            _refreshValidationCache();
                          });
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.workspace_premium_rounded, size: 14, color: Color(0xFFF59E0B)),
                          const SizedBox(width: 6),
                          Text(
                            _selectedDealer ?? 'Main Dealer * (${_availableDealers.length})',
                            style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 11.5, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.search_rounded, size: 14, color: Color(0xFFF59E0B)),
                        ],
                      ),
                    ),

                  ),
                  const SizedBox(width: 8),

                  // 👤 2. Sub-Seller Selector (ONLY IN VOUCHER MODE)
                  if (widget.mode == StockScanMode.voucher && _selectedDealer != null) ...[
                    Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF38BDF8), width: 1.2),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: (_dealerToSellersMap[_selectedDealer]?.contains(_selectedSubSeller) ?? false)
                              ? _selectedSubSeller
                              : 'MAIN_DEALER',
                          dropdownColor: const Color(0xFF1E293B),
                          items: [
                            DropdownMenuItem<String>(
                              value: 'MAIN_DEALER',
                              child: Text('👑 $_selectedDealer (Main Dealer)', style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                            ...(_dealerToSellersMap[_selectedDealer] ?? []).map((s) => DropdownMenuItem<String>(
                                  value: s,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.person, size: 13, color: Color(0xFF38BDF8)),
                                      const SizedBox(width: 5),
                                      Text(s, style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                )),
                          ],
                          onChanged: (val) {
                            setState(() {
                              if (val == 'MAIN_DEALER') {
                                _selectedSubSeller = null;
                                _partyCtrl.text = _selectedDealer!;
                              } else {
                                _selectedSubSeller = val;
                                _partyCtrl.text = val!;
                              }
                              _refreshValidationCache();
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],

                  // Minimize to dock button (allows background interaction)
                  InkWell(
                    onTap: () {
                      // Save current state so dock can re-open it
                      GeminiScannerService.instance.lastStockScanSession = LastStockScanSession(
                        imageBytes: _imagesList.first,
                        allFilesBytes: _imagesList,
                        items: _items,
                        isVoucher: isVoucher,
                        activeShift: _selectedShift,
                        activeDate: widget.activeDate,
                        defaultParty: _partyCtrl.text.trim(),
                      );
                      Navigator.pop(context, false);
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Tooltip(
                      message: 'Minimize to Dock (Work in Background)',
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: const Icon(
                          Icons.remove_rounded,
                          color: Colors.white70,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Close button
                  InkWell(
                    onTap: () => Navigator.pop(context, false),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: const Icon(Icons.close_rounded, color: Colors.white70, size: 16),
                    ),
                  ),
                ],
              ),
            ),

            // ── MISSING SERIES BANNER ────────────────────────
            if (missingCount > 0)
              Container(

                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    const Color(0xFF78350F).withAlpha(160),
                    const Color(0xFF92400E).withAlpha(80),
                  ]),
                  border: const Border(bottom: BorderSide(color: Color(0xFF92400E), width: 0.5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Color(0xFFFBBF24), size: 15),
                    const SizedBox(width: 8),
                    Text('$missingCount ticket(s) missing series —  Apply:',
                        style: const TextStyle(color: Color(0xFFFBBF24), fontWeight: FontWeight.bold, fontSize: 11)),
                    const SizedBox(width: 10),
                    ...['12', '20', '24', '36', '40', '60'].map((s) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: InkWell(
                            onTap: () => _applySeriesToAllMissing(s),
                            borderRadius: BorderRadius.circular(5),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(color: const Color(0xFFFBBF24).withAlpha(150)),
                              ),
                              child: Text('Ser $s',
                                  style: const TextStyle(
                                      color: Color(0xFFFBBF24), fontWeight: FontWeight.bold, fontSize: 10.5)),
                            ),
                          ),
                        )),
                  ],
                ),
              ),

            // ── BODY ──────────────────────────────────────────
            Expanded(
              child: Row(
                children: [
                  // LEFT: Parcha Image (collapsible)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeInOut,
                    width: _isImageMinimized ? 44 : 360,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF050810),
                        border: Border(right: BorderSide(color: primaryColor.withAlpha(30))),
                      ),
                      child: Column(
                        children: [
                          // Image header with minimize button & Slip switcher
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: _isImageMinimized ? 6 : 8, vertical: 8),
                            decoration: const BoxDecoration(
                              border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
                            ),
                            child: Row(
                              mainAxisAlignment: _isImageMinimized ? MainAxisAlignment.center : MainAxisAlignment.start,
                              children: [
                                // Minimize / Expand Toggle
                                GestureDetector(
                                  onTap: () => setState(() => _isImageMinimized = !_isImageMinimized),
                                  child: AnimatedRotation(
                                    turns: _isImageMinimized ? 0.5 : 0.0,
                                    duration: const Duration(milliseconds: 280),
                                    child: Container(
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        color: primaryColor.withAlpha(30),
                                        borderRadius: BorderRadius.circular(5),
                                        border: Border.all(color: primaryColor.withAlpha(80)),
                                      ),
                                      child: Icon(
                                        _isImageMinimized
                                            ? Icons.chevron_right_rounded
                                            : Icons.chevron_left_rounded,
                                        color: primaryColor,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                ),
                                if (!_isImageMinimized) ...[
                                  const SizedBox(width: 6),
                                  const Icon(Icons.image_search_rounded, size: 12, color: Color(0xFF64748B)),
                                  const SizedBox(width: 5),
                                  const Text('Parcha Image',
                                      style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                                  const Spacer(),

                                  // Multi-Slip Switcher Controls
                                  if (_imagesList.length > 1) ...[
                                    InkWell(
                                      onTap: _currentImageIndex > 0
                                          ? () => setState(() => _currentImageIndex--)
                                          : null,
                                      borderRadius: BorderRadius.circular(4),
                                      child: Container(
                                        padding: const EdgeInsets.all(3),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1E293B),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Icon(
                                          Icons.chevron_left_rounded,
                                          size: 14,
                                          color: _currentImageIndex > 0 ? primaryColor : Colors.grey.shade700,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: primaryColor.withAlpha(30),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: primaryColor.withAlpha(80)),
                                      ),
                                      child: Text(
                                        'Slip ${_currentImageIndex + 1}/${_imagesList.length}',
                                        style: TextStyle(
                                          color: primaryColor,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    InkWell(
                                      onTap: _currentImageIndex < _imagesList.length - 1
                                          ? () => setState(() => _currentImageIndex++)
                                          : null,
                                      borderRadius: BorderRadius.circular(4),
                                      child: Container(
                                        padding: const EdgeInsets.all(3),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1E293B),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Icon(
                                          Icons.chevron_right_rounded,
                                          size: 14,
                                          color: _currentImageIndex < _imagesList.length - 1 ? primaryColor : Colors.grey.shade700,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    InkWell(
                                      onTap: () => setState(() => _filterByCurrentPhoto = !_filterByCurrentPhoto),
                                      borderRadius: BorderRadius.circular(4),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: _filterByCurrentPhoto ? primaryColor.withAlpha(40) : const Color(0xFF1E293B),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(
                                            color: _filterByCurrentPhoto ? primaryColor : Colors.white24,
                                            width: 1,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              _filterByCurrentPhoto ? Icons.filter_alt_rounded : Icons.all_inclusive_rounded,
                                              size: 11,
                                              color: _filterByCurrentPhoto ? primaryColor : Colors.grey,
                                            ),
                                            const SizedBox(width: 3),
                                            Text(
                                              _filterByCurrentPhoto
                                                  ? 'Slip ${_currentImageIndex + 1} (${_items.where((it) => it.photoIndex == _currentImageIndex).length})'
                                                  : 'All Slips (${_items.length})',
                                              style: TextStyle(
                                                color: _filterByCurrentPhoto ? primaryColor : Colors.grey,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 9.5,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                  ],

                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: primaryColor.withAlpha(25),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: primaryColor.withAlpha(80)),
                                    ),
                                    child: Text('${_items.length} Ranges',
                                        style: TextStyle(
                                            color: primaryColor, fontWeight: FontWeight.bold, fontSize: 10)),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          // Image (hidden when minimized)
                          if (!_isImageMinimized)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: const Color(0xFF1E293B)),
                                      boxShadow: [
                                        BoxShadow(color: Colors.black.withAlpha(120), blurRadius: 15),
                                      ],
                                    ),
                                    child: InteractiveViewer(
                                      maxScale: 6.0,
                                      minScale: 0.4,
                                      child: Image.memory(
                                        _imagesList[_currentImageIndex.clamp(0, _imagesList.length - 1)],
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            )
                          else
                            // Vertical label when minimized
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _isImageMinimized = false),
                                child: Center(
                                  child: RotatedBox(
                                    quarterTurns: 3,
                                    child: Text(
                                      'PARCHA IMAGE',
                                      style: TextStyle(
                                        color: primaryColor.withAlpha(120),
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 2,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),


                  // RIGHT: Controls + Table
                  Expanded(
                    child: Container(
                      color: const Color(0xFF080C1A),
                      child: Column(
                        children: [
                          // Ã¢â€â‚¬Ã¢â€â‚¬ FILTER TOOLBAR Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
                          Container(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                            decoration: const BoxDecoration(
                              color: Color(0xFF0B1120),
                              border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Row 1: Status + Auto-Remove
                                Row(
                                  children: [
                                    // Status chips
                                    _compactChip(
                                      label: 'All  ${_items.length}',
                                      selected: _selectedStatusFilter == 'ALL',
                                      color: const Color(0xFF334155),
                                      activeColor: const Color(0xFF475569),
                                      onTap: () => setState(() => _selectedStatusFilter = 'ALL'),
                                    ),
                                    const SizedBox(width: 5),
                                    _compactChip(
                                      label: '✓ In Voucher  $validCount',
                                      selected: _selectedStatusFilter == 'VALID',
                                      color: const Color(0xFF14532D),
                                      activeColor: const Color(0xFF166534),
                                      onTap: () => setState(() => _selectedStatusFilter = 'VALID'),
                                    ),
                                    if (_notInVoucherCount > 0) ...[
                                      const SizedBox(width: 5),
                                      _compactChip(
                                        label: '❌ Not In Voucher  $_notInVoucherCount',
                                        selected: _selectedStatusFilter == 'NOT_IN_VOUCHER',
                                        color: const Color(0xFF450A0A),
                                        activeColor: const Color(0xFF991B1B),
                                        onTap: () => setState(() => _selectedStatusFilter = 'NOT_IN_VOUCHER'),
                                      ),
                                    ],
                                    if (_unmatchedCount > _notInVoucherCount) ...[
                                      const SizedBox(width: 5),
                                      _compactChip(
                                        label: '⚠ Other Issues  ${_unmatchedCount - _notInVoucherCount}',
                                        selected: _selectedStatusFilter == 'UNMATCHED',
                                        color: const Color(0xFF451A03),
                                        activeColor: const Color(0xFFB45309),
                                        onTap: () => setState(() => _selectedStatusFilter = 'UNMATCHED'),
                                      ),
                                    ],
                                     if (_cachedAiDoubtsCount > 0) ...[
                                       const SizedBox(width: 5),
                                       _compactChip(
                                         label: '❓ AI Doubts  $_cachedAiDoubtsCount',
                                         selected: _selectedStatusFilter == 'AI_DOUBTS',
                                         color: const Color(0xFF451A03),
                                         activeColor: const Color(0xFFD97706),
                                         onTap: () => setState(() => _selectedStatusFilter = 'AI_DOUBTS'),
                                       ),
                                     ],
                                     if (_cachedAiDoubtsCount > 0 || GeminiScannerService.instance.lastAiConfusions.isNotEmpty) ...[
                                       const SizedBox(width: 8),
                                       InkWell(
                                         onTap: _showAiDoubtsModal,
                                         borderRadius: BorderRadius.circular(6),
                                         child: Container(
                                           padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                           decoration: BoxDecoration(
                                             color: const Color(0xFFF59E0B).withAlpha(30),
                                             borderRadius: BorderRadius.circular(6),
                                             border: Border.all(color: const Color(0xFFF59E0B).withAlpha(150)),
                                           ),
                                           child: Row(
                                             mainAxisSize: MainAxisSize.min,
                                             children: [
                                               const Icon(Icons.warning_amber_rounded, size: 12, color: Color(0xFFF59E0B)),
                                               const SizedBox(width: 4),
                                               Text(
                                                 'AI Notes ($_cachedAiDoubtsCount)',
                                                 style: const TextStyle(
                                                   color: Color(0xFFF59E0B),
                                                   fontWeight: FontWeight.bold,
                                                   fontSize: 10.5,
                                                 ),
                                               ),
                                             ],
                                           ),
                                         ),
                                       ),
                                     ],
                                    const Spacer(),
                                    if (_alreadyIssuedCount > 0)
                                      TextButton.icon(
                                        onPressed: _removeAlreadyIssuedItems,
                                        icon: const Icon(Icons.delete_sweep_rounded, size: 13),
                                        label: Text('Remove Issued ($_alreadyIssuedCount)',
                                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                                        style: TextButton.styleFrom(
                                          foregroundColor: const Color(0xFFFCA5A5),
                                          backgroundColor: const Color(0xFF450A0A),
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                        ),
                                      ),
                                    if (_notInVoucherCount > 0) ...[
                                      const SizedBox(width: 6),
                                      TextButton.icon(
                                        onPressed: _removeNotInVoucherItems,
                                        icon: const Icon(Icons.playlist_remove_rounded, size: 13),
                                        label: Text('Remove Non-Voucher ($_notInVoucherCount)',
                                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                                        style: TextButton.styleFrom(
                                          foregroundColor: const Color(0xFFFCA5A5),
                                          backgroundColor: const Color(0xFF450A0A),
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 7),

                                // Row 2: Series filter + Date filter + Search
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      Text('Series:', style: TextStyle(color: Colors.grey.shade600, fontSize: 10, fontWeight: FontWeight.bold)),
                                      const SizedBox(width: 6),
                                      _compactChip(
                                        label: 'All',
                                        selected: _selectedSeriesFilter == 'ALL',
                                        color: const Color(0xFF1E3A5F),
                                        activeColor: const Color(0xFF1D4ED8),
                                        onTap: () => setState(() => _selectedSeriesFilter = 'ALL'),
                                      ),
                                      ..._availableSeriesList.map((s) {
                                        final count = _items.where((it) => it.series == s).length;
                                        return Padding(
                                          padding: const EdgeInsets.only(left: 4),
                                          child: _compactChip(
                                            label: 'S$s  $count',
                                            selected: _selectedSeriesFilter == s,
                                            color: const Color(0xFF1E293B),
                                            activeColor: const Color(0xFF1D4ED8),
                                            onTap: () => setState(() => _selectedSeriesFilter = s),
                                          ),
                                        );
                                      }),
                                      if (missingCount > 0)
                                        Padding(
                                          padding: const EdgeInsets.only(left: 4),
                                          child: _compactChip(
                                            label: '? $missingCount',
                                            selected: _selectedSeriesFilter == '?',
                                            color: const Color(0xFF3B2000),
                                            activeColor: const Color(0xFF78350F),
                                            onTap: () => setState(() => _selectedSeriesFilter = '?'),
                                          ),
                                        ),
                                      if (_availableDatesList.length > 1) ...[
                                        const SizedBox(width: 12),
                                        Container(width: 1, height: 14, color: const Color(0xFF334155)),
                                        const SizedBox(width: 12),
                                        Text('Date:', style: TextStyle(color: Colors.grey.shade600, fontSize: 10, fontWeight: FontWeight.bold)),
                                        const SizedBox(width: 6),
                                        _compactChip(
                                          label: 'All',
                                          selected: _selectedDateFilter == 'ALL',
                                          color: const Color(0xFF1C1A05),
                                          activeColor: const Color(0xFF78350F),
                                          onTap: () => setState(() => _selectedDateFilter = 'ALL'),
                                        ),
                                        ..._availableDatesList.map((d) {
                                          final count = _items.where((it) => it.targetDate == d).length;
                                          final dLabel = d.split('-').skip(1).join('/');
                                          return Padding(
                                            padding: const EdgeInsets.only(left: 4),
                                            child: _compactChip(
                                              label: '$dLabel  $count',
                                              selected: _selectedDateFilter == d,
                                              color: const Color(0xFF1E293B),
                                              activeColor: const Color(0xFF92400E),
                                              onTap: () => setState(() => _selectedDateFilter = d),
                                            ),
                                          );
                                        }),
                                      ],
                                      if (_availableShiftsList.length > 1) ...[
                                        const SizedBox(width: 12),
                                        Container(width: 1, height: 14, color: const Color(0xFF334155)),
                                        const SizedBox(width: 12),
                                        Text('Shift:', style: TextStyle(color: Colors.grey.shade600, fontSize: 10, fontWeight: FontWeight.bold)),
                                        const SizedBox(width: 6),
                                        _compactChip(
                                          label: 'All Shifts',
                                          selected: _selectedShiftFilter == 'ALL',
                                          color: const Color(0xFF1E1B4B),
                                          activeColor: const Color(0xFF4338CA),
                                          onTap: () => setState(() => _selectedShiftFilter = 'ALL'),
                                        ),
                                        ..._availableShiftsList.map((sh) {
                                          final count = _items.where((it) {
                                            final itemShift = (it.drawShift != null && it.drawShift!.isNotEmpty) ? it.drawShift! : _selectedShift;
                                            return itemShift == sh;
                                          }).length;
                                          final shLabel = sh.replaceAll('Dear ', '');
                                          return Padding(
                                            padding: const EdgeInsets.only(left: 4),
                                            child: _compactChip(
                                              label: '$shLabel  $count',
                                              selected: _selectedShiftFilter == sh,
                                              color: const Color(0xFF1E293B),
                                              activeColor: const Color(0xFF6D28D9),
                                              onTap: () => setState(() => _selectedShiftFilter = sh),
                                            ),
                                          );
                                        }),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 7),

                                // Row 3: Batch Apply + Manual Entry + Search
                                Row(
                                  children: [
                                    // Quick Apply
                                    Container(
                                      height: 30,
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0F172A),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: const Color(0xFF1E293B)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text('Apply All:', style: TextStyle(color: Colors.grey.shade600, fontSize: 10, fontWeight: FontWeight.bold)),
                                          const SizedBox(width: 6),
                                          ...['12', '20', '24', '36', '40', '60'].map((s) => Padding(
                                                padding: const EdgeInsets.only(left: 3),
                                                child: InkWell(
                                                  onTap: () => _applySeriesToAll(s),
                                                  borderRadius: BorderRadius.circular(4),
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFF1E293B),
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text('S$s',
                                                        style: const TextStyle(
                                                            color: Color(0xFF38BDF8),
                                                            fontSize: 10,
                                                            fontWeight: FontWeight.bold)),
                                                  ),
                                                ),
                                              )),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),

                                    // Manual Entry
                                    Container(
                                      height: 30,
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0F172A),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: primaryColor.withAlpha(60)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.add_circle_outline_rounded, size: 13, color: primaryColor),
                                          const SizedBox(width: 5),
                                          SizedBox(
                                            width: 44,
                                            child: TextField(
                                              controller: _manualSeriesCtrl,
                                              textCapitalization: TextCapitalization.characters,
                                              style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 11),
                                              decoration: const InputDecoration(
                                                isDense: true,
                                                hintText: 'Ser',
                                                border: InputBorder.none,
                                                contentPadding: EdgeInsets.zero,
                                              ),
                                            ),
                                          ),
                                          Container(width: 1, height: 16, color: const Color(0xFF334155)),
                                          const SizedBox(width: 5),
                                          SizedBox(
                                            width: 180,
                                            child: TextField(
                                              controller: _manualTicketCtrl,
                                              focusNode: _manualTicketFocusNode,
                                              maxLength: 25,
                                              style: const TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 11),
                                              decoration: InputDecoration(
                                                isDense: true,
                                                counterText: '',
                                                hintText: '52385  या  52150-99  या  52150-99-10',
                                                hintStyle: TextStyle(color: Colors.grey.shade700, fontSize: 10),
                                                border: InputBorder.none,
                                                contentPadding: EdgeInsets.zero,
                                              ),
                                              onSubmitted: (_) => _addManualTicket(),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          GestureDetector(
                                            onTap: _addManualTicket,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: primaryColor,
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: const Text('+ ADD', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    const SizedBox(width: 8),

                                    // Search
                                    Expanded(
                                      child: SizedBox(
                                        height: 30,
                                        child: TextField(
                                          controller: _searchCtrl,
                                          style: const TextStyle(fontSize: 11, color: Colors.white),
                                          decoration: InputDecoration(
                                            isDense: true,
                                            hintText: 'Search ticket / series...',
                                            hintStyle: TextStyle(color: Colors.grey.shade700, fontSize: 10.5),
                                            prefixIcon: const Icon(Icons.search_rounded, size: 13, color: Color(0xFF475569)),
                                            filled: true,
                                            fillColor: const Color(0xFF0F172A),
                                            border: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(6),
                                              borderSide: const BorderSide(color: Color(0xFF1E293B)),
                                            ),
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          ),
                                          onChanged: (val) => setState(() => _searchQuery = val),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          // ── BULK ACTIONS BAR (When items selected via Shift+Click) ──
                          _buildReviewBulkActionBar(primaryColor),

                          // ── FIND & REPLACE BAR (Ctrl+H) ────────────────────────
                          if (_showFindReplaceBar)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              color: const Color(0xFF0F2B48),
                              child: Row(
                                children: [
                                  const Icon(Icons.find_replace_rounded, size: 14, color: Color(0xFF38BDF8)),
                                  const SizedBox(width: 6),
                                  const Text('Find & Replace:', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11)),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 120,
                                    height: 26,
                                    child: TextField(
                                      controller: _findCtrl,
                                      style: const TextStyle(fontSize: 11, color: Colors.white),
                                      decoration: InputDecoration(
                                        isDense: true,
                                        hintText: 'Find...',
                                        hintStyle: const TextStyle(fontSize: 10, color: Colors.grey),
                                        filled: true,
                                        fillColor: const Color(0xFF0B1120),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  SizedBox(
                                    width: 120,
                                    height: 26,
                                    child: TextField(
                                      controller: _replaceCtrl,
                                      style: const TextStyle(fontSize: 11, color: Colors.white),
                                      decoration: InputDecoration(
                                        isDense: true,
                                        hintText: 'Replace with...',
                                        hintStyle: const TextStyle(fontSize: 10, color: Colors.grey),
                                        filled: true,
                                        fillColor: const Color(0xFF0B1120),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                      ),
                                      onSubmitted: (_) => _executeFindReplace(selectedOnly: _selectedItems.isNotEmpty),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  ElevatedButton(
                                    onPressed: () => _executeFindReplace(selectedOnly: true),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF0284C7),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      minimumSize: const Size(50, 26),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                    ),
                                    child: Text(_selectedItems.isNotEmpty ? 'Replace Sel (${_selectedItems.length})' : 'Replace Sel', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                  ),
                                  const SizedBox(width: 4),
                                  OutlinedButton(
                                    onPressed: () => _executeFindReplace(selectedOnly: false),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(color: Color(0xFF38BDF8)),
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      minimumSize: const Size(50, 26),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                    ),
                                    child: const Text('Replace All', style: TextStyle(fontSize: 10, color: Color(0xFF38BDF8), fontWeight: FontWeight.bold)),
                                  ),
                                  const Spacer(),
                                  IconButton(
                                    icon: const Icon(Icons.close, size: 14, color: Colors.white70),
                                    onPressed: () => setState(() => _showFindReplaceBar = false),
                                  ),
                                ],
                              ),
                            ),

                          // ── TABLE HEADER ────────────────────────────────────
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            color: const Color(0xFF0F172A),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: _imagesList.length > 1 ? 66 : 48,
                                  child: Row(
                                    children: [
                                      InkWell(
                                        onTap: _toggleSelectAll,
                                        child: Icon(
                                          _displayedItems.isNotEmpty && _selectedItems.containsAll(_displayedItems)
                                              ? Icons.check_box_rounded
                                              : (_selectedItems.isNotEmpty ? Icons.indeterminate_check_box_rounded : Icons.check_box_outline_blank_rounded),
                                          size: 15,
                                          color: _selectedItems.isNotEmpty ? Colors.indigoAccent : const Color(0xFF475569),
                                        ),
                                      ),
                                      const SizedBox(width: 3),
                                      const Text('#', style: TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.bold, fontSize: 10)),
                                    ],
                                  ),
                                ),
                                 SizedBox(
                                   width: 60,
                                   child: InkWell(
                                     onTap: _pickMainDate,
                                     borderRadius: BorderRadius.circular(4),
                                     child: const Row(
                                       children: [
                                         Text('DATE', style: TextStyle(color: Color(0xFFFBBF24), fontWeight: FontWeight.bold, fontSize: 10)),
                                         SizedBox(width: 2),
                                         Icon(Icons.edit_calendar_rounded, size: 10, color: Color(0xFFFBBF24)),
                                       ],
                                     ),
                                   ),
                                 ),
                                const SizedBox(width: 4),
                                const SizedBox(width: 58, child: Center(child: Text('SHIFT', style: TextStyle(color: Color(0xFFA78BFA), fontWeight: FontWeight.bold, fontSize: 10)))),
                                const SizedBox(width: 4),
                                const SizedBox(width: 54, child: Text('SERIES', style: TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.bold, fontSize: 10))),
                                const SizedBox(width: 6),
                                const Expanded(child: Text('TICKET RANGE', style: TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.bold, fontSize: 10))),
                                const SizedBox(width: 6),
                                const SizedBox(width: 52, child: Center(child: Text('QTY', style: TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.bold, fontSize: 10)))),
                                const SizedBox(width: 4),
                                const SizedBox(width: 70, child: Align(alignment: Alignment.centerRight, child: Text('AMOUNT', style: TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.bold, fontSize: 10)))),
                                const SizedBox(width: 4),
                                const SizedBox(width: 96, child: Align(alignment: Alignment.centerRight, child: Text('ACTIONS', style: TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.bold, fontSize: 10)))),
                              ],
                            ),
                          ),
                          Container(height: 1, color: const Color(0xFF1E293B)),

                          // ── TABLE BODY ──────────────────────────────────────
                          Expanded(
                            child: _displayedItems.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.search_off_rounded, size: 40, color: Colors.grey.shade700),
                                        const SizedBox(height: 10),
                                        Text('No matching tickets found.',
                                            style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                                      ],
                                    ),
                                  )
                                : ListView.builder(
                                    itemCount: _displayedItems.length,
                                    itemBuilder: (ctx, idx) {
                                      final item = _displayedItems[idx];
                                      final status = _validationCache[item] ?? _getItemValidationStatus(item);
                                      final isSelected = _selectedItems.contains(item);

                                      return _ReviewItemRowWidget(
                                        key: ValueKey(item),
                                        item: item,
                                        idx: idx,
                                        isSelected: isSelected,
                                        status: status,
                                        primaryColor: primaryColor,
                                        activeDate: _activeDate,
                                        getRateForSeries: _getPriceForSeries,
                                        hasMultipleSlips: _imagesList.length > 1,
                                        currentImageIndex: _currentImageIndex,
                                        onSlipSelected: (slipIdx) => setState(() => _currentImageIndex = slipIdx),
                                        onFocusGained: () {
                                          _activeEditingItem = item;
                                        },
                                        onFocusLost: () {
                                          _activeEditingItem = null;
                                        },
                                        onTap: () => _handleRowTap(idx, item),
                                        onDuplicate: () {
                                          setState(() {
                                            final clone = GeminiScannedItem(
                                              series: item.series,
                                              ticketNo: item.ticketNo,
                                              fromTicket: item.fromTicket,
                                              toTicket: item.toTicket,
                                              quantity: item.quantity,
                                              amount: item.amount,
                                              targetDate: item.targetDate,
                                              drawShift: item.drawShift,
                                            );
                                            final globalIdx = _items.indexOf(item);
                                            _items.insert(globalIdx + 1, clone);
                                            _refreshValidationCache();
                                          });
                                        },
                                        onDelete: () => setState(() {
                                          _items.remove(item);
                                          _validationCache.remove(item);
                                          _refreshValidationCache();
                                        }),
                                        onDateChanged: (newDate) {
                                          setState(() {
                                            item.targetDate = newDate;
                                            _refreshSingleItemValidation(item);
                                          });
                                        },
                                        onShiftChanged: (newShift) {
                                          setState(() {
                                            item.drawShift = newShift;
                                            _refreshSingleItemValidation(item);
                                          });
                                        },
                                        onItemChanged: () {
                                          _refreshSingleItemValidation(item);
                                          _recalculateAllPrices();
                                          setState(() {});
                                        },
                                        isMultiCursorActive: isSelected && _selectedItems.length > 1 && _multiCursorSyncEnabled,
                                        cursorOffsetFromEnd: _multiCursorOffsetFromEnd,
                                        onCursorOffsetChanged: _handleCursorOffsetChanged,
                                        onMultiCursorSync: (oldVal, newVal, field) => _handleMultiCursorSync(item, oldVal, newVal, field),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── FOOTER ────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [const Color(0xFF0F172A), primaryColor.withAlpha(20)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                border: Border(top: BorderSide(color: primaryColor.withAlpha(40))),
              ),
              child: Row(
                children: [
                  // Totals
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$_totalTickets Tickets • ${_items.length} Ranges',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      Text(
                        'Total Value: ₹${_totalAmount.toStringAsFixed(2)}',
                        style: const TextStyle(color: Color(0xFFFBBF24), fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                    ],
                  ),
                  const Spacer(),

                  // Export CSV / Excel
                  OutlinedButton.icon(
                    onPressed: _exportScannedEntries,
                    icon: const Icon(Icons.file_download_outlined, size: 15, color: Color(0xFF38BDF8)),
                    label: const Text('EXPORT CSV', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.5)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF38BDF8),
                      side: const BorderSide(color: Color(0xFF38BDF8), width: 1.2),
                      backgroundColor: const Color(0xFF0C2433),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Cancel
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey.shade400,
                      side: BorderSide(color: Colors.grey.shade700),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('CANCEL'),
                  ),
                  const SizedBox(width: 10),

                  // Confirm
                  ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveAllParsedEntries,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_circle_rounded, size: 16),
                    label: Text(
                      isVoucher ? 'SAVE ALL VOUCHERS' : 'SAVE ALL UNSOLD',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      shadowColor: primaryColor.withAlpha(120),
                      elevation: 8,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬ HELPER WIDGETS Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  Widget _statPill(String value, String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 12)),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: fg.withAlpha(160), fontSize: 9.5)),
        ],
      ),
    );
  }

  Widget _compactChip({
    required String label,
    required bool selected,
    required Color color,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? activeColor : color,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: selected ? activeColor.withAlpha(200) : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.grey.shade400,
            fontSize: 10.5,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _ReviewItemRowWidget extends StatefulWidget {
  final GeminiScannedItem item;
  final int idx;
  final bool isSelected;
  final String? status;
  final Color primaryColor;
  final DateTime activeDate;
  final double Function(String series) getRateForSeries;
  final VoidCallback onFocusGained;
  final VoidCallback onFocusLost;
  final VoidCallback onTap;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final ValueChanged<String> onDateChanged;
  final ValueChanged<String> onShiftChanged;
  final VoidCallback onItemChanged;
  final bool isMultiCursorActive;
  final int cursorOffsetFromEnd;
  final ValueChanged<int>? onCursorOffsetChanged;
  final void Function(String oldVal, String newVal, String field)? onMultiCursorSync;
  final bool hasMultipleSlips;
  final int currentImageIndex;
  final ValueChanged<int>? onSlipSelected;

  const _ReviewItemRowWidget({
    super.key,
    required this.item,
    required this.idx,
    required this.isSelected,
    required this.status,
    required this.primaryColor,
    required this.activeDate,
    required this.getRateForSeries,
    required this.onFocusGained,
    required this.onFocusLost,
    required this.onTap,
    required this.onDuplicate,
    required this.onDelete,
    required this.onDateChanged,
    required this.onShiftChanged,
    required this.onItemChanged,
    this.isMultiCursorActive = false,
    this.cursorOffsetFromEnd = 3,
    this.onCursorOffsetChanged,
    this.onMultiCursorSync,
    this.hasMultipleSlips = false,
    this.currentImageIndex = 0,
    this.onSlipSelected,
  });

  @override
  State<_ReviewItemRowWidget> createState() => _ReviewItemRowWidgetState();
}

class _ReviewItemRowWidgetState extends State<_ReviewItemRowWidget> {
  TextEditingController? _seriesCtrl;
  TextEditingController? _ticketCtrl;
  TextEditingController? _qtyCtrl;
  TextEditingController? _amountCtrl;

  FocusNode? _seriesFocusNode;
  FocusNode? _ticketFocusNode;
  FocusNode? _qtyFocusNode;
  FocusNode? _amountFocusNode;

  void _ensureInitialized() {
    _seriesCtrl ??= TextEditingController(text: widget.item.series);
    _ticketCtrl ??= TextEditingController(text: widget.item.ticketNo);
    _qtyCtrl ??= TextEditingController(text: '${widget.item.quantity}');
    _amountCtrl ??= TextEditingController(
      text: widget.item.amount > 0 ? widget.item.amount.toStringAsFixed(0) : '0',
    );

    if (_seriesFocusNode == null) {
      _seriesFocusNode = FocusNode();
      _attachFocusNode(_seriesFocusNode!);
    }
    if (_ticketFocusNode == null) {
      _ticketFocusNode = FocusNode();
      _attachFocusNode(_ticketFocusNode!);
      _ticketCtrl?.addListener(_onTicketSelectionChanged);
    }
    if (_qtyFocusNode == null) {
      _qtyFocusNode = FocusNode();
      _attachFocusNode(_qtyFocusNode!);
    }
    if (_amountFocusNode == null) {
      _amountFocusNode = FocusNode();
      _attachFocusNode(_amountFocusNode!);
    }
  }

  void _onTicketSelectionChanged() {
    if (_ticketFocusNode?.hasFocus ?? false) {
      final sel = _ticketCtrl?.selection;
      if (sel != null && sel.isValid && sel.baseOffset >= 0) {
        final fromEnd = (_ticketCtrl?.text.length ?? 0) - sel.baseOffset;
        widget.onCursorOffsetChanged?.call(fromEnd);
      }
    }
  }

  void _attachFocusNode(FocusNode node) {
    node.addListener(() {
      if (node.hasFocus) {
        widget.onFocusGained();
      } else {
        widget.onFocusLost();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _ensureInitialized();
  }

  @override
  void didUpdateWidget(covariant _ReviewItemRowWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ensureInitialized();
    if (!(_seriesFocusNode?.hasFocus ?? false) && _seriesCtrl?.text != widget.item.series) {
      _seriesCtrl?.text = widget.item.series;
    }
    if (_ticketCtrl?.text != widget.item.ticketNo) {
      _ticketCtrl?.text = widget.item.ticketNo;
    }
    if (!(_qtyFocusNode?.hasFocus ?? false) && _qtyCtrl?.text != '${widget.item.quantity}') {
      _qtyCtrl?.text = '${widget.item.quantity}';
    }
    if (!(_amountFocusNode?.hasFocus ?? false)) {
      final curAmt = widget.item.amount.toStringAsFixed(0);
      if (_amountCtrl?.text != curAmt) {
        _amountCtrl?.text = curAmt;
      }
    }
  }

  @override
  void dispose() {
    _seriesCtrl?.dispose();
    _ticketCtrl?.dispose();
    _qtyCtrl?.dispose();
    _amountCtrl?.dispose();

    _seriesFocusNode?.dispose();
    _ticketFocusNode?.dispose();
    _qtyFocusNode?.dispose();
    _amountFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _ensureInitialized();
    final item = widget.item;
    final isMissingSeries = item.series == '?' || item.series.trim().isEmpty;
    final hasIssue = widget.status != null;
    final isAlready = hasIssue && (widget.status!.contains('Already') || widget.status!.contains('Not in Voucher'));

    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: widget.isSelected
              ? const Color(0xFF312E81).withAlpha(180)
              : (hasIssue
                  ? (isAlready
                      ? const Color(0xFF451A03).withAlpha(160)
                      : const Color(0xFF450A0A).withAlpha(160))
                  : (widget.idx.isEven ? const Color(0xFF0B1120) : Colors.transparent)),
          borderRadius: BorderRadius.circular(6),
          border: widget.isSelected
              ? Border.all(color: Colors.indigoAccent, width: 1.2)
              : (hasIssue
                  ? Border.all(
                      color: isAlready
                          ? const Color(0xFFFBBF24)
                          : const Color(0xFFEF4444),
                      width: 1.5,
                    )
                  : null),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Row(
            children: [
              // Checkbox & Row Number & Slip Badge
              SizedBox(
                width: widget.hasMultipleSlips ? 66 : 48,
                child: Row(
                  children: [
                    Icon(
                      widget.isSelected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                      size: 13,
                      color: widget.isSelected ? Colors.indigoAccent : Colors.grey.shade700,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${widget.idx + 1}',
                      style: TextStyle(
                        color: widget.isSelected ? Colors.white : Colors.grey.shade700,
                        fontSize: 9.5,
                      ),
                    ),
                    if (widget.hasMultipleSlips) ...[
                      const SizedBox(width: 3),
                      InkWell(
                        onTap: () => widget.onSlipSelected?.call(widget.item.photoIndex),
                        borderRadius: BorderRadius.circular(3),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                          decoration: BoxDecoration(
                            color: widget.item.photoIndex == widget.currentImageIndex
                                ? widget.primaryColor.withAlpha(40)
                                : const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(
                              color: widget.item.photoIndex == widget.currentImageIndex
                                  ? widget.primaryColor
                                  : Colors.transparent,
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            'P${widget.item.photoIndex + 1}',
                            style: TextStyle(
                              fontSize: 8.5,
                              fontWeight: FontWeight.bold,
                              color: widget.item.photoIndex == widget.currentImageIndex
                                  ? widget.primaryColor
                                  : Colors.white70,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Date Pill — tap to open date picker
              SizedBox(
                width: 60,
                child: GestureDetector(
                  onTap: () async {
                    final currentDate = item.targetDate != null && item.targetDate!.isNotEmpty
                        ? DateTime.tryParse(item.targetDate!) ?? widget.activeDate
                        : widget.activeDate;
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: currentDate,
                      firstDate: DateTime(1970),
                      lastDate: DateTime(2999),
                      builder: (context, child) => Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: ColorScheme.dark(
                            primary: widget.primaryColor,
                            surface: const Color(0xFF1E293B),
                          ),
                          dialogTheme: const DialogThemeData(
                            backgroundColor: Color(0xFF0F172A),
                          ),
                        ),
                        child: child!,
                      ),
                    );
                    if (picked != null) {
                      final f = DateFormat('yyyy-MM-dd').format(picked);
                      widget.onDateChanged(f);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1A05),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF78350F).withAlpha(120)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          item.targetDate != null && item.targetDate!.isNotEmpty
                              ? item.targetDate!.split('-').skip(1).join('/')
                              : DateFormat('dd/MM').format(widget.activeDate),
                          style: const TextStyle(
                              color: Color(0xFFFBBF24), fontSize: 9.5, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 2),
                        const Icon(Icons.edit_calendar_rounded, size: 9, color: Color(0xFFFBBF24)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),

              // Shift Pill — tap to toggle or select shift
              SizedBox(
                width: 58,
                child: GestureDetector(
                  onTap: () {
                    final cur = (item.drawShift != null && item.drawShift!.isNotEmpty) ? item.drawShift! : 'Dear 1 PM';
                    final next = cur.contains('1') ? 'Dear 6 PM' : (cur.contains('6') ? 'Dear 8 PM' : 'Dear 1 PM');
                    widget.onShiftChanged(next);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
                    decoration: BoxDecoration(
                      color: (item.drawShift ?? 'Dear 1 PM').contains('1')
                          ? const Color(0xFF0F2942)
                          : ((item.drawShift ?? '').contains('6') ? const Color(0xFF2E1065) : const Color(0xFF3F1D38)),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: (item.drawShift ?? 'Dear 1 PM').contains('1')
                            ? const Color(0xFF38BDF8).withAlpha(150)
                            : ((item.drawShift ?? '').contains('6') ? const Color(0xFFA78BFA).withAlpha(150) : const Color(0xFFF472B6).withAlpha(150)),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        (item.drawShift != null && item.drawShift!.isNotEmpty ? item.drawShift! : '1 PM').replaceAll('Dear ', ''),
                        style: TextStyle(
                          color: (item.drawShift ?? 'Dear 1 PM').contains('1')
                              ? const Color(0xFF38BDF8)
                              : ((item.drawShift ?? '').contains('6') ? const Color(0xFFA78BFA) : const Color(0xFFF472B6)),
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),

              // 1. Series Box (editable)
              SizedBox(
                width: 54,
                height: 28,
                child: TextField(
                  controller: _seriesCtrl,
                  focusNode: _seriesFocusNode,
                  style: TextStyle(
                    color: isMissingSeries ? const Color(0xFFFBBF24) : const Color(0xFF38BDF8),
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: isMissingSeries ? const Color(0xFF451A03) : const Color(0xFF0F172A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(
                          color: isMissingSeries ? const Color(0xFFFBBF24) : const Color(0xFF1E293B)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: const BorderSide(color: Color(0xFF38BDF8), width: 1.2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                  ),
                  onChanged: (val) {
                    item.series = val.trim().toUpperCase();
                    final rate = widget.getRateForSeries(item.series);
                    item.amount = rate * item.quantity;
                    if (!(_amountFocusNode?.hasFocus ?? false)) {
                      _amountCtrl?.text = item.amount.toStringAsFixed(0);
                    }
                    widget.onItemChanged();
                    widget.onMultiCursorSync?.call('', val, 'series');
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 6),

              // 2. Ticket Range (editable, prominent, VS Code multi-cursor enabled)
              Expanded(
                child: SizedBox(
                  height: 28,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      TextField(
                        controller: _ticketCtrl,
                        focusNode: _ticketFocusNode,
                        maxLength: 25,
                        style: TextStyle(
                          color: widget.isMultiCursorActive
                              ? const Color(0xFF38BDF8)
                              : (hasIssue ? const Color(0xFFF87171) : const Color(0xFF4ADE80)),
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                          fontSize: 12.5,
                          letterSpacing: 0.5,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          counterText: '',
                          filled: true,
                          fillColor: widget.isMultiCursorActive
                              ? const Color(0xFF082F49)
                              : (hasIssue ? const Color(0xFF2A0A0A) : const Color(0xFF071A0E)),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(
                              color: widget.isMultiCursorActive
                                  ? const Color(0xFF38BDF8)
                                  : (hasIssue
                                      ? const Color(0xFFEF4444)
                                      : ((item.aiDoubt != null && item.aiDoubt!.isNotEmpty)
                                          ? const Color(0xFFF59E0B)
                                          : const Color(0xFF14532D))),
                              width: widget.isMultiCursorActive ? 1.8 : (hasIssue || (item.aiDoubt != null && item.aiDoubt!.isNotEmpty) ? 1.5 : 1.0),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(
                              color: widget.isMultiCursorActive
                                  ? const Color(0xFF38BDF8)
                                  : (hasIssue
                                      ? const Color(0xFFF87171)
                                      : ((item.aiDoubt != null && item.aiDoubt!.isNotEmpty)
                                          ? const Color(0xFFFBBF24)
                                          : const Color(0xFF4ADE80))),
                              width: widget.isMultiCursorActive ? 2.0 : 1.5,
                            ),
                          ),
                          suffixIcon: widget.isMultiCursorActive
                              ? const Tooltip(
                                  message: '⚡ VS Code Multi-Cursor Active (Typing syncs across selected)',
                                  child: Icon(Icons.bolt_rounded, size: 14, color: Color(0xFF38BDF8)),
                                )
                              : ((item.aiDoubt != null && item.aiDoubt!.isNotEmpty)
                                  ? Tooltip(
                                      message: '⚠️ AI Doubt: ${item.aiDoubt}',
                                      child: const Icon(Icons.help_outline_rounded, size: 13, color: Color(0xFFF59E0B)),
                                    )
                                  : null),
                          suffixIconConstraints: const BoxConstraints(maxWidth: 22, maxHeight: 22),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        ),
                        onChanged: (val) {
                          final oldVal = item.ticketNo;
                          item.ticketNo = val;
                          if (val.contains('-')) {
                            final parts = val.split('-');
                            item.fromTicket = parts.first.trim();
                            item.toTicket = parts.last.trim();
                            final f = int.tryParse(item.fromTicket);
                            final t = int.tryParse(item.toTicket);
                            if (f != null && t != null && t >= f) {
                              item.quantity = (t - f) + 1;
                            }
                          } else {
                            item.fromTicket = val.trim();
                            item.toTicket = val.trim();
                            item.quantity = 1;
                          }
                          final rate = widget.getRateForSeries(item.series);
                          item.amount = rate * item.quantity;
                          if (!(_qtyFocusNode?.hasFocus ?? false)) {
                            _qtyCtrl?.text = '${item.quantity}';
                          }
                          if (!(_amountFocusNode?.hasFocus ?? false)) {
                            _amountCtrl?.text = item.amount.toStringAsFixed(0);
                          }
                          widget.onItemChanged();
                          widget.onMultiCursorSync?.call(oldVal, val, 'ticket');
                          setState(() {});
                        },
                      ),
                      // ⚡ Live simulated blinking cursor for non-focused multi-cursor cells!
                      if (widget.isMultiCursorActive && !(_ticketFocusNode?.hasFocus ?? false))
                        Builder(
                          builder: (context) {
                            final text = widget.item.ticketNo;
                            int targetOffset = text.length - widget.cursorOffsetFromEnd;
                            if (targetOffset < 0) targetOffset = 0;
                            if (targetOffset > text.length) targetOffset = text.length;

                            final textUpToCursor = text.substring(0, targetOffset);
                            final tp = TextPainter(
                              text: TextSpan(
                                text: textUpToCursor,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              textDirection: Directionality.of(context),
                            )..layout();

                            return Positioned(
                              left: tp.width + 8.0,
                              top: 5,
                              bottom: 5,
                              child: const IgnorePointer(child: _BlinkingCursor()),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),

              // 3. QTY Box (fully editable!)
              SizedBox(
                width: 52,
                height: 28,
                child: TextField(
                  controller: _qtyCtrl,
                  focusNode: _qtyFocusNode,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                  ),
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: const BorderSide(color: Color(0xFF1E293B)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: const BorderSide(color: Color(0xFF38BDF8), width: 1.2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
                  ),
                  onChanged: (val) {
                    final q = int.tryParse(val.trim());
                    if (q != null && q > 0) {
                      item.quantity = q;
                      final rate = widget.getRateForSeries(item.series);
                      item.amount = rate * q;
                      if (!(_amountFocusNode?.hasFocus ?? false)) {
                        _amountCtrl?.text = item.amount.toStringAsFixed(0);
                      }
                      widget.onItemChanged();
                      setState(() {});
                    }
                  },
                ),
              ),
              const SizedBox(width: 4),

              // 4. Amount Box (fully editable!)
              SizedBox(
                width: 70,
                height: 28,
                child: TextField(
                  controller: _amountCtrl,
                  focusNode: _amountFocusNode,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(
                    color: Color(0xFFFBBF24),
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                  ),
                  textAlign: TextAlign.right,
                  decoration: InputDecoration(
                    isDense: true,
                    prefixText: '₹',
                    prefixStyle: const TextStyle(color: Color(0xFFFBBF24), fontSize: 10, fontWeight: FontWeight.bold),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: const BorderSide(color: Color(0xFF1E293B)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: const BorderSide(color: Color(0xFFFBBF24), width: 1.2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                  ),
                  onChanged: (val) {
                    final a = double.tryParse(val.trim());
                    if (a != null && a >= 0) {
                      item.amount = a;
                      widget.onItemChanged();
                      setState(() {});
                    }
                  },
                ),
              ),
              const SizedBox(width: 4),

              // 5. ACTION BUTTONS (Width adapts for Doubt badge)
              SizedBox(
                width: (item.aiDoubt != null && item.aiDoubt!.isNotEmpty) ? 140 : 96,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (item.aiDoubt != null && item.aiDoubt!.isNotEmpty) ...[
                      Tooltip(
                        message: 'AI Doubt: ${item.aiDoubt}',
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B).withAlpha(35),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFFF59E0B).withAlpha(180)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.help_outline_rounded, size: 9, color: Color(0xFFF59E0B)),
                              SizedBox(width: 2),
                              Text(
                                'Doubt',
                                style: TextStyle(
                                  color: Color(0xFFF59E0B),
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 3),
                    ],
                    if (hasIssue)
                      Flexible(
                        child: Tooltip(
                          message: widget.status,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: isAlready ? Colors.amber.withAlpha(30) : Colors.red.withAlpha(30),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isAlready ? const Color(0xFFFBBF24).withAlpha(150) : const Color(0xFFF87171).withAlpha(150),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isAlready ? Icons.warning_amber_rounded : Icons.error_outline_rounded,
                                  size: 10,
                                  color: isAlready ? const Color(0xFFFBBF24) : const Color(0xFFF87171),
                                ),
                                const SizedBox(width: 2),
                                Flexible(
                                  child: Text(
                                    widget.status!.contains('Not in Voucher')
                                        ? 'No Vouch'
                                        : (widget.status!.contains('Issued to')
                                            ? 'Diff Party'
                                            : (isAlready ? 'Exist' : 'Dup')),
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: isAlready ? const Color(0xFFFBBF24) : const Color(0xFFF87171),
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    else
                      _actionIconBtn(
                        icon: Icons.copy_all_rounded,
                        color: const Color(0xFF38BDF8),
                        bg: const Color(0xFF0C2433),
                        tooltip: 'Duplicate Row',
                        onTap: widget.onDuplicate,
                      ),
                    const SizedBox(width: 3),
                    _actionIconBtn(
                      icon: Icons.delete_outline_rounded,
                      color: const Color(0xFFF87171),
                      bg: const Color(0xFF2A0A0A),
                      tooltip: 'Delete Row',
                      onTap: widget.onDelete,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionIconBtn({
    required IconData icon,
    required Color color,
    required Color bg,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: color.withAlpha(80)),
          ),
          child: Icon(icon, size: 13, color: color),
        ),
      ),
    );
  }
}



class _BlinkingCursor extends StatefulWidget {
  const _BlinkingCursor();

  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 530))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) => Opacity(
        opacity: _ctrl.value > 0.45 ? 1.0 : 0.0,
        child: Container(
          width: 2,
          height: 18,
          decoration: BoxDecoration(
            color: const Color(0xFF38BDF8),
            borderRadius: BorderRadius.circular(1),
            boxShadow: const [
              BoxShadow(color: Color(0xFF38BDF8), blurRadius: 4),
            ],
          ),
        ),
      ),
    );
  }
}
