import 'dart:io';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:file_picker/file_picker.dart';
import '../utils/party_hisab_settlement_engine.dart';

class PartyHisabReportService {
  PartyHisabReportService._internal();
  static final PartyHisabReportService instance = PartyHisabReportService._internal();

  /// Clean non-ASCII symbols that cause tofu boxes in standard PDF fonts
  String _cleanPdfText(String text) {
    if (text.isEmpty) return '';
    final cleaned = text.replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();
    return cleaned.isNotEmpty ? cleaned : 'Party';
  }
 


 
  String generateSummaryWhatsAppText(PartyHisabSummary summary) {
    final buffer = StringBuffer();
    final nowStr = DateFormat('dd-MMM-yyyy, hh:mm a').format(DateTime.now());

    buffer.writeln('==================================================================');
    buffer.writeln(summary.isDealer
        ? '          👑 MAIN DEALER CONSOLIDATED HISAB SUMMARY'
        : '                    📊 DAILY DRAW HISAB SUMMARY');
    buffer.writeln('==================================================================');
    if (summary.isDealer) {
      buffer.writeln('Main Dealer    : 👑 ${summary.partyName}');
      if (summary.subSellerBreakdowns.isNotEmpty) {
        buffer.writeln('Sub-Sellers    : ${summary.subSellerBreakdowns.length} Sellers (${summary.subSellerBreakdowns.map((s) => s.sellerName).join(", ")})');
      }
    } else {
      buffer.writeln('Party / Seller : 👤 ${summary.partyName}');
      if (summary.dealerName != null && summary.dealerName!.isNotEmpty) {
        buffer.writeln('Parent Dealer  : 🏢 ${summary.dealerName}');
      }
    }
    buffer.writeln('Draw Date      : ${summary.date}');
    buffer.writeln('Draw Shift     : ${summary.shift}');
    buffer.writeln('Generated At   : $nowStr');
    buffer.writeln('------------------------------------------------------------------');
    
    final hSer = 'SERIES'.padRight(9);
    final hVou = 'VOUCHER(IN)'.padRight(14);
    final hUns = 'UNSOLD(RET)'.padRight(14);
    final hNet = 'NET SOLD'.padRight(13);
    final hRat = 'RATE(Rs)'.padRight(10);
    final hAmt = 'AMOUNT(Rs)';
    final tableHeader = '$hSer$hVou$hUns$hNet$hRat$hAmt';
    buffer.writeln(tableHeader);
    buffer.writeln('-' * tableHeader.length);

    for (final s in summary.seriesHisabList) {
      final sStr = 'Ser ${s.series}'.padRight(9);
      final vStr = '${s.voucherQty} Qty'.padRight(14);
      final uStr = '${s.unsoldQty} Qty'.padRight(14);
      final nStr = '${s.netSoldQty} Qty'.padRight(13);
      final rStr = s.rate.toStringAsFixed(2).padRight(10);
      final aStr = s.netAmount.toStringAsFixed(2);
      buffer.writeln('$sStr$vStr$uStr$nStr$rStr$aStr');
    }

    buffer.writeln('-' * tableHeader.length);
    buffer.writeln('📦 TOTAL STOCK SUMMARY:');
    buffer.writeln('• Total Voucher Inward  : ${summary.totalVouchers} Tickets  (Rs. ${summary.totalVoucherAmount.toStringAsFixed(2)})');
    buffer.writeln('• Total Unsold Returned : ${summary.totalUnsold} Tickets  (Rs. ${summary.totalUnsoldAmount.toStringAsFixed(2)})');
    buffer.writeln('• Net Sold Tickets      : ${summary.totalNetSold} Tickets  (Rs. ${summary.totalNetAmount.toStringAsFixed(2)})');

    if (summary.subSellerBreakdowns.isNotEmpty) {
      buffer.writeln('------------------------------------------------------------------');
      buffer.writeln('👥 SUB-SELLER WISE BREAKDOWN:');
      for (final sb in summary.subSellerBreakdowns) {
        final nameP = sb.sellerName.padRight(14);
        final inP = 'In ${sb.totalVouchers}'.padRight(9);
        final retP = 'Ret ${sb.totalUnsold}'.padRight(9);
        final netP = 'Net ${sb.totalNetSold} Nos'.padRight(14);
        final amtP = 'Rs. ${sb.totalNetAmount.toStringAsFixed(2)}';
        final winP = sb.totalWinAmount > 0 ? ' (Inam: -Rs.${sb.totalWinAmount.toStringAsFixed(0)})' : '';
        buffer.writeln('• $nameP: $inP - $retP = $netP -> $amtP$winP -> Net: Rs.${sb.finalNetPayable.toStringAsFixed(2)}');
      }
    }

    if (summary.dateBreakdowns.isNotEmpty && (summary.dateBreakdowns.length > 1 || summary.shift == 'ALL')) {
      buffer.writeln('------------------------------------------------------------------');
      buffer.writeln('⏰ DRAW TIMINGS & DATE BREAKDOWN:');
      for (final db in summary.dateBreakdowns) {
        buffer.writeln('📅 ${db.formattedDate}:');
        for (final sb in db.shifts) {
          final shiftPadded = sb.shift.padRight(11);
          if (!sb.hasEntry) {
            buffer.writeln('   • $shiftPadded : [ Empty / No Entry ]');
          } else {
            final vStr = 'In ${sb.totalVouchers}'.padRight(10);
            final uStr = 'Ret ${sb.totalUnsold}'.padRight(10);
            final nStr = 'Net ${sb.totalNetSold} Nos'.padRight(15);
            final aStr = '(Rs. ${sb.totalNetAmount.toStringAsFixed(2)})'.padRight(17);
            final winStr = sb.customerWins.isNotEmpty ? ' | 🏆 Inam: Rs.${sb.totalCustomerWinAmount.toStringAsFixed(0)}' : '';
            buffer.writeln('   • $shiftPadded : $vStr - $uStr = $nStr $aStr$winStr');
          }
        }
      }
    }

    double totalBaseInam = 0.0;
    double totalBonus = 0.0;
    double totalIncentive = 0.0;
    for (final w in summary.customerWins) {
      totalBaseInam += (w.baseAmount * w.seriesCount);
      totalBonus += (w.superBonus * w.seriesCount);
      totalIncentive += (w.specialIncentive * w.seriesCount);
    }

    if (summary.customerWins.isNotEmpty) {
      buffer.writeln('------------------------------------------------');
      buffer.writeln('🏆 WINNING PRIZE ADJUSTMENT (CUSTOMER CLAIMS):');
      for (final w in summary.customerWins) {
        final base = w.baseAmount * w.seriesCount;
        final bonus = w.superBonus * w.seriesCount;
        final inc = w.specialIncentive * w.seriesCount;
        buffer.writeln('• ${w.prizeTier} (${w.ticketSeries} - ${w.ticketNumber}) : Inam Rs.${base.toStringAsFixed(0)} + Bonus Rs.${bonus.toStringAsFixed(0)} + Inc Rs.${inc.toStringAsFixed(0)} = Rs.${w.prizeAmount.toStringAsFixed(0)}');
      }
      buffer.writeln('• Total Base Inam       : Rs. ${totalBaseInam.toStringAsFixed(2)}');
      buffer.writeln('• Total Super Bonus     : Rs. ${totalBonus.toStringAsFixed(2)}');
      buffer.writeln('• Total Incentive       : Rs. ${totalIncentive.toStringAsFixed(2)}');
      buffer.writeln('• Total Winning Payout  : Rs. ${summary.totalCustomerWinAmount.toStringAsFixed(2)}');
      buffer.writeln('------------------------------------------------');
    }

    buffer.writeln('💰 FINAL SETTLEMENT HISAB:');
    buffer.writeln('  1. Total Voucher Inward  :   Rs. ${summary.totalVoucherAmount.toStringAsFixed(2)}');
    buffer.writeln('  2. Less Unsold Returns   : - Rs. ${summary.totalUnsoldAmount.toStringAsFixed(2)}');
    buffer.writeln('  ------------------------------------------------');
    buffer.writeln('  = Net Sold Amount (Bikri):   Rs. ${summary.totalNetAmount.toStringAsFixed(2)}');
    if (summary.customerWins.isNotEmpty) {
      buffer.writeln('  • Base Inam Deduction    : - Rs. ${totalBaseInam.toStringAsFixed(2)}');
      buffer.writeln('  • Super Bonus Deduction  : - Rs. ${totalBonus.toStringAsFixed(2)}');
      buffer.writeln('  • Incentive Deduction    : - Rs. ${totalIncentive.toStringAsFixed(2)}');
      buffer.writeln('  3. Total Winning Inam    : - Rs. ${summary.totalCustomerWinAmount.toStringAsFixed(2)}');
    }
    buffer.writeln('  ------------------------------------------------');
    buffer.writeln('  ✅ FINAL NET PAYABLE     :   Rs. ${summary.finalNetPayable.toStringAsFixed(2)}');
    buffer.writeln('================================================');

    return buffer.toString();
  }

