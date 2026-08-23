import 'dart:io';
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
  }) async {
    final pdf = pw.Document();
    final dateFormat = DateFormat('dd-MM-yyyy (EEEE)');
    final timeFormat = DateFormat('hh:mm a');
    final dateStr = dateFormat.format(date);
    final generatedAt = timeFormat.format(DateTime.now());

    // Separate sales by shift
    final Map<String, List<TicketSaleModel>> shiftSales = {
      'Dear 1 PM': [],
      'Dear 6 PM': [],
      'Dear 8 PM': [],
    };

    for (var sale in sales) {
      final shift = getDrawShift(sale.drawName);
      shiftSales[shift]?.add(sale);
    }

    // Calculate verified winners & itemized prize/bonus/incentive metrics
    final List<WinningClaimModel> winningClaims = [];
    try {
      final rawResults = await DatabaseService.instance.getLotteryResults();
      for (final raw in rawResults) {
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

    // Series Summary calculation
    final Map<String, _SeriesSummaryData> seriesSummaryMap = {};
    for (var sale in sales) {
      final s = sale.ticketSeries.toUpperCase();
      if (!seriesSummaryMap.containsKey(s)) {
        seriesSummaryMap[s] = _SeriesSummaryData(
          series: s,
          quantity: 0,
          unitPrice: sale.pricePerTicket,
          totalAmount: 0.0,
        );
      }
      seriesSummaryMap[s]!.quantity += sale.quantity;
      seriesSummaryMap[s]!.totalAmount += sale.totalAmount;
    }

    final sortedSeriesKeys = seriesSummaryMap.keys.toList()..sort();

    // Date-wise calculation for 7-day / multi-day summaries
    final Map<String, _DateSummaryData> dateSummaryMap = {};
    for (var sale in sales) {
      final sDate = sale.drawDate.toLocal();
      final dateKey = DateFormat('yyyy-MM-dd').format(sDate);
      final displayDate = DateFormat('dd/MM/yyyy (EEE)').format(sDate);
      final shift = getDrawShift(sale.drawName);

      if (!dateSummaryMap.containsKey(dateKey)) {
        dateSummaryMap[dateKey] = _DateSummaryData(
          dateKey: dateKey,
          displayDate: displayDate,
          rawDate: sDate,
        );
      }

      final dateSummary = dateSummaryMap[dateKey]!;
      dateSummary.totalTickets += sale.quantity;
      dateSummary.totalAmount += sale.totalAmount;

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

    // Match Inam payout per date
    for (final claim in winningClaims) {
      final matchedTicket = sales.firstWhere(
        (s) => s.ticketSeries.toUpperCase() == claim.ticketSeries.toUpperCase() &&
               s.ticketNumber.contains(claim.ticketNumber),
        orElse: () => sales.first,
      );
      final dateKey = DateFormat('yyyy-MM-dd').format(matchedTicket.drawDate.toLocal());
      if (dateSummaryMap.containsKey(dateKey)) {
        dateSummaryMap[dateKey]!.totalInamPayout += claim.prizeAmount;
      }
    }

    final sortedDateKeys = dateSummaryMap.keys.toList()..sort();

    int grandTotalQty = 0;
    double grandTotalAmount = 0.0;
    for (var sale in sales) {
      grandTotalQty += sale.quantity;
      grandTotalAmount += sale.totalAmount;
    }

    final netProfitLoss = grandTotalAmount - grandTotalWinningPayout;
    final isProfit = netProfitLoss >= 0;

    // Fetch Roboto Unicode fonts for clean text rendering
    final regularFont = await PdfGoogleFonts.robotoRegular();
    final boldFont = await PdfGoogleFonts.robotoBold();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        maxPages: 200,
        theme: pw.ThemeData.withFont(
          base: regularFont,
          bold: boldFont,
        ),
        header: (pw.Context context) {
          if (context.pageNumber == 1) return pw.Container();
          return pw.Container(
            alignment: pw.Alignment.centerRight,
            margin: const pw.EdgeInsets.only(bottom: 8),
            child: pw.Text(
              '${customerName != null ? "$customerName | " : ""}$rangeTitle - Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
          );
        },
        build: (pw.Context context) {
          return [
            // TOP HEADER TITLE BANNER
            pw.Container(
              alignment: pw.Alignment.center,
              padding: const pw.EdgeInsets.only(bottom: 12),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: PdfColors.indigo900, width: 2),
                ),
              ),
              child: pw.Column(
                children: [
                  pw.Text(
                    'PHANTOM MANAGEMENT',
                    style: pw.TextStyle(
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.indigo900,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    rangeTitle.toUpperCase(),
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.grey800,
                    ),
                  ),
                  if (customerName != null && customerName.isNotEmpty && customerName != 'All') ...[
                    pw.SizedBox(height: 4),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.indigo100,
                        borderRadius: pw.BorderRadius.circular(4),
                        border: pw.Border.all(color: PdfColors.indigo600, width: 0.8),
                      ),
                      child: pw.Text(
                        'CUSTOMER / SELLER: ${customerName.toUpperCase()}',
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.indigo900,
                        ),
                      ),
                    ),
                  ],
                  pw.SizedBox(height: 6),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'DATE: $dateStr',
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        'Generated At: $generatedAt',
                        style: const pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.grey700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),

            // 📅 7-DAYS DATE-WISE CONSOLIDATED SUMMARY & PERFORMANCE BREAKDOWN (Rendered for weekly / multi-day reports)
            if (sortedDateKeys.length > 1 || rangeTitle.toUpperCase().contains('7 DAYS') || rangeTitle.toUpperCase().contains('WEEKLY')) ...[
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                color: PdfColors.blue50,
                child: pw.Text(
                  'PAST 7-DAYS DATE-WISE SALES & INAM SUMMARY BREAKDOWN',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blue900,
                  ),
                ),
              ),
              pw.SizedBox(height: 6),
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
                  horizontal: 4,
                  vertical: 4,
                ),
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
                  'Inam Paid (Rs)',
                  'Net Margin (Rs)',
                ],
                data: [
                  ...sortedDateKeys.map((key) {
                    final d = dateSummaryMap[key]!;
                    final netDay = d.totalAmount - (d.totalAmount * 0.05) - d.totalInamPayout;
                    return [
                      d.displayDate,
                      'Rs. ${d.amt1PM.toStringAsFixed(0)}',
                      'Rs. ${d.amt6PM.toStringAsFixed(0)}',
                      'Rs. ${d.amt8PM.toStringAsFixed(0)}',
                      '${d.totalTickets}',
                      'Rs. ${d.totalAmount.toStringAsFixed(2)}',
                      'Rs. ${d.totalInamPayout.toStringAsFixed(0)}',
                      'Rs. ${netDay.toStringAsFixed(2)}',
                    ];
                  }),
                ],
              ),
              pw.SizedBox(height: 14),
            ],

            // If Summary-Only: Render consolidated Shift summary table instead of line-by-line ticket items
            if (isSummaryOnly) ...[
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                color: PdfColors.indigo50,
                child: pw.Text(
                  'DRAW SHIFT SALES CONSOLIDATION (SUMMARY ONLY)',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.indigo900,
                  ),
                ),
              ),
              pw.SizedBox(height: 6),
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
                  color: PdfColors.indigo800,
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
              pw.SizedBox(height: 14),
            ] else ...[
              // Loop through each Shift directly in MultiPage list (allows clean page breaking)
              for (final shiftName in ['Dear 1 PM', 'Dear 6 PM', 'Dear 8 PM']) ...[
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  color: PdfColors.indigo50,
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'DRAW SHIFT: $shiftName',
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.indigo900,
                        ),
                      ),
                      pw.Text(
                        'Tickets: ${(shiftSales[shiftName] ?? []).fold(0, (sum, i) => sum + i.quantity)}  |  Total: Rs. ${(shiftSales[shiftName] ?? []).fold(0.0, (sum, i) => sum + i.totalAmount).toStringAsFixed(2)}',
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.indigo900,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 6),
                if ((shiftSales[shiftName] ?? []).isEmpty)
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
                  )
                else
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
                      color: PdfColors.indigo800,
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
                      'Ticket No.',
                      'Qty',
                      'Rate (Rs)',
                      'Total (Rs)',
                      'Seller/Buyer',
                    ],
                    data: List.generate((shiftSales[shiftName] ?? []).length, (index) {
                      final item = (shiftSales[shiftName] ?? [])[index];
                      final rawSeller = item.buyerName.isNotEmpty
                          ? item.buyerName
                          : item.agentName;
                      return [
                        '${index + 1}',
                        item.ticketSeries,
                        item.ticketNumber,
                        '${item.quantity}',
                        'Rs. ${item.pricePerTicket.toStringAsFixed(2)}',
                        'Rs. ${item.totalAmount.toStringAsFixed(2)}',
                        _cleanPdfText(rawSeller),
                      ];
                    }),
                  ),
                pw.SizedBox(height: 14),
              ],
            ],

            pw.Divider(color: PdfColors.indigo900, thickness: 1.5),
            pw.SizedBox(height: 10),

            // GRAND SERIES SUMMARY TABLE
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
            pw.SizedBox(height: 6),
            if (sortedSeriesKeys.isEmpty)
              pw.Text(
                'No bookings found for selected date.',
                style: const pw.TextStyle(fontSize: 10),
              )
            else
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
                  color: PdfColors.teal800,
                ),
                cellStyle: const pw.TextStyle(fontSize: 9),
                cellPadding: const pw.EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 4,
                ),
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.center,
                  2: pw.Alignment.centerRight,
                  3: pw.Alignment.centerRight,
                },
                headers: [
                  'Series Name',
                  'Total Tickets Sold',
                  'Unit Price / Rate (Rs)',
                  'Total Amount (Rs)',
                ],
                data: [
                  ...sortedSeriesKeys.map((key) {
                    final data = seriesSummaryMap[key]!;
                    return [
                      'Series ${data.series}',
                      '${data.quantity}',
                      'Rs. ${data.unitPrice.toStringAsFixed(2)}',
                      'Rs. ${data.totalAmount.toStringAsFixed(2)}',
                    ];
                  }),
                ],
              ),

            pw.SizedBox(height: 12),

            // ITEMISED WINNING PRIZE, BONUS & INCENTIVE BREAKDOWN TABLE
            if (winningClaims.isNotEmpty) ...[
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
              pw.SizedBox(height: 6),
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
                  'Series',
                  'Inam (Rs)',
                  'Bonus (Rs)',
                  'Incentive (Rs)',
                  'Total Inam (Rs)',
                ],
                data: winningClaims.map((claim) {
                  final baseTotal = claim.baseAmount * claim.seriesCount;
                  return [
                    _cleanPdfText('${claim.prizeTier} #${claim.ticketSeries}-${claim.ticketNumber}'),
                    '${claim.seriesCount}',
                    'Rs. ${baseTotal.toStringAsFixed(0)}',
                    'Rs. ${claim.superBonus.toStringAsFixed(0)}',
                    'Rs. ${claim.specialIncentive.toStringAsFixed(0)}',
                    'Rs. ${claim.prizeAmount.toStringAsFixed(0)}',
                  ];
                }).toList(),
              ),
              pw.SizedBox(height: 12),
            ],

            // GRAND TOTAL FOOTER BOX WITH PRIZE, BONUS & PROFIT/LOSS BREAKDOWN
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
                        style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900),
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
          ];
        },
      ),
    );

    return pdf.save();
  }

  /// Dedicated permanent folder on C: Drive (e.g. C:\Lottery_Reports)
  String get reportsFolderPath {
    final cDir = Directory(r'C:\Lottery_Reports');
    if (!cDir.existsSync()) {
      try {
        cDir.createSync(recursive: true);
        return cDir.path;
      } catch (_) {
        final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '.';
        final fallbackDir = Directory('$home/Documents/Lottery_Reports');
        if (!fallbackDir.existsSync()) fallbackDir.createSync(recursive: true);
        return fallbackDir.path;
      }
    }
    return cDir.path;
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
  }) async {
    final pdfBytes = await generatePdfReport(
      date: date,
      sales: sales,
      rangeTitle: rangeTitle,
      customerName: customerName,
      isSummaryOnly: isSummaryOnly,
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
  }) async {
    final res = await savePdfToDisk(
      date: date,
      sales: sales,
      rangeTitle: rangeTitle,
      customerName: customerName,
      isSummaryOnly: isSummaryOnly,
    );

    final pdfBytes = res['bytes'] as Uint8List;
    final fileName = res['fileName'] as String;
    final savedFilePath = res['filePath'] as String;

    await printPdfLayout(pdfBytes, fileName);

    return savedFilePath;
  }
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

  _DateSummaryData({
    required this.dateKey,
    required this.displayDate,
    required this.rawDate,
  });
}
