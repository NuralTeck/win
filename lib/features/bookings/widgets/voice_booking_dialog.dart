import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/database/database_service.dart';
import '../services/gemini_scanner_service.dart';
import '../services/voice_booking_service.dart';
import '../../settings/viewmodels/series_price_viewmodel.dart';
import '../viewmodels/ticket_sales_viewmodel.dart';
import '../../shared/models/ticket_sale_model.dart';

class VoiceBookingDialog extends ConsumerStatefulWidget {
  final String activeShift;
  final DateTime activeDate;
  final String defaultSeller;
  final Function(List<GeminiScannedItem> tickets, String shift, DateTime date, String seller)? onConfirmed;

  const VoiceBookingDialog({
    super.key,
    required this.activeShift,
    required this.activeDate,
    required this.defaultSeller,
    this.onConfirmed,
  });

  @override
  ConsumerState<VoiceBookingDialog> createState() => _VoiceBookingDialogState();
}

class _VoiceBookingDialogState extends ConsumerState<VoiceBookingDialog> with SingleTickerProviderStateMixin {
  final TextEditingController _speechTextCtrl = TextEditingController();
  final TextEditingController _customerCtrl = TextEditingController();
  final TextEditingController _customSeriesCtrl = TextEditingController(text: '12');

  late AnimationController _animCtrl;
  late Animation<double> _scaleAnim;

  bool _isListening = false;
  bool _isProcessing = false;
  bool _isSaving = false;
  String? _statusMessage;
  String _selectedShift = 'Dear 1 PM';
  DateTime _selectedDate = DateTime.now();

  String _activeBotMode = 'auto';
  List<GeminiScannedItem> _parsedTickets = [];