  /// Generate Full Detailed Hisab formatted text for WhatsApp
  String generateFullDetailedWhatsAppText(PartyHisabSummary summary) {
    final buffer = StringBuffer();
    final nowStr = DateFormat('dd-MMM-yyyy, hh:mm a').format(DateTime.now());

    buffer.writeln('================================================');
    buffer.writeln('        📑 FULL DETAILED HISAB PARCHA');
    buffer.writeln('================================================');
    buffer.writeln('Party / Seller : ${summary.partyName}');
    buffer.writeln('Draw Date      : ${summary.date} | Shift: ${summary.shift}');
    buffer.writeln('Generated At   : $nowStr');
    buffer.writeln('------------------------------------------------');

    if (summary.dateBreakdowns.isNotEmpty && (summary.dateBreakdowns.length > 1 || summary.shift == 'ALL')) {
      buffer.writeln('📅 DATE & TIMINGS (SHIFT-WISE) BREAKDOWN:');
      for (final db in summary.dateBreakdowns) {
        buffer.writeln('🗓️ MAIN DATE: ${db.formattedDate}');
        for (final sb in db.shifts) {
          final shiftPadded = sb.shift.padRight(11);
          if (!sb.hasEntry) {
            buffer.writeln('   ⏰ $shiftPadded -> [ Empty / No Entry ]');
          } else {
            final winStr = sb.customerWins.isNotEmpty ? ' | 🏆 Inam: Rs.${sb.totalCustomerWinAmount.toStringAsFixed(0)}' : '';
            buffer.writeln('   ⏰ $shiftPadded -> In ${sb.totalVouchers} - Ret ${sb.totalUnsold} = Net ${sb.totalNetSold} Nos (Rs. ${sb.totalNetAmount.toStringAsFixed(2)})$winStr');
          }
        }
      }
      buffer.writeln('------------------------------------------------');
    }

    buffer.writeln('📥 1. STOCK VOUCHERS INWARD:');
    if (summary.rawVouchers.isEmpty) {
      buffer.writeln('  (No Vouchers recorded)');
    } else {
      for (int i = 0; i < summary.rawVouchers.length; i++) {
        final v = summary.rawVouchers[i];
        buffer.writeln('  ${i + 1}. [Ser ${v.series}] ${v.fromTicket}-${v.toTicket} (${v.totalQty} Nos) @ Rs.${v.pricePerTicket.toStringAsFixed(2)} = Rs.${v.totalAmount.toStringAsFixed(2)}');
      }
    }
    buffer.writeln('  Total Vouchers: ${summary.totalVouchers} Tickets (Rs. ${summary.totalVoucherAmount.toStringAsFixed(2)})');
    buffer.writeln('------------------------------------------------');

    buffer.writeln('📦 2. UNSOLD RETURNS:');
    if (summary.rawUnsold.isEmpty) {
      buffer.writeln('  (No Unsold Returns recorded)');
    } else {
      for (int i = 0; i < summary.rawUnsold.length; i++) {
        final u = summary.rawUnsold[i];
        final rangeStr = u.fromTicket == u.toTicket ? u.fromTicket : '${u.fromTicket}-${u.toTicket}';
        buffer.writeln('  ${i + 1}. [Ser ${u.series}] $rangeStr (${u.totalQty} Nos) @ Rs.${u.pricePerTicket.toStringAsFixed(2)} = Rs.${u.totalAmount.toStringAsFixed(2)}');
      }
    }
    buffer.writeln('  Total Unsold: ${summary.totalUnsold} Tickets (Rs. ${summary.totalUnsoldAmount.toStringAsFixed(2)})');
    buffer.writeln('------------------------------------------------');

    buffer.writeln('📊 3. SERIES NET SOLD BREAKDOWN:');
    for (final s in summary.seriesHisabList) {
      buffer.writeln('  • Ser ${s.series} : In ${s.voucherQty} - Ret ${s.unsoldQty} = Net ${s.netSoldQty} Nos @ Rs.${s.rate.toStringAsFixed(2)} = Rs.${s.netAmount.toStringAsFixed(2)}');
    }
    buffer.writeln('------------------------------------------------');

    double totalBaseInam = 0.0;
    double totalBonus = 0.0;
    double totalIncentive = 0.0;
    for (final w in summary.customerWins) {
      totalBaseInam += (w.baseAmount * w.seriesCount);
      totalBonus += (w.superBonus * w.seriesCount);
      totalIncentive += (w.specialIncentive * w.seriesCount);
    }

    if (summary.customerWins.isNotEmpty) {
      buffer.writeln('🏆 4. WINNING INAM, BONUS & INCENTIVE CLAIMS:');
      for (final w in summary.customerWins) {
        final base = w.baseAmount * w.seriesCount;
        final bonus = w.superBonus * w.seriesCount;
        final inc = w.specialIncentive * w.seriesCount;
        buffer.writeln('  • ${w.prizeTier} [Ser ${w.ticketSeries}] #${w.ticketNumber} : Inam Rs.${base.toStringAsFixed(0)} + Bonus Rs.${bonus.toStringAsFixed(0)} + Inc Rs.${inc.toStringAsFixed(0)} = Rs.${w.prizeAmount.toStringAsFixed(0)}');
      }
      buffer.writeln('  • Total Base Inam     : Rs. ${totalBaseInam.toStringAsFixed(2)}');
      buffer.writeln('  • Total Super Bonus   : Rs. ${totalBonus.toStringAsFixed(2)}');
      buffer.writeln('  • Total Incentive     : Rs. ${totalIncentive.toStringAsFixed(2)}');
      buffer.writeln('  = Total Winning Claims : Rs. ${summary.totalCustomerWinAmount.toStringAsFixed(2)}');
      buffer.writeln('------------------------------------------------');
    }

    buffer.writeln('💰 FINAL SETTLEMENT:');
    buffer.writeln('  1. Total Voucher Inward  : Rs. ${summary.totalVoucherAmount.toStringAsFixed(2)}');
    buffer.writeln('  2. Less Unsold Returned  : - Rs. ${summary.totalUnsoldAmount.toStringAsFixed(2)}');
    buffer.writeln('  ------------------------------------------------');
    buffer.writeln('  = Net Sold Amount (Bikri): Rs. ${summary.totalNetAmount.toStringAsFixed(2)}');
    if (summary.customerWins.isNotEmpty) {
      buffer.writeln('  • Base Inam Deduction    : - Rs. ${totalBaseInam.toStringAsFixed(2)}');
      buffer.writeln('  • Super Bonus Deduction  : - Rs. ${totalBonus.toStringAsFixed(2)}');
      buffer.writeln('  • Incentive Deduction    : - Rs. ${totalIncentive.toStringAsFixed(2)}');
      buffer.writeln('  3. Total Winning Inam    : - Rs. ${summary.totalCustomerWinAmount.toStringAsFixed(2)}');
    }
    buffer.writeln('  ------------------------------------------------');
    buffer.writeln('  ✅ NET PAYABLE AMOUNT    : Rs. ${summary.finalNetPayable.toStringAsFixed(2)}');
    buffer.writeln('================================================');

    return buffer.toString();
  }

