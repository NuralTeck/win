import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../shared/models/ticket_sale_model.dart';
import '../../operations/models/winning_claim_model.dart';
import '../../operations/utils/winner_verification_engine.dart';
import '../../../core/database/database_service.dart';
import '../../operations/models/lottery_sambad_result_model.dart';

class BookingPdfService {
  BookingPdfService._internal();
  static final BookingPdfService instance = BookingPdfService._internal();

  static pw.Font? _cachedRegularFont;
  static pw.Font? _cachedBoldFont;

  // ─── Company branding ───────────────────────────────────────────────────────
  static const String _companyName = 'PHANTOM MANAGEMENT';
  static const String _companyTagline = 'Lottery & Hisab Management System';

  /// Branded header strip on page 2+ only (page 1 has its own full title banner already)
  static pw.Widget _buildPdfPageHeader(
    pw.Context ctx, {
    String subtitle = '',
  }) {
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
  static pw.Widget _buildPdfPageFooter(pw.Context ctx) {
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

  static Future<void> _ensureFontsLoaded() async {
    if (_cachedRegularFont != null && _cachedBoldFont != null) return;
    try {
      _cachedRegularFont = await PdfGoogleFonts.robotoRegular().timeout(const Duration(milliseconds: 1800));
      _cachedBoldFont = await PdfGoogleFonts.robotoBold().timeout(const Duration(milliseconds: 1800));
    } catch (e) {
      debugPrint('ℹ️ PDF Font loader using standard typography fallback: $e');
      _cachedRegularFont = pw.Font.helvetica();
      _cachedBoldFont = pw.Font.helveticaBold();
    }
  }

  /// Helper to categorize draw name into standard shift
  String getDrawShift(String drawName) {
    final lower = drawName.toLowerCase();
    if (lower.contains('1 pm') || lower.contains('1pm') || lower.contains('morning')) {
      return 'Dear 1 PM';
    } else if (lower.contains('6 pm') || lower.contains('6pm') || lower.contains('day')) {
      return 'Dear 6 PM';
    } else if (lower.contains('8 pm') || lower.contains('8pm') || lower.contains('night') || lower.contains('evening')) {
      return 'Dear 8 PM';
    }
    return 'Dear 1 PM';
  }

  /// Clean emojis, unsupported non-ASCII unicode symbols, or unprintable characters that render as tofu boxes [?] in PDF standard fonts
  String _cleanPdfText(String text) {
    if (text.isEmpty) return '';
    final cleaned = text.replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();
    return cleaned.isNotEmpty ? cleaned : 'Walk-in Customer';
  }

  Future<Uint8List> generatePdfReport({
    required DateTime date,
    required List<TicketSaleModel> sales,
    String rangeTitle = 'DAILY BOOKINGS & SALES SUMMARY REPORT',
    String? customerName,
    bool isSummaryOnly = false,
    void Function(double progress, String status)? onProgress,
  }) async {
    onProgress?.call(0.05, 'Organizing shifts & bookings...');
    await Future.delayed(const Duration(milliseconds: 20));

    final pdf = pw.Document();
    final dateFormat = DateFormat('dd-MM-yyyy (EEEE)');
    final timeFormat = DateFormat('hh:mm a');
    final dateStr = dateFormat.format(date);
    final generatedAt = timeFormat.format(DateTime.now());

    // Cache formatted dates by integer key (YYYYMMDD) so DateFormat runs at most 1-2 times total instead of 138,000 times!
    final Map<int, (String ymd, String display, String dmy)> dateCache = {};
    (String, String, String) getCachedDate(DateTime dt) {
      final key = dt.year * 10000 + dt.month * 100 + dt.day;
      final existing = dateCache[key];
      if (existing != null) return existing;
      final ymd = DateFormat('yyyy-MM-dd').format(dt);
      final display = DateFormat('dd/MM/yy (EEE)').format(dt);
      final dmy = DateFormat('dd/MM/yyyy').format(dt);
      final val = (ymd, display, dmy);
      dateCache[key] = val;
      return val;
    }

    final Set<String> targetDateSet = {
      DateFormat('dd/MM/yyyy').format(date),
      DateFormat('yyyy-MM-dd').format(date),
    };

    final Map<String, List<TicketSaleModel>> shiftSales = {
      'Dear 1 PM': [],
      'Dear 6 PM': [],
      'Dear 8 PM': [],
    };
    final Map<String, _SeriesSummaryData> seriesSummaryMap = {};
    final Map<String, _DateSummaryData> dateSummaryMap = {};
    final Map<String, List<TicketSaleModel>> salesBySeries = {};
    int grandTotalQty = 0;
    double grandTotalAmount = 0.0;

    // Single ultra-fast O(N) pass for all sales aggregations
    for (var sale in sales) {
      grandTotalQty += sale.quantity;
      grandTotalAmount += sale.totalAmount;

      final shift = getDrawShift(sale.drawName);
      shiftSales[shift]?.add(sale);

      final ser = sale.ticketSeries.toUpperCase();
      salesBySeries.putIfAbsent(ser, () => []).add(sale);

      // Series summary aggregation
      final sSummary = seriesSummaryMap.putIfAbsent(
        ser,
        () => _SeriesSummaryData(
          series: ser,
          quantity: 0,
          unitPrice: sale.pricePerTicket,
          totalAmount: 0.0,
        ),
      );
      sSummary.quantity += sale.quantity;
      sSummary.totalAmount += sale.totalAmount;

      // Date summary & target dates aggregation
      final sDate = sale.drawDate.year > 2000 ? sale.drawDate.toLocal() : sale.saleDate.toLocal();
      final (dateKey, displayDate, dmyDate) = getCachedDate(sDate);
      targetDateSet.add(dmyDate);
      targetDateSet.add(dateKey);

      final dateSummary = dateSummaryMap.putIfAbsent(
        dateKey,
        () => _DateSummaryData(
          dateKey: dateKey,
          displayDate: displayDate,
          rawDate: sDate,
        ),
      );
      dateSummary.totalTickets += sale.quantity;
      dateSummary.totalAmount += sale.totalAmount;
      dateSummary.seriesQtyMap[ser] = (dateSummary.seriesQtyMap[ser] ?? 0) + sale.quantity;
      dateSummary.seriesAmtMap[ser] = (dateSummary.seriesAmtMap[ser] ?? 0.0) + sale.totalAmount;
      dateSummary.seriesRateMap[ser] = sale.pricePerTicket;

      if (shift == 'Dear 1 PM') {
        dateSummary.qty1PM += sale.quantity;
        dateSummary.amt1PM += sale.totalAmount;
      } else if (shift == 'Dear 6 PM') {
        dateSummary.qty6PM += sale.quantity;
        dateSummary.amt6PM += sale.totalAmount;
      } else if (shift == 'Dear 8 PM') {
        dateSummary.qty8PM += sale.quantity;
        dateSummary.amt8PM += sale.totalAmount;
      }
    }

    final sortedSeriesKeys = seriesSummaryMap.keys.toList()
      ..sort((a, b) {
        final na = int.tryParse(a.replaceAll(RegExp(r'\D'), ''));
        final nb = int.tryParse(b.replaceAll(RegExp(r'\D'), ''));
        if (na != null && nb != null) return na.compareTo(nb);
        return a.compareTo(b);
      });

    // Calculate verified winners & itemized prize/bonus/incentive metrics
    final List<WinningClaimModel> winningClaims = [];
    try {
      onProgress?.call(0.12, 'Verifying lottery results & inam claims...');
      await Future.delayed(const Duration(milliseconds: 20));

      final rawResults = await DatabaseService.instance.getLotteryResults();

      int verifiedResultCount = 0;
      for (final raw in rawResults) {
        final dDateStr = raw['drawDateStr']?.toString() ?? '';
        if (dDateStr.isEmpty) continue;

        // Instant match against precomputed target date set
        final isDateMatch = targetDateSet.any((td) => dDateStr.contains(td));
        if (!isDateMatch) continue;

        final drawTimeStr = raw['drawTimeStr']?.toString() ?? '';
        final firstP = raw['firstPrize']?.toString() ?? '';
        List<String> splitNums(String key) {
          final v = raw[key]?.toString();
          return (v != null && v.isNotEmpty) ? v.split(',') : [];
        }

        final resModel = LotterySambadResultModel(
          drawId: raw['id']?.toString() ?? '',
          drawName: raw['drawName']?.toString() ?? 'Lottery Draw',
          drawDateStr: raw['drawDateStr']?.toString() ?? '',
          drawTimeStr: drawTimeStr,
          firstPrize: firstP,
          consolationPrize: firstP.contains(' ') ? firstP.split(' ').last : (firstP.length >= 5 ? firstP.substring(firstP.length - 5) : firstP),
          secondPrizeNumbers: splitNums('secondPrizeNumbers'),
          thirdPrizeNumbers: splitNums('thirdPrizeNumbers'),
          fourthPrizeNumbers: splitNums('fourthPrizeNumbers'),
          fifthPrizeNumbers: splitNums('fifthPrizeNumbers'),
          publishedAt: DateTime.tryParse(raw['publishedAt']?.toString() ?? '') ?? DateTime.now(),
        );

        final claims = WinnerVerificationEngine.verifyWinners(soldTickets: sales, result: resModel);
        winningClaims.addAll(claims);

        verifiedResultCount++;
        if (verifiedResultCount % 3 == 0) {
          await Future.delayed(const Duration(milliseconds: 8));
        }
      }
    } catch (_) {}

    double grandBasePrize = 0.0;
    double grandSuperBonus = 0.0;
    double grandSpecialIncentive = 0.0;
    double grandTotalWinningPayout = 0.0;

    for (final claim in winningClaims) {
      grandBasePrize += (claim.baseAmount * claim.seriesCount);
      grandSuperBonus += claim.superBonus;
      grandSpecialIncentive += claim.specialIncentive;
      grandTotalWinningPayout += claim.prizeAmount;
    }

    // Match Inam payout per date
    for (final claim in winningClaims) {
      TicketSaleModel? matchedTicket;
      final candidates = salesBySeries[claim.ticketSeries.toUpperCase()];
      if (candidates != null && candidates.isNotEmpty) {
        for (final s in candidates) {
          if (s.ticketNumber == claim.ticketNumber || s.ticketNumber.contains(claim.ticketNumber)) {
            matchedTicket = s;
            break;
          }
        }
      }
      matchedTicket ??= sales.first;
      final dt = matchedTicket.drawDate.year > 2000 ? matchedTicket.drawDate.toLocal() : matchedTicket.saleDate.toLocal();
      final (dateKey, _, _) = getCachedDate(dt);
      if (dateSummaryMap.containsKey(dateKey)) {
        dateSummaryMap[dateKey]!.totalInamPayout += claim.prizeAmount;
      }
    }

    final sortedDateKeys = dateSummaryMap.keys.toList()..sort();

    final netProfitLoss = grandTotalAmount - grandTotalWinningPayout;
    final isProfit = netProfitLoss >= 0;

    int grandTotalSeriesUnits = 0;
    for (final item in seriesSummaryMap.values) {
      grandTotalSeriesUnits += item.totalSeriesUnits;
    }
    final double effectiveUnitRate = grandTotalSeriesUnits > 0
        ? grandTotalAmount / grandTotalSeriesUnits
        : 3.75;

    // Fetch Roboto Unicode fonts (cached & offline-safe)
    onProgress?.call(0.20, 'Loading fonts & preparing layout...');
    await Future.delayed(const Duration(milliseconds: 20));
    await _ensureFontsLoaded();
    final regularFont = _cachedRegularFont ?? pw.Font.helvetica();
    final boldFont = _cachedBoldFont ?? pw.Font.helveticaBold();

    // Build list of document widgets asynchronously
    final List<pw.Widget> contentWidgets = [];

    // TOP HEADER TITLE BANNER — Premium clean style (no filled box)
    contentWidgets.add(
      pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 10),
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(color: PdfColor.fromInt(0xFF6B21A8), width: 1.5),
          ),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Row(
              children: [
                pw.Container(width: 4, height: 32, color: PdfColor.fromInt(0xFF6B21A8)),
                pw.SizedBox(width: 8),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      _companyName,
                      style: pw.TextStyle(
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColor.fromInt(0xFF1E1B4B),
                      ),
                    ),
                    pw.Text(
                      rangeTitle.toUpperCase(),
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColor.fromInt(0xFF6B21A8),
                      ),
                    ),
                    if (customerName != null && customerName.isNotEmpty && customerName != 'All')
                      pw.Text(
                        'Customer / Seller: ${customerName.toUpperCase()}',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromInt(0xFF1E1B4B),
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
                  'DATE: $dateStr',
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF1E1B4B)),
                ),
                pw.Text(
                  'Generated At: $generatedAt',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    contentWidgets.add(pw.SizedBox(height: 10));

    // 🌟 TOP EXECUTIVE KPI SUMMARY DASHBOARD (VISIBLE AT VERY TOP)
    contentWidgets.add(
      pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 12),
        child: pw.Column(
          children: [
            pw.Row(
              children: [
                // 1. Total Tickets
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                    decoration: pw.BoxDecoration(
                      color: const PdfColor.fromInt(0xFFFAF5FF),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
                      border: pw.Border.all(color: const PdfColor.fromInt(0xFFD8B4FE), width: 0.8),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('TOTAL TICKETS', style: pw.TextStyle(color: const PdfColor.fromInt(0xFF581C87), fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 2),
                        pw.Text('$grandTotalQty Tkts', style: pw.TextStyle(color: const PdfColor.fromInt(0xFF581C87), fontSize: 11, fontWeight: pw.FontWeight.bold)),
                        pw.Text('Kul Sem: $grandTotalSeriesUnits Sem', style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 7)),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 6),

                // 2. Total Sales Collection
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.teal50,
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
                      border: pw.Border.all(color: PdfColors.teal300, width: 0.8),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('TOTAL SALES', style: pw.TextStyle(color: PdfColors.teal900, fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 2),
                        pw.Text('Rs. ${grandTotalAmount.toStringAsFixed(2)}', style: pw.TextStyle(color: PdfColors.teal900, fontSize: 11, fontWeight: pw.FontWeight.bold)),
                        pw.Text('Gross Collection', style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 7)),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 6),

                // 3. Winning Inam Deduction
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.amber50,
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
                      border: pw.Border.all(color: PdfColors.amber300, width: 0.8),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('WINNING INAM', style: pw.TextStyle(color: PdfColors.amber900, fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 2),
                        pw.Text('Rs. ${grandTotalWinningPayout.toStringAsFixed(0)}', style: pw.TextStyle(color: PdfColors.red900, fontSize: 11, fontWeight: pw.FontWeight.bold)),
                        pw.Text('${winningClaims.length} Claim(s)', style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 7)),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 6),

                // 4. Net Due Hero Card
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                    decoration: pw.BoxDecoration(
                      color: isProfit ? PdfColors.blue900 : PdfColors.red900,
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
                      border: pw.Border.all(color: isProfit ? PdfColors.blue700 : PdfColors.red700, width: 1.2),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(isProfit ? 'NET DUE AMOUNT' : 'NET DUE (PAYABLE)', style: pw.TextStyle(color: PdfColors.white, fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          isProfit ? 'Rs. ${netProfitLoss.toStringAsFixed(2)}' : '-Rs. ${netProfitLoss.abs().toStringAsFixed(2)}',
                          style: pw.TextStyle(color: isProfit ? PdfColors.amber300 : PdfColors.white, fontSize: 11.5, fontWeight: pw.FontWeight.bold),
                        ),
                        pw.Text('[OK] Final Settlement', style: const pw.TextStyle(color: PdfColors.grey300, fontSize: 7)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 4),

            // Audit Check Box
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
              decoration: pw.BoxDecoration(
                color: PdfColors.cyan50,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                border: pw.Border.all(color: PdfColors.cyan200, width: 0.8),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    '[>>] AUDIT MULTIPLIER: Total Sem: $grandTotalSeriesUnits Sem  x  Rate: Rs.${effectiveUnitRate.toStringAsFixed(2)}/u (Base Ser 100: Rs.${(effectiveUnitRate * 100).toStringAsFixed(2)})  =  Total Sale: Rs.${grandTotalAmount.toStringAsFixed(2)}',
                    style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.cyan900),
                  ),
                  pw.Text('[OK] Verified', style: pw.TextStyle(fontSize: 7, color: PdfColors.green800, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    // 📅 DATE-WISE CONSOLIDATED SUMMARY & PERFORMANCE BREAKDOWN (ALWAYS RENDERED)
    if (sortedDateKeys.isNotEmpty) {
      contentWidgets.add(
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 6,
          ),
          color: PdfColors.blue50,
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'DATE-WISE SALES & KUL INAM SUMMARY BREAKDOWN',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blue900,
                ),
              ),
              pw.Text(
                'Kul Inam: Rs. ${grandTotalWinningPayout.toStringAsFixed(0)}',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.red900,
                ),
              ),
            ],
          ),
        ),
      );
      contentWidgets.add(pw.SizedBox(height: 6));
      contentWidgets.add(
        pw.TableHelper.fromTextArray(
          border: pw.TableBorder.all(
            color: PdfColors.grey300,
            width: 0.5,
          ),
          headerStyle: pw.TextStyle(
            fontSize: 8.5,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
          ),
          headerDecoration: const pw.BoxDecoration(
            color: PdfColors.blue800,
          ),
          cellStyle: const pw.TextStyle(fontSize: 8),
          cellPadding: const pw.EdgeInsets.symmetric(
            horizontal: 3,
            vertical: 4,
          ),
          columnWidths: {
            0: const pw.FixedColumnWidth(80),
            1: const pw.FixedColumnWidth(60),
            2: const pw.FixedColumnWidth(60),
            3: const pw.FixedColumnWidth(60),
            4: const pw.FixedColumnWidth(52),
            5: const pw.FixedColumnWidth(82),
            6: const pw.FixedColumnWidth(72),
            7: const pw.FixedColumnWidth(81),
          },
          cellAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerRight,
            2: pw.Alignment.centerRight,
            3: pw.Alignment.centerRight,
            4: pw.Alignment.centerRight,
            5: pw.Alignment.centerRight,
            6: pw.Alignment.centerRight,
            7: pw.Alignment.centerRight,
          },
          headers: [
            'Date & Day',
            '1 PM (Rs)',
            '6 PM (Rs)',
            '8 PM (Rs)',
            'Total Tkts',
            'Total Sale (Rs)',
            'Kul Inam (Rs)',
            'Net Hisab (Rs)',
          ],
          data: [
            ...sortedDateKeys.map((key) {
              final d = dateSummaryMap[key]!;
              final netDay = d.totalAmount - d.totalInamPayout;
              return [
                d.displayDate,
                NumberFormat('#,##0').format(d.amt1PM),
                NumberFormat('#,##0').format(d.amt6PM),
                NumberFormat('#,##0').format(d.amt8PM),
                NumberFormat('#,##0').format(d.totalTickets),
                NumberFormat('#,##0.00').format(d.totalAmount),
                NumberFormat('#,##0').format(d.totalInamPayout),
                NumberFormat('#,##0.00').format(netDay),
              ];
            }),
            if (sortedDateKeys.length > 1)
              [
                'TOTAL / KUL',
                NumberFormat('#,##0').format((shiftSales['Dear 1 PM'] ?? []).fold<double>(0.0, (sum, s) => sum + s.totalAmount)),
                NumberFormat('#,##0').format((shiftSales['Dear 6 PM'] ?? []).fold<double>(0.0, (sum, s) => sum + s.totalAmount)),
                NumberFormat('#,##0').format((shiftSales['Dear 8 PM'] ?? []).fold<double>(0.0, (sum, s) => sum + s.totalAmount)),
                NumberFormat('#,##0').format(grandTotalQty),
                NumberFormat('#,##0.00').format(grandTotalAmount),
                NumberFormat('#,##0').format(grandTotalWinningPayout),
                NumberFormat('#,##0.00').format(grandTotalAmount - grandTotalWinningPayout),
              ],
          ],
        ),
      );
      contentWidgets.add(pw.SizedBox(height: 14));

      // 📋 DATE & SERIES-WISE ITEMISED BREAKDOWN TABLE (KON KONSE DATE KITNA SERIES KON KON SELL HUA)
      contentWidgets.add(
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 6,
          ),
          color: PdfColors.cyan50,
          child: pw.Text(
            'DATE & SERIES-WISE ITEMISED AUDIT (KON KONSE DATE KITNA SERIES SELL HUA)',
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.cyan900,
            ),
          ),
        ),
      );
      contentWidgets.add(pw.SizedBox(height: 6));

      final List<List<String>> dateSeriesRows = [];
      for (final key in sortedDateKeys) {
        final d = dateSummaryMap[key]!;
        final sortedSer = d.seriesQtyMap.keys.toList()
          ..sort((a, b) {
            final na = int.tryParse(a.replaceAll(RegExp(r'\D'), ''));
            final nb = int.tryParse(b.replaceAll(RegExp(r'\D'), ''));
            if (na != null && nb != null) return na.compareTo(nb);
            return a.compareTo(b);
          });
        for (final ser in sortedSer) {
          final qty = d.seriesQtyMap[ser] ?? 0;
          final amt = d.seriesAmtMap[ser] ?? 0.0;
          final rate = d.seriesRateMap[ser] ?? (qty > 0 ? amt / qty : 0.0);
          dateSeriesRows.add([
            d.displayDate,
            'Series $ser',
            '$qty Tkts',
            'Rs. ${rate.toStringAsFixed(2)}',
            'Rs. ${amt.toStringAsFixed(2)}',
          ]);
        }
      }

      contentWidgets.add(
        pw.TableHelper.fromTextArray(
          border: pw.TableBorder.all(
            color: PdfColors.grey300,
            width: 0.5,
          ),
          headerStyle: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
          ),
          headerDecoration: const pw.BoxDecoration(
            color: PdfColors.cyan800,
          ),
          cellStyle: const pw.TextStyle(fontSize: 8.5),
          cellPadding: const pw.EdgeInsets.symmetric(
            horizontal: 6,
            vertical: 4,
          ),
          columnWidths: {
            0: const pw.FixedColumnWidth(110),
            1: const pw.FixedColumnWidth(100),
            2: const pw.FixedColumnWidth(95),
            3: const pw.FixedColumnWidth(100),
            4: const pw.FixedColumnWidth(142),
          },
          cellAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerLeft,
            2: pw.Alignment.center,
            3: pw.Alignment.centerRight,
            4: pw.Alignment.centerRight,
          },
          headers: [
            'Draw Date',
            'Series Name',
            'Tickets Sold (Qty)',
            'Price / Rate (Rs)',
            'Total Amount (Rs)',
          ],
          data: dateSeriesRows,
        ),
      );
      contentWidgets.add(pw.SizedBox(height: 14));
    }

    // If Summary-Only: Render consolidated Shift summary table instead of line-by-line ticket items
    if (isSummaryOnly) {
      contentWidgets.add(
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 6,
          ),
          color: const PdfColor.fromInt(0xFFFAF5FF),
          child: pw.Text(
            'DRAW SHIFT SALES CONSOLIDATION (SUMMARY ONLY)',
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: const PdfColor.fromInt(0xFF581C87),
            ),
          ),
        ),
      );
      contentWidgets.add(pw.SizedBox(height: 6));
      contentWidgets.add(
        pw.TableHelper.fromTextArray(
          border: pw.TableBorder.all(
            color: PdfColors.grey300,
            width: 0.5,
          ),
          headerStyle: pw.TextStyle(
            fontSize: 9.5,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
          ),
          headerDecoration: const pw.BoxDecoration(
            color: PdfColor.fromInt(0xFF6B21A8),
          ),
          cellStyle: const pw.TextStyle(fontSize: 9),
          cellPadding: const pw.EdgeInsets.symmetric(
            horizontal: 6,
            vertical: 5,
          ),
          cellAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.center,
            2: pw.Alignment.centerRight,
            3: pw.Alignment.centerRight,
          },
          headers: [
            'Shift Name',
            'Draw Timing',
            'Total Tickets Sold',
            'Total Collection (Rs)',
          ],
          data: [
            for (final shiftName in ['Dear 1 PM', 'Dear 6 PM', 'Dear 8 PM'])
              [
                shiftName,
                shiftName.contains('1') ? '01:00 PM (Morning)' : (shiftName.contains('6') ? '06:00 PM (Day)' : '08:00 PM (Night)'),
                '${(shiftSales[shiftName] ?? []).fold(0, (sum, i) => sum + i.quantity)}',
                'Rs. ${(shiftSales[shiftName] ?? []).fold(0.0, (sum, i) => sum + i.totalAmount).toStringAsFixed(2)}',
              ],
          ],
        ),
      );
      contentWidgets.add(pw.SizedBox(height: 14));
    } else {
      // FULL DETAILED PDF: Process Shift by Shift, chunking tickets in batches of 35 rows
      int totalProcessedTickets = 0;
      final int totalTicketsToProcess = sales.length;

      for (final shiftName in ['Dear 1 PM', 'Dear 6 PM', 'Dear 8 PM']) {
        final shiftList = shiftSales[shiftName] ?? [];

        contentWidgets.add(
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 6,
            ),
            color: const PdfColor.fromInt(0xFFFAF5FF),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'DRAW SHIFT: $shiftName',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: const PdfColor.fromInt(0xFF581C87),
                  ),
                ),
                pw.Text(
                  'Tickets: ${shiftList.fold(0, (sum, i) => sum + i.quantity)}  |  Total: Rs. ${shiftList.fold(0.0, (sum, i) => sum + i.totalAmount).toStringAsFixed(2)}',
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: const PdfColor.fromInt(0xFF581C87),
                  ),
                ),
              ],
            ),
          ),
        );
        contentWidgets.add(pw.SizedBox(height: 6));

        if (shiftList.isEmpty) {
          contentWidgets.add(
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 6),
              child: pw.Text(
                'No bookings recorded for $shiftName.',
                style: pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.grey600,
                  fontStyle: pw.FontStyle.italic,
                ),
              ),
            ),
          );
        } else {
          // Compress consecutive tickets and identical bookings into compact ranges
          final compressedRows = compressTicketSales(shiftList);

          // Chunk compressed tickets in batches of 65
          const int chunkSize = 65;
          final int totalChunks = (compressedRows.length / chunkSize).ceil();

          for (int c = 0; c < totalChunks; c++) {
            final start = c * chunkSize;
            final end = math.min(start + chunkSize, compressedRows.length);
            final chunkItems = compressedRows.sublist(start, end);

            contentWidgets.add(
              pw.TableHelper.fromTextArray(
                border: pw.TableBorder.all(
                  color: PdfColors.grey300,
                  width: 0.5,
                ),
                headerStyle: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFF6B21A8),
                ),
                cellStyle: const pw.TextStyle(fontSize: 8.5),
                cellPadding: const pw.EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 3,
                ),
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.center,
                  2: pw.Alignment.center,
                  3: pw.Alignment.centerRight,
                  4: pw.Alignment.centerRight,
                  5: pw.Alignment.centerRight,
                  6: pw.Alignment.centerLeft,
                },
                headers: [
                  'S.No',
                  'Series',
                  'Ticket / Range',
                  'Qty',
                  'Rate (Rs)',
                  'Total (Rs)',
                  'Seller/Buyer',
                ],
                data: List.generate(chunkItems.length, (i) {
                  final item = chunkItems[i];
                  final globalIdx = start + i + 1;
                  return [
                    '$globalIdx',
                    item.series,
                    item.ticketRangeDisplay,
                    '${item.quantity}',
                    'Rs. ${item.pricePerTicket.toStringAsFixed(2)}',
                    'Rs. ${item.totalAmount.toStringAsFixed(2)}',
                    _cleanPdfText(item.seller),
                  ];
                }),
              ),
            );

            if (c < totalChunks - 1) {
              contentWidgets.add(pw.SizedBox(height: 6));
            }

            final chunkQty = chunkItems.fold(0, (sum, i) => sum + i.quantity);
            totalProcessedTickets += chunkQty;
            final progress = 0.25 + (0.60 * (totalProcessedTickets / math.max(totalTicketsToProcess, 1)));
            onProgress?.call(
              progress.clamp(0.0, 0.85),
              'Rendering $shiftName: $totalProcessedTickets / $totalTicketsToProcess tickets...',
            );
            // Yield execution to the Flutter engine so the progress bar updates smoothly at 60 FPS
            await Future.delayed(const Duration(milliseconds: 18));
          }
        }
        contentWidgets.add(pw.SizedBox(height: 14));
      }
    }

    contentWidgets.add(pw.Divider(color: const PdfColor.fromInt(0xFF6B21A8), thickness: 1.5));
    contentWidgets.add(pw.SizedBox(height: 10));

    // GRAND SERIES SUMMARY TABLE
    contentWidgets.add(
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 6,
        ),
        color: PdfColors.teal50,
        child: pw.Text(
          'FINAL SERIES SUMMARY & RATE BREAKDOWN',
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.teal900,
          ),
        ),
      ),
    );
    contentWidgets.add(pw.SizedBox(height: 6));
    if (sortedSeriesKeys.isEmpty) {
      contentWidgets.add(
        pw.Text(
          'No bookings found for selected date.',
          style: const pw.TextStyle(fontSize: 10),
        ),
      );
    } else {
      contentWidgets.add(
        pw.TableHelper.fromTextArray(
          border: pw.TableBorder.all(
            color: PdfColors.grey300,
            width: 0.5,
          ),
          headerStyle: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
          ),
          headerDecoration: const pw.BoxDecoration(
            color: PdfColors.teal800,
          ),
          cellStyle: const pw.TextStyle(fontSize: 8.5),
          cellPadding: const pw.EdgeInsets.symmetric(
            horizontal: 6,
            vertical: 4,
          ),
          cellAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.center,
            2: pw.Alignment.center,
            3: pw.Alignment.centerRight,
            4: pw.Alignment.centerRight,
          },
          headers: [
            'Series Name',
            'Tickets Sold (Qty)',
            'Series Sum (Sem)',
            'Unit Price / Rate (Rs)',
            'Total Amount (Rs)',
          ],
          data: [
            ...sortedSeriesKeys.map((key) {
              final data = seriesSummaryMap[key]!;
              return [
                'Series ${data.series}',
                '${data.quantity} Tkts',
                '${data.totalSeriesUnits} Sem',
                'Rs. ${data.unitPrice.toStringAsFixed(2)}',
                'Rs. ${data.totalAmount.toStringAsFixed(2)}',
              ];
            }),
            [
              'TOTAL / KUL',
              '$grandTotalQty Tkts',
              '$grandTotalSeriesUnits Sem',
              'Rs. ${effectiveUnitRate.toStringAsFixed(2)}/u',
              'Rs. ${grandTotalAmount.toStringAsFixed(2)}',
            ],
          ],
        ),
      );
      contentWidgets.add(pw.SizedBox(height: 4));
      contentWidgets.add(
        pw.Text(
          '[>>] Formula Check: $grandTotalSeriesUnits Sem x Rs.${effectiveUnitRate.toStringAsFixed(2)} = Rs.${grandTotalAmount.toStringAsFixed(2)} Total Sale',
          style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic, color: PdfColors.teal900),
        ),
      );
    }
    contentWidgets.add(pw.SizedBox(height: 12));

    // ITEMISED WINNING PRIZE, BONUS & INCENTIVE BREAKDOWN TABLE
    if (winningClaims.isNotEmpty) {
      contentWidgets.add(
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          color: PdfColors.amber50,
          child: pw.Text(
            'WINNING INAM & BONUS BREAKDOWN',
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.amber900,
            ),
          ),
        ),
      );
      contentWidgets.add(pw.SizedBox(height: 6));

      const int winChunkSize = 35;
      final int winChunks = (winningClaims.length / winChunkSize).ceil();
      for (int wc = 0; wc < winChunks; wc++) {
        final start = wc * winChunkSize;
        final end = math.min(start + winChunkSize, winningClaims.length);
        final chunkClaims = winningClaims.sublist(start, end);

        contentWidgets.add(
          pw.TableHelper.fromTextArray(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.amber800),
            cellStyle: const pw.TextStyle(fontSize: 8.5),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.center,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerRight,
            },
            headers: [
              'Inam / Ticket',
              'Series (Sem)',
              'Inam (Rs)',
              'Bonus (Rs)',
              'Incentive (Rs)',
              'Total Inam (Rs)',
            ],
            data: chunkClaims.map((claim) {
              final baseTotal = claim.baseAmount * claim.seriesCount;
              return [
                _cleanPdfText('${claim.prizeTier} #${claim.ticketNumber}'),
                'Ser ${claim.ticketSeries} (${claim.seriesCount} Sem)',
                'Rs. ${baseTotal.toStringAsFixed(0)}',
                'Rs. ${claim.superBonus.toStringAsFixed(0)}',
                'Rs. ${claim.specialIncentive.toStringAsFixed(0)}',
                'Rs. ${claim.prizeAmount.toStringAsFixed(0)}',
              ];
            }).toList(),
          ),
        );
        if (wc < winChunks - 1) {
          contentWidgets.add(pw.SizedBox(height: 6));
        }
      }
      contentWidgets.add(pw.SizedBox(height: 12));
    }

    // GRAND TOTAL FOOTER BOX WITH PRIZE, BONUS & PROFIT/LOSS BREAKDOWN
    contentWidgets.add(
      pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey100,
          border: pw.Border.all(color: PdfColors.grey400),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Total Tickets: $grandTotalQty',
                  style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF581C87)),
                ),
                pw.SizedBox(height: 3),
                pw.Text('Inam: Rs. ${grandBasePrize.toStringAsFixed(0)}', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: PdfColors.amber900)),
                pw.Text('Bonus: Rs. ${grandSuperBonus.toStringAsFixed(0)}', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: PdfColors.purple900)),
                pw.Text('Incentive: Rs. ${grandSpecialIncentive.toStringAsFixed(0)}', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'Total Sale: Rs. ${grandTotalAmount.toStringAsFixed(2)}',
                  style: pw.TextStyle(fontSize: 11.5, fontWeight: pw.FontWeight.bold, color: PdfColors.green900),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'Total Inam: Rs. ${grandTotalWinningPayout.toStringAsFixed(0)}',
                  style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.red900),
                ),
                pw.SizedBox(height: 5),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: pw.BoxDecoration(
                    color: isProfit ? PdfColors.blue50 : PdfColors.red50,
                    border: pw.Border.all(
                      color: isProfit ? PdfColors.blue900 : PdfColors.red900,
                      width: 1.5,
                    ),
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Row(
                    mainAxisSize: pw.MainAxisSize.min,
                    children: [
                      pw.Text(
                        isProfit ? 'NET DUE: ' : 'NET DUE (PAYABLE): ',
                        style: pw.TextStyle(
                          fontSize: 10.5,
                          fontWeight: pw.FontWeight.bold,
                          color: isProfit ? PdfColors.blue900 : PdfColors.red900,
                        ),
                      ),
                      pw.Text(
                        isProfit
                            ? 'Rs. ${netProfitLoss.toStringAsFixed(2)}'
                            : '-Rs. ${netProfitLoss.abs().toStringAsFixed(2)}',
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                          color: isProfit ? PdfColors.blue900 : PdfColors.red900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    onProgress?.call(0.88, 'Calculating page layout & pagination...');
    await Future.delayed(const Duration(milliseconds: 35));

    pdf.addPage(
      pw.MultiPage(
        maxPages: 5000,
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(24, 8, 24, 8),
          theme: pw.ThemeData.withFont(
            base: regularFont,
            bold: boldFont,
          ),
          buildBackground: (pw.Context ctx) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Container(
              decoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFF3E8FF), // soothing royal purple pastel tint (removes white glare)
              ),
            ),
          ),
        ),
        header: (pw.Context context) => _buildPdfPageHeader(
          context,
          subtitle: customerName != null && customerName.isNotEmpty && customerName != 'All'
              ? 'Customer: $customerName'
              : rangeTitle,
        ),
        footer: (pw.Context context) => _buildPdfPageFooter(context),
        build: (pw.Context context) => contentWidgets,
      ),
    );

    onProgress?.call(0.92, 'Structuring document layout & tables...');
    await Future.delayed(const Duration(milliseconds: 35));

    onProgress?.call(0.96, 'Compressing PDF binary data...');
    await Future.delayed(const Duration(milliseconds: 35));

    final bytes = await pdf.save();
    onProgress?.call(1.0, 'PDF ready!');
    await Future.delayed(const Duration(milliseconds: 15));
    return bytes;
  }

  /// Dedicated permanent folder on C: Drive (e.g. C:\Lottery_Reports)
  String get reportsFolderPath {
    if (Platform.isWindows) {
      final cDir = Directory(r'C:\Lottery_Reports');
      if (cDir.existsSync()) {
        return cDir.path;
      }
      try {
        cDir.createSync(recursive: true);
        return cDir.path;
      } catch (_) {}
    }
    final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '.';
    final fallbackDir = Directory('$home/Documents/Lottery_Reports');
    if (!fallbackDir.existsSync()) {
      try {
        fallbackDir.createSync(recursive: true);
      } catch (_) {}
    }
    return fallbackDir.path;
  }

  /// Open C:\Lottery_Reports folder directly in Windows Explorer
  void openReportsFolder() {
    try {
      final path = reportsFolderPath;
      if (Platform.isWindows) {
        Process.run('explorer.exe', [path]);
      }
    } catch (e) {
      debugPrint('Error opening reports folder: $e');
    }
  }

  /// Save PDF file to C:\Lottery_Reports\ and return details
  Future<Map<String, dynamic>> savePdfToDisk({
    required DateTime date,
    required List<TicketSaleModel> sales,
    String rangeTitle = 'DAILY BOOKINGS & SALES SUMMARY REPORT',
    String? customerName,
    bool isSummaryOnly = false,
    void Function(double progress, String status)? onProgress,
  }) async {
    final pdfBytes = await generatePdfReport(
      date: date,
      sales: sales,
      rangeTitle: rangeTitle,
      customerName: customerName,
      isSummaryOnly: isSummaryOnly,
      onProgress: onProgress,
    );

    final dateStr = DateFormat('dd-MM-yyyy').format(date);
    final timeStr = DateFormat('hh-mm-ss_a').format(DateTime.now());

    final bool isSpecificCustomer = customerName != null &&
        customerName.trim().isNotEmpty &&
        customerName.trim() != 'All';

    final cleanName = isSpecificCustomer
        ? customerName.trim().replaceAll(RegExp(r'[^\w\s]+'), '').replaceAll(' ', '_')
        : 'All_Sales';

    final suffix = isSummaryOnly ? '_SUMMARY_ONLY' : '_DETAILED';
    final fileName = '${cleanName}_${dateStr}_$timeStr$suffix.pdf';

    String savedFilePath = '';
    try {
      onProgress?.call(0.98, 'Saving file to C:\\Lottery_Reports...');
      await Future.delayed(const Duration(milliseconds: 1));
      final dirPath = reportsFolderPath;
      final file = File('$dirPath\\$fileName');
      await file.writeAsBytes(pdfBytes);
      savedFilePath = file.path;
      debugPrint('✅ PDF Saved to: $savedFilePath');
    } catch (e) {
      debugPrint('⚠️ Error saving PDF to disk: $e');
    }

    return {
      'filePath': savedFilePath,
      'fileName': fileName,
      'bytes': pdfBytes,
      'customerName': isSpecificCustomer ? customerName : 'All Customers',
    };
  }

  /// Open PDF directly in default Windows PDF viewer (Adobe Acrobat, Edge, Chrome)
  Future<void> openPdfFile(String filePath) async {
    try {
      if (Platform.isWindows && filePath.isNotEmpty) {
        await Process.run('cmd', ['/c', 'start', '', filePath]);
      }
    } catch (e) {
      debugPrint('⚠️ Error opening PDF file: $e');
    }
  }

  /// Highlight and select PDF in Windows File Explorer
  Future<void> showInExplorer(String filePath) async {
    try {
      if (Platform.isWindows && filePath.isNotEmpty) {
        await Process.run('explorer.exe', ['/select,', filePath]);
      }
    } catch (e) {
      debugPrint('⚠️ Error showing file in explorer: $e');
    }
  }

  /// Launch WhatsApp with Seller Hisab and PDF info
  Future<void> shareOnWhatsApp({
    required String filePath,
    required String customerName,
    String? phone,
    required int totalTickets,
    required double totalSales,
    double? winningPayout,
  }) async {
    try {
      final pText = (winningPayout != null && winningPayout > 0)
          ? '\n🏆 *Total Inam/Winning:* Rs. ${winningPayout.toStringAsFixed(2)}\n⚖️ *Net Balance:* Rs. ${(totalSales - winningPayout).toStringAsFixed(2)}'
          : '';

      final msg = Uri.encodeComponent(
        '📊 *LOTTERY BOOKING & HISAB REPORT*\n'
        '👤 *Customer/Seller:* $customerName\n'
        '🎟️ *Total Tickets:* $totalTickets\n'
        '💰 *Total Sales Amount:* Rs. ${totalSales.toStringAsFixed(2)}'
        '$pText\n\n'
        '📁 *PDF Report Saved At:* $filePath\n'
        '✨ _Generated by PhantomManagement Operations Platform_'
      );

      final cleanPhone = phone?.replaceAll(RegExp(r'[^\d]'), '') ?? '';
      final waUrl = cleanPhone.isNotEmpty
          ? 'https://wa.me/91$cleanPhone?text=$msg'
          : 'https://api.whatsapp.com/send?text=$msg';

      if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', waUrl]);
      }
    } catch (e) {
      debugPrint('⚠️ Error launching WhatsApp share: $e');
    }
  }

  /// Open PDF Layout Preview / Print dialog
  Future<void> printPdfLayout(Uint8List pdfBytes, String fileName) async {
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfBytes,
      name: fileName,
    );
  }

  /// Print or open PDF document and automatically save a copy in C:\Lottery_Reports\
  Future<String?> exportAndPrintPdf({
    required DateTime date,
    required List<TicketSaleModel> sales,
    String rangeTitle = 'DAILY BOOKINGS & SALES SUMMARY REPORT',
    String? customerName,
    bool isSummaryOnly = false,
    void Function(double progress, String status)? onProgress,
  }) async {
    final res = await savePdfToDisk(
      date: date,
      sales: sales,
      rangeTitle: rangeTitle,
      customerName: customerName,
      isSummaryOnly: isSummaryOnly,
      onProgress: onProgress,
    );

    final pdfBytes = res['bytes'] as Uint8List;
    final fileName = res['fileName'] as String;
    final savedFilePath = res['filePath'] as String;

    await printPdfLayout(pdfBytes, fileName);

    return savedFilePath;
  }

  /// Compress consecutive tickets and identical bookings into compact ranges
  static List<CompressedTicketRow> compressTicketSales(List<TicketSaleModel> items) {
    if (items.isEmpty) return [];

    final List<CompressedTicketRow> compressed = [];

    // Precompute sort keys once in O(N) to eliminate int.tryParse and trim inside O(N log N) comparator
    final entries = items.map((item) {
      final seller = item.buyerName.isNotEmpty ? item.buyerName : item.agentName;
      final trimmedNum = item.ticketNumber.trim();
      final numVal = int.tryParse(trimmedNum) ?? -1;
      return _TicketSortEntry(
        item: item,
        seller: seller,
        series: item.ticketSeries,
        price: item.pricePerTicket,
        numVal: numVal,
        numStr: trimmedNum,
      );
    }).toList();

    entries.sort((a, b) {
      final cSeller = a.seller.compareTo(b.seller);
      if (cSeller != 0) return cSeller;

      final cSeries = a.series.compareTo(b.series);
      if (cSeries != 0) return cSeries;

      final cPrice = a.price.compareTo(b.price);
      if (cPrice != 0) return cPrice;

      if (a.numVal != -1 && b.numVal != -1) {
        return a.numVal.compareTo(b.numVal);
      }
      return a.numStr.compareTo(b.numStr);
    });

    String curSeller = '';
    String curSeries = '';
    double curPrice = 0.0;
    int startNum = -1;
    int lastNum = -1;
    String startNumStr = '';
    String lastNumStr = '';
    int curQty = 0;
    double curTotal = 0.0;

    void flush() {
      if (curQty == 0) return;

      String rangeStr;
      if (startNum != -1 && lastNum != -1 && startNum != lastNum) {
        if (startNumStr.length == 5 && lastNumStr.length == 5 && startNumStr.substring(0, 3) == lastNumStr.substring(0, 3)) {
          rangeStr = '$startNumStr-${lastNumStr.substring(3)}';
        } else {
          rangeStr = '$startNumStr-$lastNumStr';
        }
      } else {
        rangeStr = startNumStr;
      }

      compressed.add(CompressedTicketRow(
        series: curSeries,
        ticketRangeDisplay: rangeStr,
        quantity: curQty,
        pricePerTicket: curPrice,
        totalAmount: curTotal,
        seller: curSeller,
      ));

      curQty = 0;
      curTotal = 0.0;
      startNum = -1;
      lastNum = -1;
      startNumStr = '';
      lastNumStr = '';
    }

    for (final entry in entries) {
      final item = entry.item;
      final seller = entry.seller;
      final series = entry.series;
      final price = entry.price;
      final numVal = entry.numVal;

      if (curQty == 0) {
        curSeller = seller;
        curSeries = series;
        curPrice = price;
        startNum = numVal;
        lastNum = numVal;
        startNumStr = entry.numStr;
        lastNumStr = entry.numStr;
        curQty = item.quantity;
        curTotal = item.totalAmount;
      } else {
        final isSameGroup = seller == curSeller &&
            series == curSeries &&
            (price - curPrice).abs() < 0.001;

        final isConsecutive = isSameGroup &&
            numVal != -1 &&
            lastNum != -1 &&
            (numVal == lastNum + 1);

        final isSameTicket = isSameGroup &&
            numVal != -1 &&
            lastNum != -1 &&
            (numVal == lastNum);

        if (isConsecutive) {
          lastNum = numVal;
          lastNumStr = entry.numStr;
          curQty += item.quantity;
          curTotal += item.totalAmount;
        } else if (isSameTicket) {
          curQty += item.quantity;
          curTotal += item.totalAmount;
        } else {
          flush();
          curSeller = seller;
          curSeries = series;
          curPrice = price;
          startNum = numVal;
          lastNum = numVal;
          startNumStr = entry.numStr;
          lastNumStr = entry.numStr;
          curQty = item.quantity;
          curTotal = item.totalAmount;
        }
      }
    }

    flush();
    return compressed;
  }
}