  @override
  void initState() {
    super.initState();
    _selectedShift = widget.activeShift.isNotEmpty && widget.activeShift != 'All Shifts' ? widget.activeShift : 'Dear 1 PM';
    _selectedDate = widget.activeDate;
    _customerCtrl.text = widget.defaultSeller.isNotEmpty ? widget.defaultSeller : 'Walk-in Customer';

    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat(reverse: true);
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.22).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut));

    // Load persistent bot mode
    DatabaseService.instance.getBotMode().then((m) {
      if (mounted) setState(() => _activeBotMode = m);
    });

    // Automatically trigger initial listening on dialog open for maximum convenience
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startListening();
    });
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _speechTextCtrl.dispose();
    _customerCtrl.dispose();
    _customSeriesCtrl.dispose();
    VoiceBookingService.instance.stopListening();
    super.dispose();
  }

  double _getPriceForSeries(String series) {
    if (series.isEmpty || series == '?') return 0.0;
    final seriesState = ref.read(seriesPriceViewModelProvider);
    return seriesState.getPriceForSeries(series);
  }

  double get _totalAmount {
    return _parsedTickets.fold(0.0, (sum, t) => sum + (t.amount * t.quantity));
  }

  Future<void> _startListening() async {
    if (_isListening) return;
    setState(() {
      _isListening = true;
      _statusMessage = '🎙️ Listening... Please speak your numbers now!';
    });

    final recognized = await VoiceBookingService.instance.listenFromMicrophoneOffline(timeoutSeconds: 8);

    if (!mounted) return;

    setState(() {
      _isListening = false;
    });

    if (recognized != null && recognized.trim().isNotEmpty) {
      _speechTextCtrl.text = recognized.trim();
      _processSpokenText(recognized.trim());
    } else {
      setState(() {
        _statusMessage = '⚠️ No clear speech heard. Click Mic to try again or type in the box!';
      });
    }
  }

  Future<void> _processSpokenText(String text) async {
    if (text.trim().isEmpty) return;
    setState(() {
      _isProcessing = true;
      _statusMessage = '⚡ Parsing your spoken numbers...';
    });

    final currentSeries = _customSeriesCtrl.text.trim().isNotEmpty ? _customSeriesCtrl.text.trim() : '12';
    final price = _getPriceForSeries(currentSeries);

    final result = await VoiceBookingService.instance.parseSpokenTicketText(
      spokenText: text,
      defaultSeries: currentSeries,
      defaultSeller: _customerCtrl.text.trim(),
      defaultPrice: price,
      overrideMode: _activeBotMode,
    );

    if (!mounted) return;

    setState(() {
      _isProcessing = false;
      _parsedTickets = result.tickets;

      if (result.detectedShift != null) {
        _selectedShift = result.detectedShift!;
      }
      if (result.detectedSeller != null && result.detectedSeller!.isNotEmpty) {
        _customerCtrl.text = result.detectedSeller!;
      }

      // Recalculate series price for each item
      for (final t in _parsedTickets) {
        t.amount = _getPriceForSeries(t.series);
      }

      if (_parsedTickets.isNotEmpty) {
        _statusMessage = '✅ Extracted ${_parsedTickets.length} number(s) via ${result.isOnlineAiUsed ? "🌐 Online AI" : "💻 Offline Speech"}!';
      } else {
        _statusMessage = '⚠️ Could not find 5-digit numbers in spoken text. You can edit the text and click Parse!';
      }
    });
  }

  void _applySeriesToAll(String series) {
    if (series.trim().isEmpty) return;
    setState(() {
      final clean = series.trim().toUpperCase();
      final p = _getPriceForSeries(clean);
      for (final t in _parsedTickets) {
        t.series = clean;
        t.amount = p;
      }
    });
  }

  void _addNewRow() {
    setState(() {
      final s = _customSeriesCtrl.text.trim().isNotEmpty ? _customSeriesCtrl.text.trim() : '12';
      _parsedTickets.add(GeminiScannedItem(
        series: s,
        ticketNo: '',
        amount: _getPriceForSeries(s),
        quantity: 1,
        sellerName: _customerCtrl.text.trim(),
      ));
    });
  }

  Future<void> _saveAndConfirmAll() async {
    if (_parsedTickets.isEmpty) return;
    setState(() => _isSaving = true);

    final seller = _customerCtrl.text.trim().isNotEmpty ? _customerCtrl.text.trim() : 'Walk-in Customer';

    if (widget.onConfirmed != null) {
      widget.onConfirmed!(_parsedTickets, _selectedShift, _selectedDate, seller);
      Navigator.of(context).pop(true);
      return;
    }

    // Direct booking into ViewModel
    int count = 0;
    for (final t in _parsedTickets) {
      if (t.ticketNo.trim().length != 5) continue;
      final uniqueMicro = DateTime.now().microsecondsSinceEpoch + count;
      final newSale = TicketSaleModel(
        id: 'tkt_voice_${uniqueMicro}_${t.series}_${t.ticketNo}',
        receiptNumber: 'REC-${t.series}-${t.ticketNo}',
        buyerName: seller,
        buyerPhone: '',
        agentCode: 'AG-VOICE',
        agentName: seller,
        drawCode: _selectedShift.replaceAll(' ', '-').toUpperCase(),
        drawName: _selectedShift,
        ticketSeries: t.series,
        ticketNumber: '${t.series} ${t.ticketNo}',
        quantity: t.quantity,
        pricePerTicket: t.amount,
        totalAmount: t.amount * t.quantity,
        commissionAmount: (t.amount * t.quantity) * 0.05,
        status: TicketStatus.sold,
        paymentMode: PaymentMode.cash,
        saleDate: DateTime.now(),
        drawDate: _selectedDate,
      );

      await ref.read(ticketSalesViewModelProvider.notifier).addTicketSale(newSale);
      count++;
    }

    if (mounted) {
      setState(() => _isSaving = false);
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🎉 Successfully booked $count numbers via Voice Counter!'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0F172A),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF334155), width: 1.5),
      ),
      child: Container(
        width: 1000,
        height: 720,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Bar
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                  ),
                  child: const Icon(Icons.mic_rounded, color: AppColors.primary, size: 24),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '🎙️ Smart Voice Counter (बोलकर नंबर बुक करें)',
                      style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Hybrid Engine: 💻 100% Offline Windows Speech + 🌐 Online AI Natural NLP Support',
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 11.5),
                    ),
                  ],
                ),
                const Spacer(),
                // Dynamic Bot Mode Selector Pill
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildModeChip('auto', '⚡ Auto', Colors.purpleAccent),
                      const SizedBox(width: 3),
                      _buildModeChip('offline', '💻 Offline', Colors.cyanAccent),
                      const SizedBox(width: 3),
                      _buildModeChip('online', '🌐 Online AI', Colors.greenAccent),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.grey),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(color: Color(0xFF334155), height: 1),
            const SizedBox(height: 14),

            // Main Split Body: Left Mic/Input Panel | Right Parsed Table
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ─── LEFT PANEL: LIVE VOICE RECORDER & INPUT ───────────────────
                  SizedBox(
                    width: 360,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Big Mic Visualizer Card
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _isListening ? Colors.redAccent : const Color(0xFF334155),
                              width: _isListening ? 2.0 : 1.0,
                            ),
                          ),
                          child: Column(
                            children: [
                              GestureDetector(
                                onTap: _isListening ? () => VoiceBookingService.instance.stopListening() : _startListening,
                                child: AnimatedBuilder(
                                  animation: _scaleAnim,
                                  builder: (context, child) {
                                    return Transform.scale(
                                      scale: _isListening ? _scaleAnim.value : 1.0,
                                      child: Container(
                                        width: 76,
                                        height: 76,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: _isListening ? Colors.redAccent : AppColors.primary,
                                          boxShadow: [
                                            BoxShadow(
                                              color: (_isListening ? Colors.redAccent : AppColors.primary).withValues(alpha: 0.4),
                                              blurRadius: 20,
                                              spreadRadius: 4,
                                            ),
                                          ],
                                        ),
                                        child: Icon(
                                          _isListening ? Icons.mic : Icons.mic_none_rounded,
                                          color: Colors.white,
                                          size: 38,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                _isListening ? '🎙️ LISTENING (बोलिए...)' : 'Click Mic to Speak (माइक दबाकर बोलें)',
                                style: TextStyle(
                                  color: _isListening ? Colors.redAccent : Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _statusMessage ?? 'Example: "Series 12 56581 se 56585 rate 45"',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _statusMessage != null && _statusMessage!.contains('✅') ? Colors.greenAccent : Colors.grey.shade400,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Spoken Text Area (Editable)
                        const Text('Live Recognized Voice Text (यहाँ बोलकर लिखा आएगा):', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Expanded(
                          child: TextField(
                            controller: _speechTextCtrl,
                            maxLines: null,
                            expands: true,
                            textAlignVertical: TextAlignVertical.top,
                            style: const TextStyle(color: Colors.white, fontSize: 12.5, height: 1.4),
                            decoration: InputDecoration(
                              hintText: 'Recognized speech appears here...\n\nExamples:\n- "Series 12 56581 to 56585"\n- "Customer Ramesh Series 24 46185, 56185"\n- "100 series 28311 se 28315"',
                              hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 11.5),
                              filled: true,
                              fillColor: const Color(0xFF0B1120),
                              contentPadding: const EdgeInsets.all(12),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF334155))),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF334155))),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Action Buttons: Re-listen / Parse
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1E293B),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: Color(0xFF334155))),
                                ),
                                icon: const Icon(Icons.refresh_rounded, size: 16),
                                label: const Text('Speak Again', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                onPressed: _startListening,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                icon: _isProcessing
                                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Icon(Icons.auto_fix_high_rounded, size: 16),
                                label: const Text('Parse Text', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                onPressed: _isProcessing ? null : () => _processSpokenText(_speechTextCtrl.text),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  const VerticalDivider(color: Color(0xFF334155), width: 1),
                  const SizedBox(width: 16),

                  // ─── RIGHT PANEL: PARSED TICKETS TABLE & CONTROLS ──────────────
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Metadata Bar: Customer + Shift + Date
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF334155)),
                          ),
                          child: Row(
                            children: [
                              // Customer Name
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: _customerCtrl,
                                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                  decoration: const InputDecoration(
                                    labelText: 'Customer / Seller',
                                    labelStyle: TextStyle(color: Colors.grey, fontSize: 11),
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),

                              // Shift Dropdown
                              Expanded(
                                flex: 2,
                                child: DropdownButtonFormField<String>(
                                  initialValue: _selectedShift,
                                  dropdownColor: const Color(0xFF1E293B),
                                  style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 12),
                                  decoration: const InputDecoration(
                                    labelText: 'Shift Timing',
                                    labelStyle: TextStyle(color: Colors.grey, fontSize: 11),
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    border: OutlineInputBorder(),
                                  ),
                                  items: ['Dear 1 PM', 'Dear 6 PM', 'Dear 8 PM'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                                  onChanged: (val) {
                                    if (val != null) setState(() => _selectedShift = val);
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),

                              // Date Picker
                              InkWell(
                                onTap: () async {
                                  final first = _selectedDate.isBefore(DateTime(2020)) ? _selectedDate : DateTime(2020);
                                  final last = _selectedDate.isAfter(DateTime(2035)) ? _selectedDate : DateTime(2035);
                                  final d = await showDatePicker(
                                    context: context,
                                    initialDate: _selectedDate,
                                    firstDate: first,
                                    lastDate: last,
                                  );
                                  if (d != null) setState(() => _selectedDate = d);
                                },
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F172A),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFF334155)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.calendar_month_rounded, size: 14, color: AppColors.primary),
                                      const SizedBox(width: 6),
                                      Text(
                                        DateFormat('dd/MM/yy').format(_selectedDate),
                                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Quick Series Override Bar
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0B1120),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF334155)),
                          ),
                          child: Row(
                            children: [
                              const Text('Quick Series: ', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
                              const SizedBox(width: 6),
                              ...['12', '24', '36', '100'].map((s) {
                                return Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: InkWell(
                                    onTap: () {
                                      _customSeriesCtrl.text = s;
                                      _applySeriesToAll(s);
                                    },
                                    borderRadius: BorderRadius.circular(4),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                                      ),
                                      child: Text(
                                        'Set $s',
                                        style: const TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                              const Spacer(),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.primary,
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                ),
                                icon: const Icon(Icons.add, size: 14),
                                label: const Text('+ Add Number', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                onPressed: _addNewRow,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Parsed Tickets Table
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF0B1120),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFF334155)),
                            ),
                            child: _parsedTickets.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.mic_none_rounded, size: 40, color: Colors.grey.shade700),
                                        const SizedBox(height: 8),
                                        Text(
                                          'No numbers parsed yet.\nSpeak clearly into mic or paste/type text on the left!',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  )
                                : ListView.separated(
                                    padding: const EdgeInsets.all(8),
                                    itemCount: _parsedTickets.length,
                                    separatorBuilder: (_, _) => const Divider(color: Color(0xFF1E293B), height: 1),
                                    itemBuilder: (context, idx) {
                                      final t = _parsedTickets[idx];
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 4),
                                        child: Row(
                                          children: [
                                            SizedBox(
                                              width: 24,
                                              child: Text('#${idx + 1}', style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
                                            ),
                                            const SizedBox(width: 6),

                                            // Series
                                            SizedBox(
                                              width: 70,
                                              child: TextFormField(
                                                key: ValueKey('voice_ser_${t.hashCode}_${t.series}'),
                                                initialValue: t.series,
                                                style: const TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.bold),
                                                decoration: const InputDecoration(
                                                  labelText: 'Series',
                                                  labelStyle: TextStyle(fontSize: 10),
                                                  isDense: true,
                                                  contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                                                  border: OutlineInputBorder(),
                                                ),
                                                onChanged: (v) {
                                                  setState(() {
                                                    t.series = v.trim().toUpperCase();
                                                    t.amount = _getPriceForSeries(t.series);
                                                  });
                                                },
                                              ),
                                            ),
                                            const SizedBox(width: 8),

                                            // Ticket No
                                            Expanded(
                                              child: TextFormField(
                                                key: ValueKey('voice_tkt_${t.hashCode}_${t.ticketNo}'),
                                                initialValue: t.ticketNo,
                                                maxLength: 5,
                                                style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontWeight: FontWeight.w900, fontSize: 13),
                                                decoration: const InputDecoration(
                                                  labelText: '5-Digit Number',
                                                  labelStyle: TextStyle(fontSize: 10),
                                                  isDense: true,
                                                  counterText: '',
                                                  contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                                                  border: OutlineInputBorder(),
                                                ),
                                                onChanged: (v) => t.ticketNo = v.trim(),
                                              ),
                                            ),
                                            const SizedBox(width: 8),

                                            // Rate
                                            SizedBox(
                                              width: 75,
                                              child: TextFormField(
                                                key: ValueKey('voice_amt_${t.hashCode}_${t.amount}'),
                                                initialValue: t.amount % 1 == 0 ? t.amount.toInt().toString() : t.amount.toStringAsFixed(1),
                                                keyboardType: TextInputType.number,
                                                style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 12),
                                                decoration: const InputDecoration(
                                                  labelText: 'Rate (₹)',
                                                  labelStyle: TextStyle(fontSize: 10, color: Colors.greenAccent),
                                                  isDense: true,
                                                  contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                                                  border: OutlineInputBorder(),
                                                ),
                                                onChanged: (v) {
                                                  setState(() {
                                                    t.amount = double.tryParse(v.trim()) ?? 0.0;
                                                  });
                                                },
                                              ),
                                            ),
                                            const SizedBox(width: 4),

                                            // Delete
                                            IconButton(
                                              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                                              onPressed: () => setState(() => _parsedTickets.remove(t)),
                                            ),
                                          ],
                                        ),
                                      );
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
            const SizedBox(height: 14),
            const Divider(color: Color(0xFF334155), height: 1),
            const SizedBox(height: 12),

            // Footer KPI & Confirm Button
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    'Total Numbers: ${_parsedTickets.length}',
                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    'Total Amount: ₹${_totalAmount.toStringAsFixed(0)}',
                    style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent.shade700,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: _isSaving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : const Icon(Icons.check_circle_rounded, size: 18, color: Colors.black),
                  label: Text(
                    _isSaving ? 'Booking...' : 'Confirm & Book All (${_parsedTickets.length}) Numbers',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5, color: Colors.black),
                  ),
                  onPressed: _parsedTickets.isEmpty || _isSaving ? null : _saveAndConfirmAll,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeChip(String mode, String label, Color activeColor) {
    final isSelected = _activeBotMode == mode;
    return InkWell(
      onTap: () {
        setState(() => _activeBotMode = mode);
        DatabaseService.instance.saveBotMode(mode);
      },
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? activeColor : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? activeColor : Colors.grey.shade400,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w900 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