  // ═══════════════════════════════════════════════════════════════
  // 2. PDF GENERATION & SAVING (SUMMARY & FULL)
  // ═══════════════════════════════════════════════════════════════

  /// Export Summary PDF document
  Future<String?> exportSummaryPdf(PartyHisabSummary summary) async {
    final pdf = pw.Document();
    final partyClean = _cleanPdfText(summary.partyName);
    final nowStr = DateFormat('dd-MMM-yyyy, hh:mm a').format(DateTime.now());

    double totalBaseInam = 0.0;
    double totalBonus = 0.0;
    double totalIncentive = 0.0;
    for (final w in summary.customerWins) {
      totalBaseInam += (w.baseAmount * w.seriesCount);
      totalBonus += (w.superBonus * w.seriesCount);
      totalIncentive += (w.specialIncentive * w.seriesCount);
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context ctx) {
          return [
            // Top Header
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: const pw.BoxDecoration(
                color: PdfColors.blue900,
                borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('PARTY HISAB SUMMARY REPORT', style: pw.TextStyle(color: PdfColors.white, fontSize: 16, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 2),
                      pw.Text('Party: $partyClean', style: pw.TextStyle(color: PdfColors.amber200, fontSize: 12, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Date: ${summary.date} | Shift: ${summary.shift}', style: const pw.TextStyle(color: PdfColors.white, fontSize: 10)),
                      pw.Text('Generated: $nowStr', style: const pw.TextStyle(color: PdfColors.grey300, fontSize: 9)),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 14),

            // Series Table
            pw.Text('SERIES-WISE STOCK & SETTLEMENT TABLE', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800)),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headers: ['Series', 'Voucher In', 'Unsold Ret', 'Net Sold', 'Rate (Rs)', 'Net Amount (Rs)'],
              data: summary.seriesHisabList.map((s) => [
                'Ser ${s.series}',
                '${s.voucherQty} Nos',
                '${s.unsoldQty} Nos',
                '${s.netSoldQty} Nos',
                s.rate.toStringAsFixed(2),
                s.netAmount.toStringAsFixed(2),
              ]).toList(),
              headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blue800),
              rowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
              cellAlignment: pw.Alignment.center,
              cellStyle: const pw.TextStyle(fontSize: 9.5),
            ),
            pw.SizedBox(height: 14),

            // Date & Shift Breakdown Table if Multi-Date or Shift == ALL
            if (summary.dateBreakdowns.isNotEmpty && (summary.dateBreakdowns.length > 1 || summary.shift == 'ALL')) ...[
              pw.Text(
                summary.dateBreakdowns.length > 1
                    ? 'DATE & SHIFT-WISE TIMINGS BREAKDOWN'
                    : 'DRAW TIMINGS BREAKDOWN (1 PM • 6 PM • 8 PM)',
                style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900),
              ),
              pw.SizedBox(height: 4),
              pw.TableHelper.fromTextArray(
                columnWidths: const {
                  0: pw.FlexColumnWidth(2.2),
                  1: pw.FlexColumnWidth(1.6),
                  2: pw.FlexColumnWidth(1.4),
                  3: pw.FlexColumnWidth(1.4),
                  4: pw.FlexColumnWidth(1.4),
                  5: pw.FlexColumnWidth(2.0),
                  6: pw.FlexColumnWidth(1.5),
                  7: pw.FlexColumnWidth(1.8),
                },
                headers: ['Date', 'Draw Shift / Timing', 'Voucher In', 'Unsold Ret', 'Net Sold', 'Net Amount (Rs)', 'Inam (Rs)', 'Status'],
                data: [
                  for (final db in summary.dateBreakdowns)
                    for (final sb in db.shifts)
                      [
                        db.formattedDate,
                        sb.shift,
                        sb.hasEntry ? '${sb.totalVouchers} Nos' : '-',
                        sb.hasEntry ? '${sb.totalUnsold} Nos' : '-',
                        sb.hasEntry ? '${sb.totalNetSold} Nos' : '-',
                        sb.hasEntry ? 'Rs. ${sb.totalNetAmount.toStringAsFixed(2)}' : '-',
                        sb.customerWins.isNotEmpty ? 'Rs. ${sb.totalCustomerWinAmount.toStringAsFixed(0)}' : '-',
                        sb.hasEntry ? 'Active' : 'Empty / No Entry',
                      ],
                ],
                headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 8.5),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo800),
                rowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
                cellAlignment: pw.Alignment.center,
                cellStyle: const pw.TextStyle(fontSize: 8),
              ),
              pw.SizedBox(height: 14),
            ],

