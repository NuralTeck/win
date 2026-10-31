import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../operations/models/winning_claim_model.dart';

class WinningTicketsDialog extends StatelessWidget {
  final List<WinningClaimModel> winners;
  final String partyName;

  const WinningTicketsDialog({
    super.key,
    required this.winners,
    required this.partyName,
  });

  double get _totalPrize => winners.fold(0.0, (sum, w) => sum + w.prizeAmount);

  void _copyToWhatsApp(BuildContext context) {
    final currencyFormatter = NumberFormat('#,##,###');
    final buffer = StringBuffer();
    buffer.writeln('🎉 *LOTTERY WINNING TICKET ALERT* 🎉');
    buffer.writeln('👤 *Party:* ${partyName.isNotEmpty ? partyName : "Customer"}');
    buffer.writeln('🏆 *Total Winners:* ${winners.length} Ticket(s)');
    buffer.writeln('💰 *Total Winning Inam:* ₹${currencyFormatter.format(_totalPrize)}');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━');
    for (int i = 0; i < winners.length; i++) {
      final w = winners[i];
      buffer.writeln('${i + 1}. *${w.prizeTier}*');
      buffer.writeln('   🎟️ *Ticket:* #${w.ticketNumber} (S${w.ticketSeries})');
      buffer.writeln('   🎯 *Matched:* ${w.winningNumber}');
      buffer.writeln('   📅 *Draw:* ${w.drawName}');
      buffer.writeln('   💵 *Inam:* ₹${currencyFormatter.format(w.prizeAmount)}');
      if (w.seriesCount > 1) {
        buffer.writeln('   ✖️ *Multiplier:* ${w.seriesCount} Series');
      }
      buffer.writeln('');
    }
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('✨ *Mubaarak Ho! Radhe Radhe* ✨');

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 20),
            SizedBox(width: 8),
            Text('📋 Winning summary copied to clipboard for WhatsApp!'),
          ],
        ),
        backgroundColor: Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Color _getTierColor(String prizeTier) {
    final lower = prizeTier.toLowerCase();
    if (lower.contains('1st')) return const Color(0xFFFFD700);
    if (lower.contains('2nd')) return const Color(0xFF38BDF8);
    if (lower.contains('3rd')) return const Color(0xFFFB923C);
    if (lower.contains('4th')) return const Color(0xFFA855F7);
    return const Color(0xFF10B981);
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat('#,##,###');

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Container(
        width: 650,
        constraints: const BoxConstraints(maxHeight: 720),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A), // Dark elegant slate
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.amberAccent.withValues(alpha: 0.6),
            width: 1.8,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.amberAccent.withValues(alpha: 0.18),
              blurRadius: 28,
              spreadRadius: 4,
            ),
            const BoxShadow(
              color: Colors.black54,
              blurRadius: 20,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── TOP CELEBRATION HEADER ──────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.amber.shade900.withValues(alpha: 0.5),
                    const Color(0xFF1E293B),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                border: Border(
                  bottom: BorderSide(
                    color: Colors.amberAccent.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.amberAccent.withValues(alpha: 0.6),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.emoji_events_rounded,
                      color: Colors.amberAccent,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Text(
                              '🎉 WINNING TICKET DETECTED! 🎉',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                                color: Colors.amberAccent,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Party "${partyName.isNotEmpty ? partyName : 'Customer'}" ke booked tickets me inam match hua hai!',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white60),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // ── QUICK METRICS BANNER ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                children: [
                  // Total Winners Card
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'WINNERS COUNT',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.tealAccent,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${winners.length} Ticket${winners.length > 1 ? 's' : ''}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Total Prize Inam Card
                  Expanded(
                    flex: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.amber.shade800.withValues(alpha: 0.3),
                            const Color(0xFF1E293B),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amberAccent, width: 1.2),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'TOTAL WINNING INAM (₹)',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.amberAccent,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '₹${currencyFormatter.format(_totalPrize)}',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: Colors.amberAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Party Name Card
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'PARTY / BUYER',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.cyanAccent,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            partyName.isNotEmpty ? partyName : 'Customer',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── SCROLLABLE LIST OF WINNING TICKETS ────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ListView.separated(
                  itemCount: winners.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final w = winners[index];
                    final tierColor = _getTierColor(w.prizeTier);

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: tierColor.withValues(alpha: 0.4),
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Left prize tier badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: tierColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: tierColor, width: 1),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  w.prizeTier,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: tierColor,
                                  ),
                                ),
                                if (w.seriesCount > 1) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    '${w.seriesCount}x Series',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w600,
                                      color: tierColor.withValues(alpha: 0.8),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),

                          // Middle ticket details
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    // Series badge
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: Colors.blueGrey.withValues(alpha: 0.4),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: Colors.blueGrey.shade400, width: 0.8),
                                      ),
                                      child: Text(
                                        'S${w.ticketSeries}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Ticket Number
                                    Text(
                                      '#${w.ticketNumber}',
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.amberAccent,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 5),
                                Row(
                                  children: [
                                    const Icon(Icons.check_circle_outline, size: 12, color: Colors.greenAccent),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Matched: ${w.winningNumber}',
                                      style: const TextStyle(fontSize: 11.5, color: Colors.greenAccent, fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(width: 10),
                                    const Text('•', style: TextStyle(color: Colors.white24, fontSize: 10)),
                                    const SizedBox(width: 10),
                                    const Icon(Icons.access_time_rounded, size: 12, color: Colors.white60),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        w.drawName,
                                        style: const TextStyle(fontSize: 11.5, color: Colors.white70),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          // Right winning inam amount
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '₹${currencyFormatter.format(w.prizeAmount)}',
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.greenAccent,
                                ),
                              ),
                              if (w.seriesCount > 1 && w.baseAmount > 0)
                                Text(
                                  '₹${currencyFormatter.format(w.baseAmount)} × ${w.seriesCount}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.white54,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),

            // ── BOTTOM ACTIONS ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: const BoxDecoration(
                color: Color(0xFF0B132B),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(18)),
              ),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.tealAccent,
                      side: const BorderSide(color: Colors.tealAccent),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.share_rounded, size: 16),
                    label: const Text('WhatsApp Copy', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () => _copyToWhatsApp(context),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amberAccent.shade700,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.done_all_rounded, size: 18),
                    label: const Text(
                      'Done & Continue',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
