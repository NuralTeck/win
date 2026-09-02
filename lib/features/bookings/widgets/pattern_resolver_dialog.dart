import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/pattern_matcher_service.dart';

class PatternResolverDialog extends StatefulWidget {
  final Function(List<ParsedTicketItem> tickets, String sender, String? senderName)? onTicketsResolved;

  const PatternResolverDialog({
    super.key,
    this.onTicketsResolved,
  });

  @override
  State<PatternResolverDialog> createState() => _PatternResolverDialogState();
}

class _PatternResolverDialogState extends State<PatternResolverDialog> {
  List<UnparsedMessage> _unparsedList = [];
  UnparsedMessage? _selectedMessage;
  bool _isLoading = true;

  // Pattern Resolver Inputs
  final TextEditingController _patternNameCtrl = TextEditingController(text: 'Custom Learned Pattern');
  final TextEditingController _regexCtrl = TextEditingController();
  final TextEditingController _sampleCtrl = TextEditingController();

  int _seriesGroup = 1;
  int _ticketGroup = 2;
  int _qtyGroup = 3;

  List<ParsedTicketItem> _testPreviewTickets = [];
  String? _testError;

  @override
  void initState() {
    super.initState();
    _loadUnparsedMessages();
  }

  @override
  void dispose() {
    _patternNameCtrl.dispose();
    _regexCtrl.dispose();
    _sampleCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUnparsedMessages() async {
    setState(() => _isLoading = true);
    final list = await PatternMatcherService.instance.fetchPendingUnparsedMessages();
    if (mounted) {
      setState(() {
        _unparsedList = list;
        _isLoading = false;
        if (list.isNotEmpty) {
          _selectMessage(list.first);
        } else {
          _selectedMessage = null;
        }
      });
    }
  }

  bool _isDateOrShiftText(String raw) {
    final clean = raw.trim();
    final isPureDate = RegExp(r'^\s*(\d{1,2}[=\/\.-]\d{1,2}[=\/\.-]\d{2,4}|\d{1,2}[=\/\.-]\d{1,2}|today|tomorrow|aaj|kal)\s*$', caseSensitive: false).hasMatch(clean);
    final isPureShift = RegExp(r'^\s*(?:=)?\s*(?:dear\s*)?[168]\s*(?:pm|am|gm|baje)\s*$', caseSensitive: false).hasMatch(clean);
    final isPureName = RegExp(r'^(?:name:?\s*)?[A-Za-z]{3,20}\s*(?:boakg|booking|bokg|bok|bkg)$', caseSensitive: false).hasMatch(clean);
    return isPureDate || isPureShift || isPureName;
  }

  void _selectMessage(UnparsedMessage msg) {
    setState(() {
      _selectedMessage = msg;
      _sampleCtrl.text = msg.rawText;
      _autoGenerateSuggestedRegex(msg.rawText);
      _runTestParse();
    });
  }

  /// Auto-detects structure and suggests an initial regex
  void _autoGenerateSuggestedRegex(String sample) {
    final lines = sample.split(RegExp(r'[\r\n]+'));
    final firstLine = lines.firstWhere(
      (l) => l.trim().isNotEmpty && RegExp(r'\d{5}').hasMatch(l),
      orElse: () => sample.trim(),
    );

    // Case 1: Combined Shift Tag + Series + 5-Digit Ticket e.g. "8gm12c62393", "8pm12c62393", "8gm 12c 62393"
    if (RegExp(r'(?:[168]\s*(?:gm|pm|am|g|p))?[\s-_=]*([0-9]{1,3}[A-Za-z]?)\s*[-:,\/=\s]*(\d{5})', caseSensitive: false).hasMatch(firstLine)) {
      _regexCtrl.text = r'(?:[168]\s*(?:gm|pm|am|g|p))?[\s-_=]*([0-9]{1,3}[A-Za-z]?)\s*[-:,\/=\s]*(\d{5})(?:\s*[-*=xX]\s*(\d+))?';
      _seriesGroup = 1;
      _ticketGroup = 2;
      _qtyGroup = 3;
      return;
    }

    // Case 2: Bracket series e.g. "(40) 12345"
    if (RegExp(r'[\(\[]\s*([0-9]{1,3}[A-Za-z]?)\s*[\)\]]\s*[-:,\/=\s]*(\d{5})').hasMatch(firstLine)) {
      _regexCtrl.text = r'[\(\[]\s*([0-9]{1,3}[A-Za-z]?)\s*[\)\]]\s*[-:,\/=\s]*(\d{5})(?:\s*[-*=xX]\s*(\d+))?';
      _seriesGroup = 1;
      _ticketGroup = 2;
      _qtyGroup = 3;
      return;
    }

    // Case 3: Inverted e.g. "12345=12"
    if (RegExp(r'(\d{5})\s*[-:,\/=]\s*([0-9]{1,3}[A-Za-z]?)').hasMatch(firstLine)) {
      _regexCtrl.text = r'(\d{5})\s*[-:,\/=]\s*([0-9]{1,3}[A-Za-z]?)(?:\s*[-*=xX]\s*(\d+))?';
      _ticketGroup = 1;
      _seriesGroup = 2;
      _qtyGroup = 3;
      return;
    }

    // Default universal fallback template
    _regexCtrl.text = r'([0-9]{1,3}[A-Za-z]?)\s*[-:,\/=\s]+\s*(\d{5})(?:\s*[-*=xX]\s*(\d+))?';
    _seriesGroup = 1;
    _ticketGroup = 2;
    _qtyGroup = 3;
  }

  void _runTestParse() {
    final pattern = _regexCtrl.text.trim();
    final text = _sampleCtrl.text.trim();

    if (pattern.isEmpty || text.isEmpty) {
      setState(() {
        _testPreviewTickets = [];
        _testError = null;
      });
      return;
    }

    try {
      final regex = RegExp(pattern, caseSensitive: false, multiLine: true);
      final items = <ParsedTicketItem>[];
      final lines = text.split(RegExp(r'[\r\n]+'));

      for (final line in lines) {
        final l = line.trim();
        if (l.isEmpty) continue;

        final match = regex.firstMatch(l);
        if (match != null) {
          String s = '12';
          if (_seriesGroup > 0 && match.groupCount >= _seriesGroup) {
            final rawS = match.group(_seriesGroup);
            if (rawS != null && rawS.isNotEmpty) {
              s = PatternMatcherService.instance.cleanSeriesNumber(rawS);
            }
          }

          String tNo = '';
          if (_ticketGroup > 0 && match.groupCount >= _ticketGroup) {
            tNo = match.group(_ticketGroup) ?? '';
          }

          int qty = 1;
          if (_qtyGroup > 0 && match.groupCount >= _qtyGroup) {
            final rawQty = match.group(_qtyGroup);
            if (rawQty != null) {
              qty = int.tryParse(rawQty) ?? 1;
            }
          }

          if (tNo.length == 5) {
            items.add(ParsedTicketItem(
              series: s.isNotEmpty && s != '?' ? s : _selectedSeriesOverride,
              ticketNo: tNo,
              quantity: qty > 0 ? qty : 1,
            ));
          }
        }
      }

      // Auto Fallback: If regex didn't extract tickets or missed some, extract all 5-digit numbers from raw text!
      if (items.isEmpty) {
        final all5s = RegExp(r'\b\d{5}\b').allMatches(text);
        for (final m in all5s) {
          items.add(ParsedTicketItem(
            series: _selectedSeriesOverride,
            ticketNo: m.group(0)!,
            quantity: 1,
          ));
        }
      }

      setState(() {
        _testPreviewTickets = items;
        _testError = items.isEmpty ? 'No 5-digit tickets found in this message.' : null;
      });
    } catch (e) {
      // If regex failed, still extract raw 5-digit tickets!
      final all5s = RegExp(r'\b\d{5}\b').allMatches(text);
      final items = all5s.map((m) => ParsedTicketItem(
        series: _selectedSeriesOverride,
        ticketNo: m.group(0)!,
        quantity: 1,
      )).toList();

      setState(() {
        _testPreviewTickets = items;
        _testError = items.isEmpty ? 'Invalid Regex: $e' : null;
      });
    }
  }

  String _selectedSeriesOverride = '12';

  void _applySeriesToAll(String newSeries) {
    final clean = PatternMatcherService.instance.cleanSeriesNumber(newSeries, fallback: newSeries.isNotEmpty ? newSeries : '12');
    setState(() {
      _selectedSeriesOverride = clean;
      _testPreviewTickets = _testPreviewTickets.map((t) => ParsedTicketItem(
        series: clean,
        ticketNo: t.ticketNo,
        quantity: t.quantity,
      )).toList();
    });
  }

  Future<void> _saveAndTrainBot() async {
    if (_selectedMessage == null || _testPreviewTickets.isEmpty) return;

    final newPattern = LearnedPattern(
      patternName: _patternNameCtrl.text.trim().isEmpty ? 'Custom Learned Pattern' : _patternNameCtrl.text.trim(),
      regexPattern: _regexCtrl.text.trim(),
      seriesGroupIndex: _seriesGroup,
      ticketGroupIndex: _ticketGroup,
      qtyGroupIndex: _qtyGroup,
      sampleText: _selectedMessage!.rawText,
    );

    // 1. Save pattern to database & memory cache
    await PatternMatcherService.instance.saveLearnedPattern(newPattern);

    // 2. Mark unparsed message as resolved
    await PatternMatcherService.instance.updateUnparsedStatus(_selectedMessage!.id, status: 'resolved');

    // 3. Callback to book tickets into Live UI table
    if (widget.onTicketsResolved != null) {
      widget.onTicketsResolved!(
        _testPreviewTickets,
        _selectedMessage!.senderPhone,
        _selectedMessage!.senderName,
      );
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Bot Learned New Pattern! ${_testPreviewTickets.length} ticket(s) pushed to booking table.'),
          backgroundColor: AppColors.success,
        ),
      );
      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  Future<void> _ignoreCurrentMessage() async {
    if (_selectedMessage == null) return;
    await PatternMatcherService.instance.updateUnparsedStatus(_selectedMessage!.id, status: 'ignored');
    await _loadUnparsedMessages();
  }

  Future<void> _clearAllPendingMessages() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerHigh,
        title: const Row(
          children: [
            Icon(Icons.delete_sweep_rounded, color: Colors.orangeAccent),
            SizedBox(width: 8),
            Text('Dismiss All Pending Messages?'),
          ],
        ),
        content: const Text('Are you sure you want to dismiss all pending date/setup and unparsed messages?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Dismiss All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await PatternMatcherService.instance.clearAllPendingUnparsedMessages();
      await _loadUnparsedMessages();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Container(
        width: 950,
        height: 650,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Dialog Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.psychology_rounded, color: AppColors.primary, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'WhatsApp Pattern Resolver & Bot AI Trainer',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                      Text(
                        'Map unknown seller messages to train the bot for 100% future auto-booking accuracy.',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(color: AppColors.border, height: 24),

            // Content Area
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _unparsedList.isEmpty
                      ? _buildEmptyState()
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Left Queue List
                            Container(
                              width: 280,
                              decoration: BoxDecoration(
                                color: AppColors.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.mark_chat_unread_rounded, size: 16, color: AppColors.warning),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Pending Messages (${_unparsedList.length})',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete_sweep_outlined, size: 18, color: Colors.orangeAccent),
                                          tooltip: 'Dismiss All Pending Messages',
                                          visualDensity: VisualDensity.compact,
                                          onPressed: _clearAllPendingMessages,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Divider(color: AppColors.border, height: 1),
                                  Expanded(
                                    child: ListView.separated(
                                      itemCount: _unparsedList.length,
                                      separatorBuilder: (_, _) => const Divider(color: AppColors.border, height: 1),
                                      itemBuilder: (context, idx) {
                                        final msg = _unparsedList[idx];
                                        final isSelected = _selectedMessage?.id == msg.id;
                                        final isConfig = _isDateOrShiftText(msg.rawText);

                                        return ListTile(
                                          dense: true,
                                          selected: isSelected,
                                          selectedTileColor: AppColors.primary.withValues(alpha: 0.15),
                                          title: Row(
                                            children: [
                                              if (isConfig)
                                                const Padding(
                                                  padding: EdgeInsets.only(right: 6),
                                                  child: Icon(Icons.calendar_month, size: 13, color: Colors.lightBlueAccent),
                                                ),
                                              Expanded(
                                                child: Text(
                                                  msg.senderName ?? msg.senderPhone,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                                    color: isSelected ? AppColors.primary : AppColors.textPrimary,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          subtitle: Text(
                                            msg.rawText.replaceAll('\n', ' '),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isConfig ? Colors.lightBlueAccent.withAlpha(200) : AppColors.textSecondary,
                                            ),
                                          ),
                                          onTap: () => _selectMessage(msg),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),

                            // Right Mapping & Training Editor
                            Expanded(
                              child: _selectedMessage == null
                                  ? const SizedBox.shrink()
                                  : SingleChildScrollView(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // Informational Banner for Date / Shift Messages
                                          if (_isDateOrShiftText(_selectedMessage!.rawText))
                                            Container(
                                              margin: const EdgeInsets.only(bottom: 12),
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: Colors.blueAccent.withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.5)),
                                              ),
                                              child: Row(
                                                children: [
                                                  const Icon(Icons.calendar_today_rounded, color: Colors.lightBlueAccent, size: 20),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Text(
                                                      '📅 "${_selectedMessage!.rawText}" is a Draw Date / Shift setup message (not a ticket format).\nThe bot stores this in session for all following tickets. Click "Dismiss" to remove from queue.',
                                                      style: const TextStyle(fontSize: 12, color: Colors.white),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  ElevatedButton.icon(
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: Colors.redAccent.withValues(alpha: 0.8),
                                                      foregroundColor: Colors.white,
                                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                      visualDensity: VisualDensity.compact,
                                                    ),
                                                    icon: const Icon(Icons.delete_outline, size: 14),
                                                    label: const Text('DISMISS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                                    onPressed: _ignoreCurrentMessage,
                                                  ),
                                                ],
                                              ),
                                            ),

                                          // Raw Message Box
                                          const Text('Raw Incoming Text:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                          const SizedBox(height: 6),
                                          TextField(
                                            controller: _sampleCtrl,
                                            maxLines: 3,
                                            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                                            decoration: InputDecoration(
                                              filled: true,
                                              fillColor: AppColors.surfaceContainerHigh,
                                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                              contentPadding: const EdgeInsets.all(10),
                                            ),
                                            onChanged: (_) => _runTestParse(),
                                          ),
                                          const SizedBox(height: 14),

                                          // Regex Rule Pattern
                                          const Text('Generated Dynamic Regex Pattern:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                          const SizedBox(height: 6),
                                          TextField(
                                            controller: _regexCtrl,
                                            style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: AppColors.tertiary),
                                            decoration: InputDecoration(
                                              filled: true,
                                              fillColor: AppColors.surfaceContainerHigh,
                                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                              contentPadding: const EdgeInsets.all(10),
                                              suffixIcon: IconButton(
                                                icon: const Icon(Icons.play_arrow_rounded, color: AppColors.primary),
                                                tooltip: 'Test Regex',
                                                onPressed: _runTestParse,
                                              ),
                                            ),
                                            onChanged: (_) => _runTestParse(),
                                          ),
                                          const SizedBox(height: 14),

                                          // Group Captures
                                          Row(
                                            children: [
                                              Expanded(
                                                child: _buildGroupSelector('Series Group #', _seriesGroup, (val) {
                                                  setState(() => _seriesGroup = val);
                                                  _runTestParse();
                                                }),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: _buildGroupSelector('5-Digit Ticket Group #', _ticketGroup, (val) {
                                                  setState(() => _ticketGroup = val);
                                                  _runTestParse();
                                                }),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: _buildGroupSelector('Quantity Group #', _qtyGroup, (val) {
                                                  setState(() => _qtyGroup = val);
                                                  _runTestParse();
                                                }),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 16),

                                          // Quick Series Fix / Override Bar
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF1E293B),
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(color: Colors.amberAccent.withAlpha(100)),
                                            ),
                                            child: Row(
                                              children: [
                                                const Icon(Icons.bolt_rounded, color: Colors.amberAccent, size: 18),
                                                const SizedBox(width: 8),
                                                const Text(
                                                  'Fix Series To All:',
                                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.amberAccent),
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Wrap(
                                                    spacing: 6,
                                                    runSpacing: 4,
                                                    children: ['12', '24', '36', '40', '60', '100'].map((s) {
                                                      final isSel = _selectedSeriesOverride == s;
                                                      return InkWell(
                                                        onTap: () => _applySeriesToAll(s),
                                                        borderRadius: BorderRadius.circular(6),
                                                        child: Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                          decoration: BoxDecoration(
                                                            color: isSel ? Colors.amberAccent.withAlpha(50) : AppColors.surfaceContainerHigh,
                                                            borderRadius: BorderRadius.circular(6),
                                                            border: Border.all(color: isSel ? Colors.amberAccent : Colors.white24, width: isSel ? 1.5 : 1),
                                                          ),
                                                          child: Text(
                                                            'Series $s',
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              fontWeight: isSel ? FontWeight.w900 : FontWeight.bold,
                                                              color: isSel ? Colors.amberAccent : Colors.white70,
                                                            ),
                                                          ),
                                                        ),
                                                      );
                                                    }).toList(),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 16),

                                          // Test Status Output
                                          if (_testError != null)
                                            Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: AppColors.error.withValues(alpha: 0.1),
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: AppColors.error),
                                              ),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  const Row(
                                                    children: [
                                                      Icon(Icons.error_outline, color: AppColors.error, size: 16),
                                                      SizedBox(width: 6),
                                                      Text('Matching Status: Error', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.error)),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(_testError!, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                                ],
                                              ),
                                            )
                                          else
                                            Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: AppColors.success.withValues(alpha: 0.1),
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: AppColors.success),
                                              ),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 16),
                                                      const SizedBox(width: 6),
                                                      Text(
                                                        'Matching Status: SUCCESS (${_testPreviewTickets.length} Tickets Found)',
                                                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.success),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Wrap(
                                                    spacing: 8,
                                                    runSpacing: 6,
                                                    children: _testPreviewTickets.map((t) {
                                                      return Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                        decoration: BoxDecoration(
                                                          color: AppColors.surfaceContainerHigh,
                                                          borderRadius: BorderRadius.circular(6),
                                                          border: Border.all(color: AppColors.tertiary),
                                                        ),
                                                        child: Text(
                                                          'Series ${t.series} • #${t.ticketNo}${t.quantity > 1 ? ' (x${t.quantity})' : ''}',
                                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                                        ),
                                                      );
                                                    }).toList(),
                                                  ),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                            ),
                          ],
                        ),
            ),
            const Divider(color: AppColors.border, height: 24),

            // Dialog Footer Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (_selectedMessage != null)
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: AppColors.error),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Ignore / Dismiss Message'),
                    onPressed: _ignoreCurrentMessage,
                  )
                else
                  const SizedBox.shrink(),
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      icon: const Icon(Icons.smart_toy_rounded, size: 18),
                      label: Text(
                        _testPreviewTickets.isEmpty
                            ? 'Train & Save Pattern'
                            : 'Train Bot & Book ${_testPreviewTickets.length} Ticket(s)',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: _testPreviewTickets.isEmpty ? null : _saveAndTrainBot,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupSelector(String label, int currentVal, ValueChanged<int> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: currentVal,
              isExpanded: true,
              dropdownColor: AppColors.surfaceContainerHigh,
              items: [1, 2, 3, 4, 5].map((i) {
                return DropdownMenuItem<int>(
                  value: i,
                  child: Text('Group #$i', style: const TextStyle(fontSize: 12)),
                );
              }).toList(),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 48),
          ),
          const SizedBox(height: 16),
          const Text(
            'All WhatsApp Messages Successfully Parsed!',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 6),
          const Text(
            'There are currently no unparsed or unrecognized seller messages pending resolution.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
