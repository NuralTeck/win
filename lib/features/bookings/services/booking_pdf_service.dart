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

    int grandTotalQty = 0;
    double grandTotalAmount = 0.0;
    for (var sale in sales) {
      grandTotalQty += sale.quantity;
      grandTotalAmount += sale.totalAmount;
    }

    // Load Unicode-safe Roboto font
    pw.Font? regularFont;
    pw.Font? boldFont;
    try {
      regularFont = await PdfGoogleFonts.robotoRegular();
      boldFont = await PdfGoogleFonts.robotoBold();
    } catch (_) {
      // Fallback to standard fonts if offline
    }

    final themeData = regularFont != null && boldFont != null
        ? pw.ThemeData.withFont(base: regularFont, bold: boldFont)
        : null;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        maxPages: 200,
        margin: const pw.EdgeInsets.all(24),
        theme: themeData,
        build: (pw.Context context) {
          return [
            // Header Title
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
                    'NAGALAND TICKETCORE',
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
                  'VERIFIED WINNING INAM & BONUS / INCENTIVE BREAKDOWN',
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
                  'Prize Tier & Ticket',
                  'Series Count',
                  'Base Prize (Rs)',
                  'Super Bonus (Rs)',
                  'Special Incentive (Rs)',
                  'Total Winner Payout (Rs)',
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

            // GRAND TOTAL FOOTER BOX WITH PRIZE & BONUS BREAKDOWN
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Total Series Count: ${sortedSeriesKeys.length}',
                        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text('Total Bookings Recorded: ${sales.length}', style: const pw.TextStyle(fontSize: 10)),
                      pw.SizedBox(height: 4),
                      pw.Text('Base Inam Prize: Rs. ${grandBasePrize.toStringAsFixed(0)}', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: PdfColors.amber900)),
                      pw.Text('Super Bonus: Rs. ${grandSuperBonus.toStringAsFixed(0)}', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: PdfColors.purple900)),
                      pw.Text('Special Incentive: Rs. ${grandSpecialIncentive.toStringAsFixed(0)}', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'GRAND TOTAL TICKETS: $grandTotalQty',
                        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'TOTAL REVENUE: Rs. ${grandTotalAmount.toStringAsFixed(2)}',
                        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.green900),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'GRAND TOTAL INAM PAYOUT: Rs. ${grandTotalWinningPayout.toStringAsFixed(0)}',
                        style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.red900),
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

  /// Print or open PDF document
  Future<void> exportAndPrintPdf({
    required DateTime date,
    required List<TicketSaleModel> sales,
    String rangeTitle = 'DAILY BOOKINGS & SALES SUMMARY REPORT',
  }) async {
    final pdfBytes = await generatePdfReport(date: date, sales: sales, rangeTitle: rangeTitle);
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfBytes,
      name: 'NagaLand_Bookings_Report_$dateStr.pdf',
    );
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