            // Stock & Settlement Summary Cards
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Left Card: Stock Overview
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey50,
                      border: pw.Border.all(color: PdfColors.grey400),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('STOCK QUANTITY SUMMARY', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                        pw.Divider(color: PdfColors.grey300, thickness: 0.5),
                        _pdfKeyVal('Total Voucher Inward:', '${summary.totalVouchers} Nos (Rs. ${summary.totalVoucherAmount.toStringAsFixed(2)})'),
                        _pdfKeyVal('Total Unsold Returned:', '${summary.totalUnsold} Nos (Rs. ${summary.totalUnsoldAmount.toStringAsFixed(2)})'),
                        _pdfKeyVal('Net Sold Tickets:', '${summary.totalNetSold} Nos'),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 12),

                // Right Card: Final Calculation
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.amber50,
                      border: pw.Border.all(color: PdfColors.amber700),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('FINAL SETTLEMENT (RS)', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.brown800)),
                        pw.Divider(color: PdfColors.amber300, thickness: 0.5),
                        _pdfKeyVal('Total Voucher Inward:', 'Rs. ${summary.totalVoucherAmount.toStringAsFixed(2)}'),
                        _pdfKeyVal('Less Unsold Returns:', '- Rs. ${summary.totalUnsoldAmount.toStringAsFixed(2)}'),
                        _pdfKeyVal('Net Sold Amount (Bikri):', 'Rs. ${summary.totalNetAmount.toStringAsFixed(2)}', isBold: true),
                        if (summary.customerWins.isNotEmpty) ...[
                          pw.SizedBox(height: 3),
                          _pdfKeyVal('• Base Winning Inam:', '- Rs. ${totalBaseInam.toStringAsFixed(2)}'),
                          _pdfKeyVal('• Super Bonus:', '- Rs. ${totalBonus.toStringAsFixed(2)}'),
                          _pdfKeyVal('• Special Incentive:', '- Rs. ${totalIncentive.toStringAsFixed(2)}'),
                          _pdfKeyVal('Total Inam Claims:', '- Rs. ${summary.totalCustomerWinAmount.toStringAsFixed(2)}', isBold: true),
                        ],
                        pw.Divider(color: PdfColors.amber300, thickness: 0.5),
                        _pdfKeyVal('FINAL NET PAYABLE:', 'Rs. ${summary.finalNetPayable.toStringAsFixed(2)}', isBold: true),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 14),

            // Winning claims section with Bonus & Incentive if any
            if (summary.customerWins.isNotEmpty) ...[
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                color: PdfColors.amber50,
                child: pw.Text(
                  'WINNING INAM, BONUS & INCENTIVE BREAKDOWN (CUSTOMER CLAIMS)',
                  style: pw.TextStyle(
                    fontSize: 10.5,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.amber900,
                  ),
                ),
              ),
              pw.SizedBox(height: 4),
              pw.TableHelper.fromTextArray(
                headers: ['Prize Tier', 'Ticket No', 'Series', 'Base Inam (Rs)', 'Super Bonus (Rs)', 'Incentive (Rs)', 'Total Inam (Rs)'],
                data: summary.customerWins.map((w) {
                  final base = w.baseAmount * w.seriesCount;
                  final bonus = w.superBonus * w.seriesCount;
                  final inc = w.specialIncentive * w.seriesCount;
                  return [
                    _cleanPdfText(w.prizeTier),
                    w.ticketNumber,
                    '${w.ticketSeries} (${w.seriesCount} Sem)',
                    'Rs. ${base.toStringAsFixed(0)}',
                    'Rs. ${bonus.toStringAsFixed(0)}',
                    'Rs. ${inc.toStringAsFixed(0)}',
                    'Rs. ${w.prizeAmount.toStringAsFixed(0)}',
                  ];
                }).toList(),
                headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.amber800),
                cellAlignment: pw.Alignment.center,
                cellStyle: const pw.TextStyle(fontSize: 8.5),
              ),
            ],
          ];
        },
      ),
    );

    return _savePdfDocument(pdf, 'hisab_summary_${summary.partyName}_${summary.date}.pdf');
  }

  /// Export Full Detailed PDF document
  Future<String?> exportFullDetailedPdf(PartyHisabSummary summary) async {
    final pdf = pw.Document();
    final partyClean = _cleanPdfText(summary.partyName);
    final nowStr = DateFormat('dd-MMM-yyyy, hh:mm a').format(DateTime.now());

    double totalBaseInam = 0.0;
    double totalBonus = 0.0;
    double totalIncentive = 0.0;
    for (final w in summary.customerWins) {
      totalBaseInam += (w.baseAmount * w.seriesCount);
      totalBonus += (w.superBonus * w.seriesCount);
      totalIncentive += (w.specialIncentive * w.seriesCount);
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context ctx) {
          return [
            // Header
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: const pw.BoxDecoration(
                color: PdfColors.indigo900,
                borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('FULL DETAILED HISAB PARCHA', style: pw.TextStyle(color: PdfColors.white, fontSize: 16, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 2),
                      pw.Text('Party: $partyClean', style: pw.TextStyle(color: PdfColors.amber200, fontSize: 12, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Date: ${summary.date} | Shift: ${summary.shift}', style: const pw.TextStyle(color: PdfColors.white, fontSize: 10)),
                      pw.Text('Generated: $nowStr', style: const pw.TextStyle(color: PdfColors.grey300, fontSize: 9)),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 12),

            // Section 1: Vouchers
            pw.Text('1. STOCK VOUCHERS INWARD (${summary.rawVouchers.length} Ranges - ${summary.totalVouchers} Tickets)', style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
            pw.SizedBox(height: 4),
            if (summary.rawVouchers.isEmpty)
              pw.Text('No vouchers recorded', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600))
            else
              pw.TableHelper.fromTextArray(
                headers: ['#', 'Series', 'From Ticket', 'To Ticket', 'Qty', 'Rate (Rs)', 'Total Amount (Rs)'],
                data: summary.rawVouchers.asMap().entries.map((e) => [
                  '${e.key + 1}',
                  'Ser ${e.value.series}',
                  e.value.fromTicket,
                  e.value.toTicket,
                  '${e.value.totalQty}',
                  e.value.pricePerTicket.toStringAsFixed(2),
                  e.value.totalAmount.toStringAsFixed(2),
                ]).toList(),
                headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.blue700),
                cellAlignment: pw.Alignment.center,
                cellStyle: const pw.TextStyle(fontSize: 8.5),
              ),
            pw.SizedBox(height: 12),

            // Section 2: Unsold
            pw.Text('2. UNSOLD RETURNS (${summary.rawUnsold.length} Ranges - ${summary.totalUnsold} Tickets)', style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: PdfColors.red800)),
            pw.SizedBox(height: 4),
            if (summary.rawUnsold.isEmpty)
              pw.Text('No unsold returns recorded', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600))
            else
              pw.TableHelper.fromTextArray(
                headers: ['#', 'Series', 'From Ticket', 'To Ticket', 'Qty', 'Rate (Rs)', 'Total Amount (Rs)'],
                data: summary.rawUnsold.asMap().entries.map((e) => [
                  '${e.key + 1}',
                  'Ser ${e.value.series}',
                  e.value.fromTicket,
                  e.value.toTicket,
                  '${e.value.totalQty}',
                  e.value.pricePerTicket.toStringAsFixed(2),
                  e.value.totalAmount.toStringAsFixed(2),
                ]).toList(),
                headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.red700),
                cellAlignment: pw.Alignment.center,
                cellStyle: const pw.TextStyle(fontSize: 8.5),
              ),
            pw.SizedBox(height: 12),

            // Section 3: Winning Claims if any
            if (summary.customerWins.isNotEmpty) ...[
              pw.Text('3. WINNING INAM, BONUS & INCENTIVE CLAIMS (${summary.customerWins.length} Claims - Rs. ${summary.totalCustomerWinAmount.toStringAsFixed(2)})',
                  style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: PdfColors.amber900)),
              pw.SizedBox(height: 4),
              pw.TableHelper.fromTextArray(
                headers: ['#', 'Prize Tier', 'Ticket No', 'Series', 'Base Inam (Rs)', 'Super Bonus (Rs)', 'Incentive (Rs)', 'Total Inam (Rs)'],
                data: summary.customerWins.asMap().entries.map((e) {
                  final w = e.value;
                  final base = w.baseAmount * w.seriesCount;
                  final bonus = w.superBonus * w.seriesCount;
                  final inc = w.specialIncentive * w.seriesCount;
                  return [
                    '${e.key + 1}',
                    _cleanPdfText(w.prizeTier),
                    w.ticketNumber,
                    '${w.ticketSeries} (${w.seriesCount} Sem)',
                    'Rs. ${base.toStringAsFixed(0)}',
                    'Rs. ${bonus.toStringAsFixed(0)}',
                    'Rs. ${inc.toStringAsFixed(0)}',
                    'Rs. ${w.prizeAmount.toStringAsFixed(0)}',
                  ];
                }).toList(),
                headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 8.5),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.amber800),
                cellAlignment: pw.Alignment.center,
                cellStyle: const pw.TextStyle(fontSize: 8),
              ),
              pw.SizedBox(height: 12),
            ],

            // Section 3.5: Date & Shift Breakdown Table
            if (summary.dateBreakdowns.isNotEmpty && (summary.dateBreakdowns.length > 1 || summary.shift == 'ALL')) ...[
              pw.Text(
                summary.dateBreakdowns.length > 1
                    ? '3.5. DATE & SHIFT-WISE TIMINGS BREAKDOWN'
                    : '3.5. DRAW TIMINGS BREAKDOWN (1 PM • 6 PM • 8 PM)',
                style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900),
              ),
              pw.SizedBox(height: 4),
              pw.TableHelper.fromTextArray(
                columnWidths: const {
                  0: pw.FlexColumnWidth(2.2),
                  1: pw.FlexColumnWidth(1.6),
                  2: pw.FlexColumnWidth(1.4),
                  3: pw.FlexColumnWidth(1.4),
                  4: pw.FlexColumnWidth(1.4),
                  5: pw.FlexColumnWidth(2.0),
                  6: pw.FlexColumnWidth(1.5),
                  7: pw.FlexColumnWidth(1.8),
                },
                headers: ['Date', 'Draw Shift / Timing', 'Voucher In', 'Unsold Ret', 'Net Sold', 'Net Amount (Rs)', 'Inam (Rs)', 'Status'],
                data: [
                  for (final db in summary.dateBreakdowns)
                    for (final sb in db.shifts)
                      [
                        db.formattedDate,
                        sb.shift,
                        sb.hasEntry ? '${sb.totalVouchers} Nos' : '-',
                        sb.hasEntry ? '${sb.totalUnsold} Nos' : '-',
                        sb.hasEntry ? '${sb.totalNetSold} Nos' : '-',
                        sb.hasEntry ? 'Rs. ${sb.totalNetAmount.toStringAsFixed(2)}' : '-',
                        sb.customerWins.isNotEmpty ? 'Rs. ${sb.totalCustomerWinAmount.toStringAsFixed(0)}' : '-',
                        sb.hasEntry ? 'Active' : 'Empty / No Entry',
                      ],
                ],
                headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 8.5),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo800),
                rowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
                cellAlignment: pw.Alignment.center,
                cellStyle: const pw.TextStyle(fontSize: 8),
              ),
              pw.SizedBox(height: 12),
            ],

            // Section 4: Final Settlement Summary Cards
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey50,
                      border: pw.Border.all(color: PdfColors.grey400),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('STOCK QUANTITY SUMMARY', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                        pw.Divider(color: PdfColors.grey300, thickness: 0.5),
                        _pdfKeyVal('Total Voucher Inward:', '${summary.totalVouchers} Nos (Rs. ${summary.totalVoucherAmount.toStringAsFixed(2)})'),
                        _pdfKeyVal('Total Unsold Returned:', '${summary.totalUnsold} Nos (Rs. ${summary.totalUnsoldAmount.toStringAsFixed(2)})'),
                        _pdfKeyVal('Net Sold Tickets:', '${summary.totalNetSold} Nos'),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.amber50,
                      border: pw.Border.all(color: PdfColors.amber700),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('FINAL SETTLEMENT (RS)', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.brown800)),
                        pw.Divider(color: PdfColors.amber300, thickness: 0.5),
                        _pdfKeyVal('Total Voucher Inward:', 'Rs. ${summary.totalVoucherAmount.toStringAsFixed(2)}'),
                        _pdfKeyVal('Less Unsold Returns:', '- Rs. ${summary.totalUnsoldAmount.toStringAsFixed(2)}'),
                        _pdfKeyVal('Net Sold Amount (Bikri):', 'Rs. ${summary.totalNetAmount.toStringAsFixed(2)}', isBold: true),
                        if (summary.customerWins.isNotEmpty) ...[
                          pw.SizedBox(height: 3),
                          _pdfKeyVal('• Base Winning Inam:', '- Rs. ${totalBaseInam.toStringAsFixed(2)}'),
                          _pdfKeyVal('• Super Bonus:', '- Rs. ${totalBonus.toStringAsFixed(2)}'),
                          _pdfKeyVal('• Special Incentive:', '- Rs. ${totalIncentive.toStringAsFixed(2)}'),
                          _pdfKeyVal('Total Inam Claims:', '- Rs. ${summary.totalCustomerWinAmount.toStringAsFixed(2)}', isBold: true),
                        ],
                        pw.Divider(color: PdfColors.amber300, thickness: 0.5),
                        _pdfKeyVal('FINAL NET PAYABLE:', 'Rs. ${summary.finalNetPayable.toStringAsFixed(2)}', isBold: true),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ];
        },
      ),
    );

    return _savePdfDocument(pdf, 'hisab_detailed_${summary.partyName}_${summary.date}.pdf');
  }

  pw.Widget _pdfKeyVal(String key, String val, {bool isBold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(key, style: pw.TextStyle(fontSize: 9, color: PdfColors.grey800, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          pw.Text(val, style: pw.TextStyle(fontSize: isBold ? 10.5 : 9, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal, color: isBold ? PdfColors.green900 : PdfColors.black)),
        ],
      ),
    );
  }

  Future<String?> _savePdfDocument(pw.Document pdf, String defaultName) async {
    try {
      final bytes = await pdf.save();
      String? filePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Hisab PDF',
        fileName: defaultName,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (filePath == null) {
        final docsDir = Platform.environment['USERPROFILE'] != null
            ? '${Platform.environment['USERPROFILE']}\\Documents'
            : Directory.systemTemp.path;
        filePath = '$docsDir\\$defaultName';
      }

      final file = File(filePath);
      await file.writeAsBytes(bytes);
      return filePath;
    } catch (e) {
      return null;
    }
  }
}