class CompressedTicketRow {
  final String series;
  final String ticketRangeDisplay;
  final int quantity;
  final double pricePerTicket;
  final double totalAmount;
  final String seller;

  CompressedTicketRow({
    required this.series,
    required this.ticketRangeDisplay,
    required this.quantity,
    required this.pricePerTicket,
    required this.totalAmount,
    required this.seller,
  });
}

class _SeriesSummaryData {
  final String series;
  int quantity;
  double unitPrice;
  double totalAmount;

  _SeriesSummaryData({
    required this.series,
    required this.quantity,
    required this.unitPrice,
    required this.totalAmount,
  });

  int get seriesNumber {
    final digits = series.replaceAll(RegExp(r'\D'), '');
    return int.tryParse(digits) ?? (series.toLowerCase().contains('100') ? 100 : 12);
  }

  int get totalSeriesUnits => quantity * seriesNumber;
}

class _DateSummaryData {
  final String dateKey;
  final String displayDate;
  final DateTime rawDate;
  int totalTickets = 0;
  double totalAmount = 0.0;
  int qty1PM = 0;
  double amt1PM = 0.0;
  int qty6PM = 0;
  double amt6PM = 0.0;
  int qty8PM = 0;
  double amt8PM = 0.0;
  double totalInamPayout = 0.0;
  final Map<String, int> seriesQtyMap = {};
  final Map<String, double> seriesAmtMap = {};
  final Map<String, double> seriesRateMap = {};

  _DateSummaryData({
    required this.dateKey,
    required this.displayDate,
    required this.rawDate,
  });
}

class _TicketSortEntry {
  final TicketSaleModel item;
  final String seller;
  final String series;
  final double price;
  final int numVal;
  final String numStr;

  _TicketSortEntry({
    required this.item,
    required this.seller,
    required this.series,
    required this.price,
    required this.numVal,
    required this.numStr,
  });
}
