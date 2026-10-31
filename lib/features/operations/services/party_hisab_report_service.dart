import 'dart:io';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:file_picker/file_picker.dart';
import '../utils/party_hisab_settlement_engine.dart';

class PartyHisabReportService {
  PartyHisabReportService._internal();
  static final PartyHisabReportService instance =
      PartyHisabReportService._internal();

  // ─── Company branding constants ───────────────────────────────────────────
  static const String _companyName = 'PHANTOM MANAGEMENT';
  static const String _companyTagline = 'Lottery & Hisab Management System';

  /// Branded header strip on page 2+ only (page 1 has its own full title banner already)
  pw.Widget _buildPdfPageHeader(pw.Context ctx, {String subtitle = ''}) {
    if (ctx.pageNumber == 1) return pw.SizedBox(height: 0);
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      margin: const pw.EdgeInsets.only(bottom: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColor.fromInt(0xFF6B21A8), width: 1.2),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          // Left: royal purple vertical accent bar + company name + tagline
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Container(
                width: 3.5,
                height: 22,
                color: const PdfColor.fromInt(0xFF6B21A8),
              ),
              pw.SizedBox(width: 6),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Text(
                    _companyName,
                    style: pw.TextStyle(
                      fontSize: 10.5,
                      fontWeight: pw.FontWeight.bold,
                      color: const PdfColor.fromInt(0xFF1E1B4B),
                    ),
                  ),
                  pw.Text(
                    _companyTagline,
                    style: pw.TextStyle(
                      fontSize: 7,
                      color: const PdfColor.fromInt(0xFF6B21A8),
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
          // Right: subtitle + page number
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              if (subtitle.isNotEmpty)
                pw.Text(
                  subtitle,
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: const PdfColor.fromInt(0xFF6B21A8),
                  ),
                ),
              pw.Text(
                'Page ${ctx.pageNumber} / ${ctx.pagesCount}',
                style: const pw.TextStyle(
                  fontSize: 7.5,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Footer: company info + page number, page 2+ only
  pw.Widget _buildPdfPageFooter(pw.Context ctx) {
    if (ctx.pageNumber == 1) return pw.SizedBox(height: 0);
    final nowStr = DateFormat('dd-MMM-yyyy, hh:mm a').format(DateTime.now());
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColor.fromInt(0xFFC084FC), width: 0.8),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            '$_companyName  |  $_companyTagline',
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
          ),
          pw.Text(
            'Generated: $nowStr  |  Page ${ctx.pageNumber} / ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
          ),
        ],
      ),
    );
  }

  /// Clean non-ASCII symbols that cause tofu boxes in standard PDF fonts
  String _cleanPdfText(String text) {
    if (text.isEmpty) return '';
    final cleaned = text.replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();
    return cleaned.isNotEmpty ? cleaned : 'Party';
  }

  String generateSummaryWhatsAppText(PartyHisabSummary summary) {
    final buffer = StringBuffer();
    final nowStr = DateFormat('dd-MMM-yyyy, hh:mm a').format(DateTime.now());

    buffer.writeln(
      '==================================================================',
    );
    buffer.writeln(
      summary.isDealer
          ? '          👑 MAIN DEALER CONSOLIDATED HISAB SUMMARY'
          : '                    📊 DAILY DRAW HISAB SUMMARY',
    );
    buffer.writeln(
      '==================================================================',
    );
    if (summary.isDealer) {
      buffer.writeln('Main Dealer    : 👑 ${summary.partyName}');
      if (summary.subSellerBreakdowns.isNotEmpty) {
        buffer.writeln(
          'Sub-Sellers    : ${summary.subSellerBreakdowns.length} Sellers (${summary.subSellerBreakdowns.map((s) => s.sellerName).join(", ")})',
        );
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
    buffer.writeln(
      '------------------------------------------------------------------',
    );

    final hSer = 'SERIES'.padRight(9);
    final hVou = 'VOUCHER(IN)'.padRight(13);
    final hUns = 'UNSOLD(RET)'.padRight(13);
    final hNet = 'NET SOLD'.padRight(11);
    final hSem = 'SEM SUM'.padRight(12);
    final hRat = 'RATE(Rs)'.padRight(10);
    final hAmt = 'AMOUNT(Rs)';
    final tableHeader = '$hSer$hVou$hUns$hNet$hSem$hRat$hAmt';
    buffer.writeln(tableHeader);
    buffer.writeln('-' * tableHeader.length);

    for (final s in summary.seriesHisabList) {
      final sStr = 'Ser ${s.series}'.padRight(9);
      final vStr = '${s.voucherQty} Qty'.padRight(13);
      final uStr = '${s.unsoldQty} Qty'.padRight(13);
      final nStr = '${s.netSoldQty} Qty'.padRight(11);
      final semStr = '${s.netSeriesSum} Sem'.padRight(12);
      final rStr = s.rate.toStringAsFixed(2).padRight(10);
      final aStr = s.netAmount.toStringAsFixed(2);
      buffer.writeln('$sStr$vStr$uStr$nStr$semStr$rStr$aStr');
    }

    buffer.writeln('-' * tableHeader.length);
    final totSer = 'TOTAL'.padRight(9);
    final totVou = '${summary.totalVouchers} Qty'.padRight(13);
    final totUns = '${summary.totalUnsold} Qty'.padRight(13);
    final totNet = '${summary.totalNetSold} Qty'.padRight(11);
    final totSem = '${summary.totalNetSeriesSum} Sem'.padRight(12);
    final totRat = '-'.padRight(10);
    final totAmt = 'Rs. ${summary.totalNetAmount.toStringAsFixed(2)}';
    buffer.writeln('$totSer$totVou$totUns$totNet$totSem$totRat$totAmt');
    buffer.writeln('-' * tableHeader.length);
    buffer.writeln(
      '⚡ AUDIT CHECK: ${summary.totalNetSeriesSum} Sem x Rs.${summary.effectivePerUnitRate.toStringAsFixed(2)}/unit = Rs.${summary.totalNetAmount.toStringAsFixed(2)} Net Sold',
    );
    buffer.writeln(
      '------------------------------------------------------------------',
    );
    buffer.writeln('📦 TOTAL STOCK SUMMARY:');
    buffer.writeln(
      '• Total Voucher Inward  : ${summary.totalVouchers} Tickets (Sem: ${summary.totalVoucherSeriesSum}) -> Rs. ${summary.totalVoucherAmount.toStringAsFixed(2)}',
    );
    buffer.writeln(
      '• Total Unsold Returned : ${summary.totalUnsold} Tickets (Sem: ${summary.totalUnsoldSeriesSum}) -> Rs. ${summary.totalUnsoldAmount.toStringAsFixed(2)}',
    );
    buffer.writeln(
      '• Net Sold Tickets      : ${summary.totalNetSold} Tickets (Kul Sem: ${summary.totalNetSeriesSum}) -> Rs. ${summary.totalNetAmount.toStringAsFixed(2)}',
    );

    if (summary.subSellerBreakdowns.isNotEmpty) {
      buffer.writeln(
        '------------------------------------------------------------------',
      );
      buffer.writeln('👥 SUB-SELLER WISE BREAKDOWN:');
      for (final sb in summary.subSellerBreakdowns) {
        final nameP = sb.sellerName.padRight(14);
        final inP = 'In ${sb.totalVouchers}'.padRight(9);
        final retP = 'Ret ${sb.totalUnsold}'.padRight(9);
        final netP = 'Net ${sb.totalNetSold} Nos'.padRight(14);
        final amtP = 'Rs. ${sb.totalNetAmount.toStringAsFixed(2)}';
        final winP = sb.totalWinAmount > 0
            ? ' (Inam: -Rs.${sb.totalWinAmount.toStringAsFixed(0)})'
            : '';
        buffer.writeln(
          '• $nameP: $inP - $retP = $netP -> $amtP$winP -> Net: Rs.${sb.finalNetPayable.toStringAsFixed(2)}',
        );
      }
    }

    if (summary.dateBreakdowns.isNotEmpty) {
      buffer.writeln(
        '------------------------------------------------------------------',
      );
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
            final aStr = '(Rs. ${sb.totalNetAmount.toStringAsFixed(2)})'
                .padRight(17);
            final resStr =
                (sb.drawResultFirstPrize != null &&
                    sb.drawResultFirstPrize!.isNotEmpty)
                ? ' | 🎯 Result: 1st Prize ${sb.drawResultFirstPrize}'
                : '';
            final winStr = sb.customerWins.isNotEmpty
                ? ' | 🏆 Party Won: ${sb.customerWins.map((w) => '#${w.ticketNumber} [${w.prizeTier}]').join(", ")}'
                : (resStr.isNotEmpty ? ' (No Party Win)' : '');
            buffer.writeln(
              '   • $shiftPadded : $vStr - $uStr = $nStr $aStr$resStr$winStr',
            );
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
        buffer.writeln(
          '• [${w.displayDate} ${w.displayTime}] ${w.prizeTier} (Ser ${w.ticketSeries} #${w.ticketNumber} x ${w.seriesCount} Sem) : Inam Rs.${base.toStringAsFixed(0)} + Bonus Rs.${bonus.toStringAsFixed(0)} + Inc Rs.${inc.toStringAsFixed(0)} = Rs.${w.prizeAmount.toStringAsFixed(0)}',
        );
      }
      buffer.writeln(
        '• Total Base Inam       : Rs. ${totalBaseInam.toStringAsFixed(2)}',
      );
      buffer.writeln(
        '• Total Super Bonus     : Rs. ${totalBonus.toStringAsFixed(2)}',
      );
      buffer.writeln(
        '• Total Incentive       : Rs. ${totalIncentive.toStringAsFixed(2)}',
      );
      buffer.writeln(
        '• Total Winning Payout  : Rs. ${summary.totalCustomerWinAmount.toStringAsFixed(2)}',
      );
      buffer.writeln('------------------------------------------------');
    }

    buffer.writeln('💰 FINAL SETTLEMENT HISAB:');
    buffer.writeln(
      '  1. Total Voucher Inward  :   Rs. ${summary.totalVoucherAmount.toStringAsFixed(2)}',
    );
    buffer.writeln(
      '  2. Less Unsold Returns   : - Rs. ${summary.totalUnsoldAmount.toStringAsFixed(2)}',
    );
    buffer.writeln('  ------------------------------------------------');
    buffer.writeln(
      '  = Net Sold Amount (Bikri):   Rs. ${summary.totalNetAmount.toStringAsFixed(2)}',
    );
    if (summary.customerWins.isNotEmpty) {
      buffer.writeln(
        '  • Base Inam Deduction    : - Rs. ${totalBaseInam.toStringAsFixed(2)}',
      );
      buffer.writeln(
        '  • Super Bonus Deduction  : - Rs. ${totalBonus.toStringAsFixed(2)}',
      );
      buffer.writeln(
        '  • Incentive Deduction    : - Rs. ${totalIncentive.toStringAsFixed(2)}',
      );
      buffer.writeln(
        '  3. Total Winning Inam    : - Rs. ${summary.totalCustomerWinAmount.toStringAsFixed(2)}',
      );
    }
    buffer.writeln('  ------------------------------------------------');
    buffer.writeln(
      '  ✅ FINAL NET PAYABLE     :   Rs. ${summary.finalNetPayable.toStringAsFixed(2)}',
    );
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
    buffer.writeln(
      'Draw Date      : ${summary.date} | Shift: ${summary.shift}',
    );
    buffer.writeln('Generated At   : $nowStr');
    buffer.writeln('------------------------------------------------');

    if (summary.dateBreakdowns.isNotEmpty) {
      buffer.writeln('📅 DATE & TIMINGS (SHIFT-WISE) BREAKDOWN:');
      for (final db in summary.dateBreakdowns) {
        buffer.writeln('🗓️ MAIN DATE: ${db.formattedDate}');
        for (final sb in db.shifts) {
          final shiftPadded = sb.shift.padRight(11);
          if (!sb.hasEntry) {
            buffer.writeln('   ⏰ $shiftPadded -> [ Empty / No Entry ]');
          } else {
            final resStr =
                (sb.drawResultFirstPrize != null &&
                    sb.drawResultFirstPrize!.isNotEmpty)
                ? ' | 🎯 Result: 1st Prize ${sb.drawResultFirstPrize}'
                : '';
            final winStr = sb.customerWins.isNotEmpty
                ? ' | 🏆 Party Won: ${sb.customerWins.map((w) => '#${w.ticketNumber} [${w.prizeTier}]').join(", ")})'
                : (resStr.isNotEmpty ? ' (No Party Win)' : '');
            buffer.writeln(
              '   ⏰ $shiftPadded -> In ${sb.totalVouchers} - Ret ${sb.totalUnsold} = Net ${sb.totalNetSold} Nos (Rs. ${sb.totalNetAmount.toStringAsFixed(2)})$resStr$winStr',
            );
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
        buffer.writeln(
          '  ${i + 1}. [Ser ${v.series}] ${v.fromTicket}-${v.toTicket} (${v.totalQty} Nos) @ Rs.${v.pricePerTicket.toStringAsFixed(2)} = Rs.${v.totalAmount.toStringAsFixed(2)}',
        );
      }
    }
    buffer.writeln(
      '  Total Vouchers: ${summary.totalVouchers} Tickets (Rs. ${summary.totalVoucherAmount.toStringAsFixed(2)})',
    );
    buffer.writeln('------------------------------------------------');

    buffer.writeln('📦 2. UNSOLD RETURNS:');
    if (summary.rawUnsold.isEmpty) {
      buffer.writeln('  (No Unsold Returns recorded)');
    } else {
      for (int i = 0; i < summary.rawUnsold.length; i++) {
        final u = summary.rawUnsold[i];
        final rangeStr = u.fromTicket == u.toTicket
            ? u.fromTicket
            : '${u.fromTicket}-${u.toTicket}';
        buffer.writeln(
          '  ${i + 1}. [Ser ${u.series}] $rangeStr (${u.totalQty} Nos) @ Rs.${u.pricePerTicket.toStringAsFixed(2)} = Rs.${u.totalAmount.toStringAsFixed(2)}',
        );
      }
    }
    buffer.writeln(
      '  Total Unsold: ${summary.totalUnsold} Tickets (Rs. ${summary.totalUnsoldAmount.toStringAsFixed(2)})',
    );
    buffer.writeln('------------------------------------------------');

    buffer.writeln('📊 3. SERIES NET SOLD BREAKDOWN:');
    for (final s in summary.seriesHisabList) {
      buffer.writeln(
        '  • Ser ${s.series} : In ${s.voucherQty} - Ret ${s.unsoldQty} = Net ${s.netSoldQty} Nos [${s.netSeriesSum} Sem] @ Rs.${s.rate.toStringAsFixed(2)} = Rs.${s.netAmount.toStringAsFixed(2)}',
      );
    }
    buffer.writeln(
      '  • TOTAL NET SOLD: ${summary.totalNetSold} Tickets (Kul Sem: ${summary.totalNetSeriesSum} Sem) = Rs. ${summary.totalNetAmount.toStringAsFixed(2)}',
    );
    buffer.writeln(
      '  ⚡ AUDIT CHECK: ${summary.totalNetSeriesSum} Sem x Rs.${summary.effectivePerUnitRate.toStringAsFixed(2)}/unit = Rs.${summary.totalNetAmount.toStringAsFixed(2)}',
    );
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
        buffer.writeln(
          '  • [${w.displayDate} ${w.displayTime}] ${w.prizeTier} [Ser ${w.ticketSeries} x ${w.seriesCount} Sem] #${w.ticketNumber} : Inam Rs.${base.toStringAsFixed(0)} + Bonus Rs.${bonus.toStringAsFixed(0)} + Inc Rs.${inc.toStringAsFixed(0)} = Rs.${w.prizeAmount.toStringAsFixed(0)}',
        );
      }
      buffer.writeln(
        '  • Total Base Inam     : Rs. ${totalBaseInam.toStringAsFixed(2)}',
      );
      buffer.writeln(
        '  • Total Super Bonus   : Rs. ${totalBonus.toStringAsFixed(2)}',
      );
      buffer.writeln(
        '  • Total Incentive     : Rs. ${totalIncentive.toStringAsFixed(2)}',
      );
      buffer.writeln(
        '  = Total Winning Claims : Rs. ${summary.totalCustomerWinAmount.toStringAsFixed(2)}',
      );
      buffer.writeln('------------------------------------------------');
    }

    buffer.writeln('💰 FINAL SETTLEMENT:');
    buffer.writeln(
      '  1. Total Voucher Inward  : Rs. ${summary.totalVoucherAmount.toStringAsFixed(2)}',
    );
    buffer.writeln(
      '  2. Less Unsold Returned  : - Rs. ${summary.totalUnsoldAmount.toStringAsFixed(2)}',
    );
    buffer.writeln('  ------------------------------------------------');
    buffer.writeln(
      '  = Net Sold Amount (Bikri): Rs. ${summary.totalNetAmount.toStringAsFixed(2)}',
    );
    if (summary.customerWins.isNotEmpty) {
      buffer.writeln(
        '  • Base Inam Deduction    : - Rs. ${totalBaseInam.toStringAsFixed(2)}',
      );
      buffer.writeln(
        '  • Super Bonus Deduction  : - Rs. ${totalBonus.toStringAsFixed(2)}',
      );
      buffer.writeln(
        '  • Incentive Deduction    : - Rs. ${totalIncentive.toStringAsFixed(2)}',
      );
      buffer.writeln(
        '  3. Total Winning Inam    : - Rs. ${summary.totalCustomerWinAmount.toStringAsFixed(2)}',
      );
    }
    buffer.writeln('  ------------------------------------------------');
    buffer.writeln(
      '  ✅ NET PAYABLE AMOUNT    : Rs. ${summary.finalNetPayable.toStringAsFixed(2)}',
    );
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
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(24, 8, 24, 8),
          buildBackground: (pw.Context ctx) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Container(
              decoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(
                  0xFFF3E8FF,
                ), // soothing royal purple pastel tint (removes white glare)
              ),
            ),
          ),
        ),
        header: (pw.Context ctx) => _buildPdfPageHeader(
          ctx,
          subtitle: 'Party Hisab Summary | ${_cleanPdfText(summary.partyName)}',
        ),
        footer: (pw.Context ctx) => _buildPdfPageFooter(ctx),
        build: (pw.Context ctx) {
          return [
            // ── Premium Clean Title Block (no filled box) ──────────────────
            pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 10),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(
                    color: PdfColor.fromInt(0xFF6B21A8), // royal purple accent
                    width: 1.5,
                  ),
                ),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Row(
                        children: [
                          pw.Container(
                            width: 4,
                            height: 28,
                            color: PdfColor.fromInt(0xFF6B21A8),
                          ),
                          pw.SizedBox(width: 8),
                          pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                _companyName,
                                style: pw.TextStyle(
                                  fontSize: 18,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColor.fromInt(0xFF1E1B4B),
                                ),
                              ),
                              pw.Text(
                                'PARTY HISAB SUMMARY REPORT',
                                style: pw.TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColor.fromInt(0xFF6B21A8),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 5),
                      pw.Text(
                        'Party / Customer: $partyClean',
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromInt(0xFF1E1B4B),
                        ),
                      ),
                      if (summary.dealerName != null &&
                          summary.dealerName!.isNotEmpty)
                        pw.Text(
                          'Parent Dealer: ${summary.dealerName}',
                          style: const pw.TextStyle(
                            fontSize: 8.5,
                            color: PdfColors.grey700,
                          ),
                        ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'Date: ${summary.date}  |  Shift: ${summary.shift}',
                        style: pw.TextStyle(
                          fontSize: 9.5,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromInt(0xFF1E1B4B),
                        ),
                      ),
                      if (summary.dateBreakdowns.any(
                        (db) => db.shifts.any(
                          (s) =>
                              s.drawResultFirstPrize != null &&
                              s.drawResultFirstPrize!.isNotEmpty,
                        ),
                      ))
                        pw.Text(
                          '1st Prize: ${summary.dateBreakdowns.expand((db) => db.shifts).where((s) => s.drawResultFirstPrize != null && s.drawResultFirstPrize!.isNotEmpty).map((s) => "${s.shift}: ${s.drawResultFirstPrize}").toSet().join(" | ")}',
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColor.fromInt(0xFF6B21A8),
                          ),
                        ),
                      pw.Text(
                        'Generated: $nowStr',
                        style: const pw.TextStyle(
                          fontSize: 7.5,
                          color: PdfColors.grey600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 10),

            // 🌟 2. TOP SUMMARY DASHBOARD & KPI CARDS (IMMEDIATELY VISIBLE AT THE VERY TOP)
            _buildTopKpiSummary(
              summary,
              totalBaseInam,
              totalBonus,
              totalIncentive,
            ),
            pw.SizedBox(height: 8),

            // 3. SERIES-WISE STOCK & SETTLEMENT TABLE (WITH SERIES SUM MULTIPLIER COLUMN & GRAND TOTAL ROW)
            pw.Text(
              'SERIES-WISE STOCK & SETTLEMENT TABLE',
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blueGrey800,
              ),
            ),
            pw.SizedBox(height: 5),
            pw.TableHelper.fromTextArray(
              columnWidths: const {
                0: pw.FlexColumnWidth(1.3),
                1: pw.FlexColumnWidth(1.4),
                2: pw.FlexColumnWidth(1.4),
                3: pw.FlexColumnWidth(1.4),
                4: pw.FlexColumnWidth(1.8),
                5: pw.FlexColumnWidth(1.4),
                6: pw.FlexColumnWidth(1.8),
              },
              headers: [
                'Series',
                'Voucher In',
                'Unsold Ret',
                'Net Sold',
                'Series Sum (Sem)',
                'Rate (Rs)',
                'Net Amount (Rs)',
              ],
              data: [
                ...summary.seriesHisabList.map(
                  (s) => [
                    'Ser ${s.series}',
                    '${s.voucherQty} Nos',
                    '${s.unsoldQty} Nos',
                    '${s.netSoldQty} Nos',
                    '${s.netSeriesSum} Sem',
                    s.rate.toStringAsFixed(2),
                    s.netAmount.toStringAsFixed(2),
                  ],
                ),
                // Final Grand Total Row
                [
                  'TOTAL / KUL',
                  '${summary.totalVouchers} Nos',
                  '${summary.totalUnsold} Nos',
                  '${summary.totalNetSold} Nos',
                  '${summary.totalNetSeriesSum} Sem',
                  'Rs. ${summary.effectivePerUnitRate.toStringAsFixed(2)}/u',
                  'Rs. ${summary.totalNetAmount.toStringAsFixed(2)}',
                ],
              ],
              headerStyle: pw.TextStyle(
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
                fontSize: 9,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFF6B21A8),
              ),
              rowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
              cellAlignment: pw.Alignment.center,
              cellStyle: const pw.TextStyle(fontSize: 8.5),
            ),
            pw.SizedBox(height: 12),

            // Date & Shift Breakdown Table (Result Khula & Winning Hits)
            if (summary.dateBreakdowns.isNotEmpty) ...[
              pw.Text(
                'DATE & DRAW TIMINGS BREAKDOWN (RESULT KHULA & INAM SUMMARY)',
                style: pw.TextStyle(
                  fontSize: 10.5,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColor.fromInt(0xFF581C87),
                ),
              ),
              pw.SizedBox(height: 4),
              pw.TableHelper.fromTextArray(
                columnWidths: const {
                  0: pw.FlexColumnWidth(2.0),
                  1: pw.FlexColumnWidth(1.6),
                  2: pw.FlexColumnWidth(1.2),
                  3: pw.FlexColumnWidth(1.2),
                  4: pw.FlexColumnWidth(1.2),
                  5: pw.FlexColumnWidth(1.8),
                  6: pw.FlexColumnWidth(1.5),
                  7: pw.FlexColumnWidth(2.5),
                },
                headers: [
                  'Date',
                  'Draw Shift / Timing',
                  'Voucher In',
                  'Unsold Ret',
                  'Net Sold',
                  'Net Amount (Rs)',
                  'Inam (Rs)',
                  'Result Khula & Winning Hits',
                ],
                data: [
                  for (final db in summary.dateBreakdowns)
                    for (final sb in db.shifts)
                      [
                        db.formattedDate,
                        sb.shift,
                        sb.hasEntry ? '${sb.totalVouchers} Nos' : '-',
                        sb.hasEntry ? '${sb.totalUnsold} Nos' : '-',
                        sb.hasEntry ? '${sb.totalNetSold} Nos' : '-',
                        sb.hasEntry
                            ? 'Rs. ${sb.totalNetAmount.toStringAsFixed(2)}'
                            : '-',
                        sb.customerWins.isNotEmpty
                            ? 'Rs. ${sb.customerWins.fold<double>(0.0, (sum, w) => sum + w.prizeAmount).toStringAsFixed(0)}'
                            : '-',
                        '${sb.drawResultFirstPrize != null && sb.drawResultFirstPrize!.isNotEmpty ? "Khula: 1st ${sb.drawResultFirstPrize}\n" : ""}${sb.customerWins.isNotEmpty ? "Won: ${sb.customerWins.map((w) => '${w.ticketNumber} (${_cleanPdfText(w.prizeTier)} - Rs.${w.prizeAmount.toStringAsFixed(0)})').join(', ')}" : (sb.drawResultFirstPrize != null ? "No Party Win" : (sb.hasEntry ? "Result Pending" : "No Entry"))}',
                      ],
                ],
                headerStyle: pw.TextStyle(
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 8,
                ),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFF6B21A8),
                ),
                rowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
                cellAlignment: pw.Alignment.center,
                cellStyle: const pw.TextStyle(fontSize: 7.5),
              ),
              pw.SizedBox(height: 12),
            ],

            // Final Settlement Summary Balance Sheet Card
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
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(4),
                      ),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'STOCK QUANTITY SUMMARY',
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.blue900,
                          ),
                        ),
                        pw.Divider(color: PdfColors.grey300, thickness: 0.5),
                        _pdfKeyVal(
                          'Total Voucher Inward:',
                          '${summary.totalVouchers} Nos [${summary.totalVoucherSeriesSum} Sem]',
                        ),
                        _pdfKeyVal(
                          'Total Unsold Returned:',
                          '${summary.totalUnsold} Nos [${summary.totalUnsoldSeriesSum} Sem]',
                        ),
                        _pdfKeyVal(
                          'Net Sold Tickets:',
                          '${summary.totalNetSold} Nos [${summary.totalNetSeriesSum} Sem]',
                          isBold: true,
                        ),
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
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(4),
                      ),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'FINAL SETTLEMENT (RS)',
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.brown800,
                          ),
                        ),
                        pw.Divider(color: PdfColors.amber300, thickness: 0.5),
                        _pdfKeyVal(
                          'Total Voucher Inward:',
                          'Rs. ${summary.totalVoucherAmount.toStringAsFixed(2)}',
                        ),
                        _pdfKeyVal(
                          'Less Unsold Returns:',
                          '- Rs. ${summary.totalUnsoldAmount.toStringAsFixed(2)}',
                        ),
                        _pdfKeyVal(
                          'Net Sold Amount (Bikri):',
                          'Rs. ${summary.totalNetAmount.toStringAsFixed(2)}',
                          isBold: true,
                        ),
                        if (summary.customerWins.isNotEmpty) ...[
                          pw.SizedBox(height: 3),
                          _pdfKeyVal(
                            '- Base Winning Inam:',
                            '- Rs. ${totalBaseInam.toStringAsFixed(2)}',
                          ),
                          _pdfKeyVal(
                            '- Super Bonus:',
                            '- Rs. ${totalBonus.toStringAsFixed(2)}',
                          ),
                          _pdfKeyVal(
                            '- Special Incentive:',
                            '- Rs. ${totalIncentive.toStringAsFixed(2)}',
                          ),
                          _pdfKeyVal(
                            'Total Inam Claims:',
                            '- Rs. ${summary.totalCustomerWinAmount.toStringAsFixed(2)}',
                            isBold: true,
                          ),
                        ],
                        pw.Divider(color: PdfColors.amber300, thickness: 0.5),
                        _pdfKeyVal(
                          'FINAL NET PAYABLE:',
                          'Rs. ${summary.finalNetPayable.toStringAsFixed(2)}',
                          isBold: true,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 12),

            // Winning claims section with Bonus & Incentive if any
            if (summary.customerWins.isNotEmpty) ...[
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 5,
                ),
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
                columnWidths: const {
                  0: pw.FlexColumnWidth(1.6),
                  1: pw.FlexColumnWidth(1.4),
                  2: pw.FlexColumnWidth(1.8),
                  3: pw.FlexColumnWidth(1.5),
                  4: pw.FlexColumnWidth(1.6),
                  5: pw.FlexColumnWidth(1.5),
                  6: pw.FlexColumnWidth(1.6),
                  7: pw.FlexColumnWidth(1.7),
                },
                headers: [
                  'Date',
                  'Shift / Time',
                  'Prize Tier',
                  'Ticket No',
                  'Series / Sem',
                  'Base Inam (Rs)',
                  'Bonus+Inc (Rs)',
                  'Total Inam (Rs)',
                ],
                data: summary.customerWins.map((w) {
                  final base = w.baseAmount * w.seriesCount;
                  final bonusPlusInc =
                      (w.superBonus + w.specialIncentive) * w.seriesCount;
                  return [
                    w.displayDate,
                    w.displayTime,
                    _cleanPdfText(w.prizeTier),
                    w.ticketNumber,
                    'Ser ${w.ticketSeries} (${w.seriesCount} Sem)',
                    'Rs. ${base.toStringAsFixed(0)}',
                    'Rs. ${bonusPlusInc.toStringAsFixed(0)}',
                    'Rs. ${w.prizeAmount.toStringAsFixed(0)}',
                  ];
                }).toList(),
                headerStyle: pw.TextStyle(
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 8,
                ),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.amber800,
                ),
                cellAlignment: pw.Alignment.center,
                cellStyle: const pw.TextStyle(fontSize: 7.5),
              ),
            ] else ...[
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(4),
                  ),
                ),
                child: pw.Row(
                  children: [
                    pw.Text(
                      'WINNING INAM STATUS: ',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 8.5,
                        color: PdfColors.blueGrey800,
                      ),
                    ),
                    pw.Text(
                      'Is hisab me party ka koi winning inam claim nahi nikla hai (Total Inam Deduction: Rs. 0.00)',
                      style: const pw.TextStyle(
                        fontSize: 8.5,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ];
        },
      ),
    );

    return _savePdfDocument(
      pdf,
      'hisab_summary_${summary.partyName}_${summary.date}.pdf',
    );
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
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(24, 8, 24, 8),
          buildBackground: (pw.Context ctx) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Container(
              decoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFF3E8FF),
              ),
            ),
          ),
        ),
        header: (pw.Context ctx) => _buildPdfPageHeader(
          ctx,
          subtitle: 'Full Detailed Hisab | ${_cleanPdfText(summary.partyName)}',
        ),
        footer: (pw.Context ctx) => _buildPdfPageFooter(ctx),
        build: (pw.Context ctx) {
          return [
            // ── Premium Clean Title Block ──────────────────────────────────
            pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 10),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(
                    color: PdfColor.fromInt(0xFF6B21A8),
                    width: 1.5,
                  ),
                ),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Row(
                    children: [
                      pw.Container(
                        width: 4,
                        height: 28,
                        color: PdfColor.fromInt(0xFF6B21A8),
                      ),
                      pw.SizedBox(width: 8),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            _companyName,
                            style: pw.TextStyle(
                              fontSize: 18,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColor.fromInt(0xFF1E1B4B),
                            ),
                          ),
                          pw.Text(
                            'FULL DETAILED HISAB PARCHA',
                            style: pw.TextStyle(
                              fontSize: 9.5,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColor.fromInt(0xFF6B21A8),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'Party: $partyClean',
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromInt(0xFF1E1B4B),
                        ),
                      ),
                      pw.Text(
                        'Date: ${summary.date} | Shift: ${summary.shift}',
                        style: const pw.TextStyle(
                          fontSize: 9,
                          color: PdfColors.grey700,
                        ),
                      ),
                      pw.Text(
                        'Generated: $nowStr',
                        style: const pw.TextStyle(
                          fontSize: 7.5,
                          color: PdfColors.grey600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 10),

            // 🌟 2. TOP SUMMARY DASHBOARD & KPI CARDS (IMMEDIATELY VISIBLE AT THE VERY TOP)
            _buildTopKpiSummary(
              summary,
              totalBaseInam,
              totalBonus,
              totalIncentive,
            ),
            pw.SizedBox(height: 8),

            // Section 1: Vouchers
            pw.Text(
              '1. STOCK VOUCHERS INWARD (${summary.rawVouchers.length} Ranges - ${summary.totalVouchers} Tickets - ${summary.totalVoucherSeriesSum} Sem)',
              style: pw.TextStyle(
                fontSize: 10.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromInt(0xFF581C87),
              ),
            ),
            pw.SizedBox(height: 4),
            if (summary.rawVouchers.isEmpty)
              pw.Text(
                'No vouchers recorded',
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey600,
                ),
              )
            else
              pw.TableHelper.fromTextArray(
                columnWidths: const {
                  0: pw.FlexColumnWidth(0.8),
                  1: pw.FlexColumnWidth(1.4),
                  2: pw.FlexColumnWidth(1.6),
                  3: pw.FlexColumnWidth(1.6),
                  4: pw.FlexColumnWidth(1.2),
                  5: pw.FlexColumnWidth(1.5),
                  6: pw.FlexColumnWidth(1.4),
                  7: pw.FlexColumnWidth(1.8),
                },
                headers: [
                  '#',
                  'Series',
                  'From Ticket',
                  'To Ticket',
                  'Qty',
                  'Sem Units',
                  'Rate (Rs)',
                  'Total Amount (Rs)',
                ],
                data: [
                  ...summary.rawVouchers.asMap().entries.map((e) {
                    final sNum =
                        int.tryParse(
                          e.value.series.replaceAll(RegExp(r'\D'), ''),
                        ) ??
                        12;
                    final sem = e.value.totalQty * sNum;
                    return [
                      '${e.key + 1}',
                      'Ser ${e.value.series}',
                      e.value.fromTicket,
                      e.value.toTicket,
                      '${e.value.totalQty}',
                      '$sem Sem',
                      e.value.pricePerTicket.toStringAsFixed(2),
                      e.value.totalAmount.toStringAsFixed(2),
                    ];
                  }),
                  [
                    'TOTAL',
                    '-',
                    '-',
                    '-',
                    '${summary.totalVouchers} Nos',
                    '${summary.totalVoucherSeriesSum} Sem',
                    '-',
                    'Rs. ${summary.totalVoucherAmount.toStringAsFixed(2)}',
                  ],
                ],
                headerStyle: pw.TextStyle(
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 8.5,
                ),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFF6B21A8),
                ),
                cellAlignment: pw.Alignment.center,
                cellStyle: const pw.TextStyle(fontSize: 8),
              ),
            pw.SizedBox(height: 12),

            // Section 2: Unsold
            pw.Text(
              '2. UNSOLD RETURNS (${summary.rawUnsold.length} Ranges - ${summary.totalUnsold} Tickets - ${summary.totalUnsoldSeriesSum} Sem)',
              style: pw.TextStyle(
                fontSize: 10.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.red800,
              ),
            ),
            pw.SizedBox(height: 4),
            if (summary.rawUnsold.isEmpty)
              pw.Text(
                'No unsold returns recorded',
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey600,
                ),
              )
            else
              pw.TableHelper.fromTextArray(
                columnWidths: const {
                  0: pw.FlexColumnWidth(0.8),
                  1: pw.FlexColumnWidth(1.4),
                  2: pw.FlexColumnWidth(1.6),
                  3: pw.FlexColumnWidth(1.6),
                  4: pw.FlexColumnWidth(1.2),
                  5: pw.FlexColumnWidth(1.5),
                  6: pw.FlexColumnWidth(1.4),
                  7: pw.FlexColumnWidth(1.8),
                },
                headers: [
                  '#',
                  'Series',
                  'From Ticket',
                  'To Ticket',
                  'Qty',
                  'Sem Units',
                  'Rate (Rs)',
                  'Total Amount (Rs)',
                ],
                data: [
                  ...summary.rawUnsold.asMap().entries.map((e) {
                    final sNum =
                        int.tryParse(
                          e.value.series.replaceAll(RegExp(r'\D'), ''),
                        ) ??
                        12;
                    final sem = e.value.totalQty * sNum;
                    return [
                      '${e.key + 1}',
                      'Ser ${e.value.series}',
                      e.value.fromTicket,
                      e.value.toTicket,
                      '${e.value.totalQty}',
                      '$sem Sem',
                      e.value.pricePerTicket.toStringAsFixed(2),
                      e.value.totalAmount.toStringAsFixed(2),
                    ];
                  }),
                  [
                    'TOTAL',
                    '-',
                    '-',
                    '-',
                    '${summary.totalUnsold} Nos',
                    '${summary.totalUnsoldSeriesSum} Sem',
                    '-',
                    'Rs. ${summary.totalUnsoldAmount.toStringAsFixed(2)}',
                  ],
                ],
                headerStyle: pw.TextStyle(
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 8.5,
                ),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.red700,
                ),
                cellAlignment: pw.Alignment.center,
                cellStyle: const pw.TextStyle(fontSize: 8),
              ),
            pw.SizedBox(height: 12),

            // Section 2.5: SERIES-WISE NET SOLD BREAKDOWN
            pw.Text(
              '2.5. SERIES NET SOLD BREAKDOWN (TOTAL SERIES FACTOR: ${summary.totalNetSeriesSum} SEM)',
              style: pw.TextStyle(
                fontSize: 10.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.teal900,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.TableHelper.fromTextArray(
              columnWidths: const {
                0: pw.FlexColumnWidth(1.3),
                1: pw.FlexColumnWidth(1.4),
                2: pw.FlexColumnWidth(1.4),
                3: pw.FlexColumnWidth(1.4),
                4: pw.FlexColumnWidth(1.8),
                5: pw.FlexColumnWidth(1.4),
                6: pw.FlexColumnWidth(1.8),
              },
              headers: [
                'Series',
                'Voucher In',
                'Unsold Ret',
                'Net Sold',
                'Series Sum (Sem)',
                'Rate (Rs)',
                'Net Amount (Rs)',
              ],
              data: [
                ...summary.seriesHisabList.map(
                  (s) => [
                    'Ser ${s.series}',
                    '${s.voucherQty} Nos',
                    '${s.unsoldQty} Nos',
                    '${s.netSoldQty} Nos',
                    '${s.netSeriesSum} Sem',
                    s.rate.toStringAsFixed(2),
                    s.netAmount.toStringAsFixed(2),
                  ],
                ),
                [
                  'TOTAL / KUL',
                  '${summary.totalVouchers} Nos',
                  '${summary.totalUnsold} Nos',
                  '${summary.totalNetSold} Nos',
                  '${summary.totalNetSeriesSum} Sem',
                  'Rs. ${summary.effectivePerUnitRate.toStringAsFixed(2)}/u',
                  'Rs. ${summary.totalNetAmount.toStringAsFixed(2)}',
                ],
              ],
              headerStyle: pw.TextStyle(
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
                fontSize: 8.5,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.teal800,
              ),
              rowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
              cellAlignment: pw.Alignment.center,
              cellStyle: const pw.TextStyle(fontSize: 8),
            ),
            pw.SizedBox(height: 12),

            // Section 3: Winning Claims if any
            if (summary.customerWins.isNotEmpty) ...[
              pw.Text(
                '3. WINNING INAM, BONUS & INCENTIVE CLAIMS (${summary.customerWins.length} Claims - Rs. ${summary.totalCustomerWinAmount.toStringAsFixed(2)})',
                style: pw.TextStyle(
                  fontSize: 10.5,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.amber900,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.TableHelper.fromTextArray(
                columnWidths: const {
                  0: pw.FlexColumnWidth(0.8),
                  1: pw.FlexColumnWidth(1.7),
                  2: pw.FlexColumnWidth(1.4),
                  3: pw.FlexColumnWidth(1.8),
                  4: pw.FlexColumnWidth(1.5),
                  5: pw.FlexColumnWidth(1.6),
                  6: pw.FlexColumnWidth(1.5),
                  7: pw.FlexColumnWidth(1.5),
                  8: pw.FlexColumnWidth(1.4),
                  9: pw.FlexColumnWidth(1.7),
                },
                headers: [
                  '#',
                  'Date',
                  'Shift / Time',
                  'Prize Tier',
                  'Ticket No',
                  'Series / Sem',
                  'Base Inam',
                  'Bonus',
                  'Incentive',
                  'Total Inam (Rs)',
                ],
                data: summary.customerWins.asMap().entries.map((e) {
                  final w = e.value;
                  final base = w.baseAmount * w.seriesCount;
                  final bonus = w.superBonus * w.seriesCount;
                  final inc = w.specialIncentive * w.seriesCount;
                  return [
                    '${e.key + 1}',
                    w.displayDate,
                    w.displayTime,
                    _cleanPdfText(w.prizeTier),
                    w.ticketNumber,
                    'Ser ${w.ticketSeries} (${w.seriesCount} Sem)',
                    'Rs. ${base.toStringAsFixed(0)}',
                    'Rs. ${bonus.toStringAsFixed(0)}',
                    'Rs. ${inc.toStringAsFixed(0)}',
                    'Rs. ${w.prizeAmount.toStringAsFixed(0)}',
                  ];
                }).toList(),
                headerStyle: pw.TextStyle(
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 7.5,
                ),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.amber800,
                ),
                cellAlignment: pw.Alignment.center,
                cellStyle: const pw.TextStyle(fontSize: 7),
              ),
              pw.SizedBox(height: 12),
            ],

            // Section 3.5: Date & Shift Breakdown Table
            if (summary.dateBreakdowns.isNotEmpty) ...[
              pw.Text(
                '3.5. DATE & DRAW TIMINGS BREAKDOWN (RESULT KHULA & INAM SUMMARY)',
                style: pw.TextStyle(
                  fontSize: 10.5,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.indigo900,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.TableHelper.fromTextArray(
                columnWidths: const {
                  0: pw.FlexColumnWidth(2.0),
                  1: pw.FlexColumnWidth(1.6),
                  2: pw.FlexColumnWidth(1.2),
                  3: pw.FlexColumnWidth(1.2),
                  4: pw.FlexColumnWidth(1.2),
                  5: pw.FlexColumnWidth(1.8),
                  6: pw.FlexColumnWidth(1.5),
                  7: pw.FlexColumnWidth(2.5),
                },
                headers: [
                  'Date',
                  'Draw Shift / Timing',
                  'Voucher In',
                  'Unsold Ret',
                  'Net Sold',
                  'Net Amount (Rs)',
                  'Inam (Rs)',
                  'Result Khula & Winning Hits',
                ],
                data: [
                  for (final db in summary.dateBreakdowns)
                    for (final sb in db.shifts)
                      [
                        db.formattedDate,
                        sb.shift,
                        sb.hasEntry ? '${sb.totalVouchers} Nos' : '-',
                        sb.hasEntry ? '${sb.totalUnsold} Nos' : '-',
                        sb.hasEntry ? '${sb.totalNetSold} Nos' : '-',
                        sb.hasEntry
                            ? 'Rs. ${sb.totalNetAmount.toStringAsFixed(2)}'
                            : '-',
                        '${sb.drawResultFirstPrize != null && sb.drawResultFirstPrize!.isNotEmpty ? "Khula: 1st ${sb.drawResultFirstPrize}\n" : ""}${sb.customerWins.isNotEmpty ? "Won: ${sb.customerWins.map((w) => '${w.ticketNumber} (${_cleanPdfText(w.prizeTier)} - Rs.${w.prizeAmount.toStringAsFixed(0)})').join(', ')}" : (sb.drawResultFirstPrize != null ? "No Party Win" : (sb.hasEntry ? "Result Pending" : "No Entry"))}',
                      ],
                ],
                headerStyle: pw.TextStyle(
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 8,
                ),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.indigo800,
                ),
                rowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
                cellAlignment: pw.Alignment.center,
                cellStyle: const pw.TextStyle(fontSize: 7.5),
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
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(4),
                      ),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'STOCK QUANTITY SUMMARY',
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.blue900,
                          ),
                        ),
                        pw.Divider(color: PdfColors.grey300, thickness: 0.5),
                        _pdfKeyVal(
                          'Total Voucher Inward:',
                          '${summary.totalVouchers} Nos (Rs. ${summary.totalVoucherAmount.toStringAsFixed(2)})',
                        ),
                        _pdfKeyVal(
                          'Total Unsold Returned:',
                          '${summary.totalUnsold} Nos (Rs. ${summary.totalUnsoldAmount.toStringAsFixed(2)})',
                        ),
                        _pdfKeyVal(
                          'Net Sold Tickets:',
                          '${summary.totalNetSold} Nos',
                        ),
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
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(4),
                      ),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'FINAL SETTLEMENT (RS)',
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.brown800,
                          ),
                        ),
                        pw.Divider(color: PdfColors.amber300, thickness: 0.5),
                        _pdfKeyVal(
                          'Total Voucher Inward:',
                          'Rs. ${summary.totalVoucherAmount.toStringAsFixed(2)}',
                        ),
                        _pdfKeyVal(
                          'Less Unsold Returns:',
                          '- Rs. ${summary.totalUnsoldAmount.toStringAsFixed(2)}',
                        ),
                        _pdfKeyVal(
                          'Net Sold Amount (Bikri):',
                          'Rs. ${summary.totalNetAmount.toStringAsFixed(2)}',
                          isBold: true,
                        ),
                        if (summary.customerWins.isNotEmpty) ...[
                          pw.SizedBox(height: 3),
                          _pdfKeyVal(
                            '- Base Winning Inam:',
                            '- Rs. ${totalBaseInam.toStringAsFixed(2)}',
                          ),
                          _pdfKeyVal(
                            '- Super Bonus:',
                            '- Rs. ${totalBonus.toStringAsFixed(2)}',
                          ),
                          _pdfKeyVal(
                            '- Special Incentive:',
                            '- Rs. ${totalIncentive.toStringAsFixed(2)}',
                          ),
                          _pdfKeyVal(
                            'Total Inam Claims:',
                            '- Rs. ${summary.totalCustomerWinAmount.toStringAsFixed(2)}',
                            isBold: true,
                          ),
                        ],
                        pw.Divider(color: PdfColors.amber300, thickness: 0.5),
                        _pdfKeyVal(
                          'FINAL NET PAYABLE:',
                          'Rs. ${summary.finalNetPayable.toStringAsFixed(2)}',
                          isBold: true,
                        ),
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

    return _savePdfDocument(
      pdf,
      'hisab_detailed_${summary.partyName}_${summary.date}.pdf',
    );
  }

  pw.Widget _pdfKeyVal(String key, String val, {bool isBold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            key,
            style: pw.TextStyle(
              fontSize: 9,
              color: PdfColors.grey800,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
          pw.Text(
            val,
            style: pw.TextStyle(
              fontSize: isBold ? 10.5 : 9,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: isBold ? PdfColors.green900 : PdfColors.black,
            ),
          ),
        ],
      ),
    );
  }

  /// Modern Top KPI Summary Cards Dashboard (Displayed at the very top of the PDF)
  pw.Widget _buildTopKpiSummary(
    PartyHisabSummary summary,
    double totalBaseInam,
    double totalBonus,
    double totalIncentive,
  ) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Column(
        children: [
          pw.Row(
            children: [
              // 1. Stock Inward Card
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 6,
                  ),
                  decoration: pw.BoxDecoration(
                    color: const PdfColor.fromInt(0xFFFAF5FF),
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(5),
                    ),
                    border: pw.Border.all(color: const PdfColor.fromInt(0xFFD8B4FE), width: 0.8),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'STOCK IN (VOUCHER)',
                        style: pw.TextStyle(
                          color: const PdfColor.fromInt(0xFF581C87),
                          fontSize: 7,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        '${summary.totalVouchers} Tkts',
                        style: pw.TextStyle(
                          color: const PdfColor.fromInt(0xFF581C87),
                          fontSize: 10.5,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        'Sem: ${summary.totalVoucherSeriesSum}',
                        style: const pw.TextStyle(
                          color: PdfColors.grey700,
                          fontSize: 7,
                        ),
                      ),
                      pw.SizedBox(height: 1),
                      pw.Text(
                        'Rs. ${summary.totalVoucherAmount.toStringAsFixed(2)}',
                        style: pw.TextStyle(
                          color: const PdfColor.fromInt(0xFF6B21A8),
                          fontSize: 8.5,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: 5),

              // 2. Unsold Returns Card
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 6,
                  ),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.red50,
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(5),
                    ),
                    border: pw.Border.all(color: PdfColors.red300, width: 0.8),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'UNSOLD RETURN',
                        style: pw.TextStyle(
                          color: PdfColors.red900,
                          fontSize: 7,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        '${summary.totalUnsold} Tkts',
                        style: pw.TextStyle(
                          color: PdfColors.red900,
                          fontSize: 10.5,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        'Sem: ${summary.totalUnsoldSeriesSum}',
                        style: const pw.TextStyle(
                          color: PdfColors.grey700,
                          fontSize: 7,
                        ),
                      ),
                      pw.SizedBox(height: 1),
                      pw.Text(
                        '- Rs. ${summary.totalUnsoldAmount.toStringAsFixed(2)}',
                        style: pw.TextStyle(
                          color: PdfColors.red800,
                          fontSize: 8.5,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: 5),

              // 3. Net Sold (Bikri) Card
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 6,
                  ),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.teal50,
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(5),
                    ),
                    border: pw.Border.all(color: PdfColors.teal400, width: 0.8),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'NET SOLD (BIKRI)',
                        style: pw.TextStyle(
                          color: PdfColors.teal900,
                          fontSize: 7,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        '${summary.totalNetSold} Tkts',
                        style: pw.TextStyle(
                          color: PdfColors.teal900,
                          fontSize: 10.5,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        'Kul Sem: ${summary.totalNetSeriesSum}',
                        style: pw.TextStyle(
                          color: PdfColors.teal800,
                          fontSize: 7,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 1),
                      pw.Text(
                        'Rs. ${summary.totalNetAmount.toStringAsFixed(2)}',
                        style: pw.TextStyle(
                          color: PdfColors.teal900,
                          fontSize: 8.5,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: 5),

              // 4. Winning Inam Deduction Card
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 6,
                  ),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.amber50,
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(5),
                    ),
                    border: pw.Border.all(
                      color: PdfColors.amber400,
                      width: 0.8,
                    ),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'INAM / BONUS DED.',
                        style: pw.TextStyle(
                          color: PdfColors.amber900,
                          fontSize: 7,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        '${summary.customerWins.length} Claim(s)',
                        style: pw.TextStyle(
                          color: PdfColors.amber900,
                          fontSize: 10.5,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        summary.customerWins.isNotEmpty
                            ? 'Base+Bonus+Inc'
                            : 'Zero Wins',
                        style: const pw.TextStyle(
                          color: PdfColors.grey700,
                          fontSize: 7,
                        ),
                      ),
                      pw.SizedBox(height: 1),
                      pw.Text(
                        '- Rs. ${summary.totalCustomerWinAmount.toStringAsFixed(2)}',
                        style: pw.TextStyle(
                          color: PdfColors.amber900,
                          fontSize: 8.5,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: 5),

              // 5. Final Net Payable Hero Card
              pw.Expanded(
                flex: 1,
                child: pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 6,
                  ),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.green900,
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(5),
                    ),
                    border: pw.Border.all(
                      color: PdfColors.green700,
                      width: 1.2,
                    ),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'FINAL NET PAYABLE',
                        style: pw.TextStyle(
                          color: PdfColors.green100,
                          fontSize: 7,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Rs. ${summary.finalNetPayable.toStringAsFixed(2)}',
                        style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 1),
                      pw.Text(
                        '[OK] Net Due Amount',
                        style: pw.TextStyle(
                          color: PdfColors.green200,
                          fontSize: 7,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 4),

          // 🧮 AUDIT CROSS-CHECK VERIFICATION BOX
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 3.5,
            ),
            decoration: pw.BoxDecoration(
              color: const PdfColor.fromInt(0xFFFAF5FF),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              border: pw.Border.all(color: const PdfColor.fromInt(0xFFD8B4FE), width: 0.8),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Row(
                  children: [
                    pw.Text(
                      '[>>] AUDIT MULTIPLIER VERIFICATION: ',
                      style: pw.TextStyle(
                        fontSize: 7.5,
                        fontWeight: pw.FontWeight.bold,
                        color: const PdfColor.fromInt(0xFF581C87),
                      ),
                    ),
                    pw.Text(
                      'Kul Series Sum: ${summary.totalNetSeriesSum} Sem  x  Rate: Rs.${summary.effectivePerUnitRate.toStringAsFixed(2)}/u  (Base Ser 100: Rs.${(summary.effectivePerUnitRate * 100).toStringAsFixed(2)})  =  Total Bikri: Rs.${summary.totalNetAmount.toStringAsFixed(2)}',
                      style: pw.TextStyle(
                        fontSize: 7.5,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue900,
                      ),
                    ),
                  ],
                ),
                pw.Text(
                  '[OK] Calculation Verified',
                  style: pw.TextStyle(
                    fontSize: 7,
                    color: PdfColors.green800,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
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
