import 'package:flutter/foundation.dart';
import '../../../core/database/database_service.dart';
import '../models/lottery_sambad_result_model.dart';
import '../models/winning_claim_model.dart';
import '../models/prize_config_model.dart';
import '../../shared/models/ticket_sale_model.dart';
import '../../unsold/models/unsold_model.dart';

class WinnerVerificationEngine {
  static bool _matchesShift(String ticketShift, String resultShift) {
    if (resultShift.isEmpty || resultShift == 'All' || resultShift == 'All Shifts') return true;
    final t = ticketShift.toLowerCase();
    final r = resultShift.toLowerCase();

    if (r.contains('1 pm') || r.contains('1pm') || r.contains('morning') || r.contains('1:00')) {
      return t.contains('1 pm') || t.contains('1pm') || t.contains('morning') || t.contains('1:00') || t == '1';
    }
    if (r.contains('6 pm') || r.contains('6pm') || r.contains('day') || r.contains('6:00')) {
      return t.contains('6 pm') || t.contains('6pm') || t.contains('day') || t.contains('6:00') || t == '6';
    }
    if (r.contains('8 pm') || r.contains('8pm') || r.contains('evening') || r.contains('night') || r.contains('8:00')) {
      return t.contains('8 pm') || t.contains('8pm') || t.contains('evening') || t.contains('night') || t.contains('8:00') || t == '8';
    }
    return t.contains(r) || r.contains(t);
  }

  static String _formatToDdMmYyyy(dynamic raw) {
    if (raw == null) return '';
    if (raw is DateTime) {
      return '${raw.day.toString().padLeft(2, '0')}/${raw.month.toString().padLeft(2, '0')}/${raw.year}';
    }
    final clean = raw.toString().trim();
    if (clean.isEmpty) return '';

    try {
      final iso = DateTime.tryParse(clean);
      if (iso != null) {
        return '${iso.day.toString().padLeft(2, '0')}/${iso.month.toString().padLeft(2, '0')}/${iso.year}';
      }

      final dateOnly = clean.split('T')[0].split(' ')[0];
      final parts = dateOnly.split(RegExp(r'[/.-]'));
      if (parts.length == 3) {
        final p0 = int.tryParse(parts[0]);
        final p1 = int.tryParse(parts[1]);
        var p2 = int.tryParse(parts[2]);
        if (p0 != null && p1 != null && p2 != null) {
          if (parts[0].length == 4) {
            // YYYY-MM-DD
            return '${p2.toString().padLeft(2, '0')}/${p1.toString().padLeft(2, '0')}/$p0';
          } else {
            // DD/MM/YYYY
            if (p2 < 100) p2 = 2000 + p2;
            return '${p0.toString().padLeft(2, '0')}/${p1.toString().padLeft(2, '0')}/$p2';
          }
        }
      }
    } catch (_) {}
    return clean;
  }

  /// High-performance asynchronous isolate verification.
  /// Automatically offloads to a background worker isolate when tickets >= 200,
  /// keeping the Flutter UI thread completely free from frame drops.
  static Future<List<WinningClaimModel>> verifyWinnersAsync({
    required LotterySambadResultModel result,
    required List<TicketSaleModel> soldTickets,
    Map<int, PrizeTierConfigModel>? prizeConfig,
  }) async {
    if (soldTickets.length < 200) {
      return verifyWinners(
        result: result,
        soldTickets: soldTickets,
        prizeConfig: prizeConfig,
      );
    }
    return compute(
      _verifyWinnersIsolateEntry,
      _VerifyWinnersArgs(result, soldTickets, prizeConfig),
    );
  }

  /// Verifies winners for a lottery result by streaming eligible tickets from SQLite
  /// in bounded batches (default 10,000), ensuring full draw verification without
  /// being limited to UI pagination or blowing up memory.
  static Future<List<WinningClaimModel>> verifyDrawFromDatabase({
    required LotterySambadResultModel result,
    Map<int, PrizeTierConfigModel>? prizeConfig,
    int batchSize = 10000,
  }) async {
    final List<WinningClaimModel> allClaims = [];
    await for (final batch in DatabaseService.instance.streamDrawTicketSalesInBatches(
      drawDateStr: result.drawDateStr,
      drawName: result.drawName,
      batchSize: batchSize,
    )) {
      final claims = await verifyWinnersAsync(
        result: result,
        soldTickets: batch,
        prizeConfig: prizeConfig,
      );
      allClaims.addAll(claims);
    }
    return allClaims;
  }

  /// Matches a published PDF Sambad result against a list of sold tickets using Prize Matrix
  static List<WinningClaimModel> verifyWinners({
    required LotterySambadResultModel result,
    required List<TicketSaleModel> soldTickets,
    Map<int, PrizeTierConfigModel>? prizeConfig,
  }) {
    final List<WinningClaimModel> winners = [];
    final now = DateTime.now();
    final configMap = prizeConfig ?? PrizeTierConfigModel.defaultConfig;

    // Helper to format 5-digit number
    String format5Digits(String numStr) {
      final digits = numStr.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length >= 5) {
        return digits.substring(digits.length - 5);
      }
      return digits.padLeft(5, '0');
    }

    // Helper to format 4-digit number
    String format4Digits(String numStr) {
      final digits = numStr.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length >= 4) {
        return digits.substring(digits.length - 4);
      }
      return digits.padLeft(4, '0');
    }

    final firstPrize5Digits = format5Digits(result.firstPrize);
    final consolation5Digits = format5Digits(result.consolationPrize.isNotEmpty ? result.consolationPrize : result.firstPrize);
    final secondPrize5Digits =
        result.secondPrizeNumbers.map(format5Digits).toSet();
    final thirdPrize4Digits =
        result.thirdPrizeNumbers.map(format4Digits).toSet();
    final fourthPrize4Digits =
        result.fourthPrizeNumbers.map(format4Digits).toSet();
    final fifthPrize4Digits =
        result.fifthPrizeNumbers.map(format4Digits).toSet();

    final resultDateFormatted = _formatToDdMmYyyy(result.drawDateStr);
    int? resDay, resMonth, resYear;
    if (resultDateFormatted.isNotEmpty) {
      final parts = resultDateFormatted.split('/');
      if (parts.length == 3) {
        resDay = int.tryParse(parts[0]);
        resMonth = int.tryParse(parts[1]);
        resYear = int.tryParse(parts[2]);
      }
    }

    final resShift = result.drawName.toLowerCase();
    final bool isAllShift = result.drawName.isEmpty || resShift == 'all' || resShift == 'all shifts';
    final bool resIs1 = resShift.contains('1 pm') || resShift.contains('1pm') || resShift.contains('morning') || resShift.contains('1:00');
    final bool resIs6 = resShift.contains('6 pm') || resShift.contains('6pm') || resShift.contains('day') || resShift.contains('6:00');
    final bool resIs8 = resShift.contains('8 pm') || resShift.contains('8pm') || resShift.contains('evening') || resShift.contains('night') || resShift.contains('8:00');

    for (final ticket in soldTickets) {
      // 🛡️ 1. ULTRA-FAST INTEGER DATE MATCHING (Checks both drawDate and saleDate)
      if (resDay != null && resMonth != null && resYear != null) {
        final dMatch = (ticket.drawDate.day == resDay &&
            ticket.drawDate.month == resMonth &&
            ticket.drawDate.year == resYear);
        final sMatch = (ticket.saleDate.day == resDay &&
            ticket.saleDate.month == resMonth &&
            ticket.saleDate.year == resYear);
        if (!dMatch && !sMatch) {
          continue; // Target Date mismatch! Skip this ticket.
        }
      }

      // 🛡️ 2. STRICT SHIFT / DRAW TIME MATCHING
      if (!isAllShift) {
        final t = '${ticket.drawName} ${ticket.drawCode}'.toLowerCase();
        if (resIs1) {
          if (!t.contains('1 pm') && !t.contains('1pm') && !t.contains('morning') && !t.contains('1:00') && t != '1') {
            continue;
          }
        } else if (resIs6) {
          if (!t.contains('6 pm') && !t.contains('6pm') && !t.contains('day') && !t.contains('6:00') && t != '6') {
            continue;
          }
        } else if (resIs8) {
          if (!t.contains('8 pm') && !t.contains('8pm') && !t.contains('evening') && !t.contains('night') && !t.contains('8:00') && t != '8') {
            continue;
          }
        } else {
          if (!t.contains(resShift) && !resShift.contains(t)) {
            continue;
          }
        }
      }

      final tNo5Digits = format5Digits(ticket.ticketNumber);
      final tNo4Digits = format4Digits(ticket.ticketNumber);

      // Extract series count multiplier directly from each ticket's own series value (e.g. Series "150" -> 150, Series "50" -> 50, Series "12" -> 12)
      int seriesCount = 1;
      final parsedSeriesNum = int.tryParse(ticket.ticketSeries.replaceAll(RegExp(r'\D'), ''));
      if (parsedSeriesNum != null && parsedSeriesNum > 0) {
        seriesCount = parsedSeriesNum;
      } else if (ticket.quantity > 0) {
        seriesCount = ticket.quantity;
      }

      // 1. Check 1st Prize / Consolation Prize (Match 5 Digits directly)
      if (result.firstPrize.trim().isNotEmpty &&
          (tNo5Digits == firstPrize5Digits || (consolation5Digits.isNotEmpty && tNo5Digits == consolation5Digits))) {
        final cfg = configMap[1] ?? PrizeTierConfigModel.defaultConfig[1]!;
        final payout = cfg.calculatePayout(seriesCount);
        winners.add(
          WinningClaimModel(
            id: 'win_${result.drawId}_${ticket.id}',
            drawId: result.drawId,
            drawName: result.drawName,
            drawDate: result.drawDateStr,
            drawTime: result.drawTimeStr,
            prizeTier: '🥇 1st Prize',
            winningNumber: '${result.firstPrize} (#$tNo5Digits)',
            prizeAmount: payout,
            seriesCount: seriesCount,
            baseAmount: cfg.baseAmount,
            superBonus: cfg.superBonus * seriesCount,
            specialIncentive: cfg.specialIncentive * seriesCount,
            buyerName: ticket.buyerName.isNotEmpty ? ticket.buyerName : 'Walk-in Customer',
            sellerName: ticket.agentName.isNotEmpty ? ticket.agentName : 'Rajiv',
            ticketSeries: ticket.ticketSeries,
            ticketNumber: ticket.ticketNumber,
            verifiedAt: now,
          ),
        );
        continue;
      }

      // 2. Check 2nd Prize
      if (secondPrize5Digits.contains(tNo5Digits)) {
        final cfg = configMap[2] ?? PrizeTierConfigModel.defaultConfig[2]!;
        final payout = cfg.calculatePayout(seriesCount);
        winners.add(
          WinningClaimModel(
            id: 'win_${result.drawId}_${ticket.id}',
            drawId: result.drawId,
            drawName: result.drawName,
            drawDate: result.drawDateStr,
            drawTime: result.drawTimeStr,
            prizeTier: '🥈 2nd Prize',
            winningNumber: tNo5Digits,
            prizeAmount: payout,
            seriesCount: seriesCount,
            baseAmount: cfg.baseAmount,
            superBonus: cfg.superBonus * seriesCount,
            specialIncentive: cfg.specialIncentive * seriesCount,
            buyerName: ticket.buyerName.isNotEmpty ? ticket.buyerName : 'Walk-in Customer',
            sellerName: ticket.agentName.isNotEmpty ? ticket.agentName : 'Rajiv',
            ticketSeries: ticket.ticketSeries,
            ticketNumber: ticket.ticketNumber,
            verifiedAt: now,
          ),
        );
        continue;
      }

      // 3. Check 3rd Prize
      if (thirdPrize4Digits.contains(tNo4Digits)) {
        final cfg = configMap[3] ?? PrizeTierConfigModel.defaultConfig[3]!;
        final payout = cfg.calculatePayout(seriesCount);
        winners.add(
          WinningClaimModel(
            id: 'win_${result.drawId}_${ticket.id}',
            drawId: result.drawId,
            drawName: result.drawName,
            drawDate: result.drawDateStr,
            drawTime: result.drawTimeStr,
            prizeTier: '🥉 3rd Prize',
            winningNumber: tNo4Digits,
            prizeAmount: payout,
            seriesCount: seriesCount,
            baseAmount: cfg.baseAmount,
            superBonus: cfg.superBonus * seriesCount,
            specialIncentive: cfg.specialIncentive * seriesCount,
            buyerName: ticket.buyerName.isNotEmpty ? ticket.buyerName : 'Walk-in Customer',
            sellerName: ticket.agentName.isNotEmpty ? ticket.agentName : 'Rajiv',
            ticketSeries: ticket.ticketSeries,
            ticketNumber: ticket.ticketNumber,
            verifiedAt: now,
          ),
        );
        continue;
      }

      // 4. Check 4th Prize
      if (fourthPrize4Digits.contains(tNo4Digits)) {
        final cfg = configMap[4] ?? PrizeTierConfigModel.defaultConfig[4]!;
        final payout = cfg.calculatePayout(seriesCount);
        winners.add(
          WinningClaimModel(
            id: 'win_${result.drawId}_${ticket.id}',
            drawId: result.drawId,
            drawName: result.drawName,
            drawDate: result.drawDateStr,
            drawTime: result.drawTimeStr,
            prizeTier: '🏅 4th Prize',
            winningNumber: tNo4Digits,
            prizeAmount: payout,
            seriesCount: seriesCount,
            baseAmount: cfg.baseAmount,
            superBonus: cfg.superBonus * seriesCount,
            specialIncentive: cfg.specialIncentive * seriesCount,
            buyerName: ticket.buyerName.isNotEmpty ? ticket.buyerName : 'Walk-in Customer',
            sellerName: ticket.agentName.isNotEmpty ? ticket.agentName : 'Rajiv',
            ticketSeries: ticket.ticketSeries,
            ticketNumber: ticket.ticketNumber,
            verifiedAt: now,
          ),
        );
        continue;
      }

      // 5. Check 5th Prize
      if (fifthPrize4Digits.contains(tNo4Digits)) {
        final cfg = configMap[5] ?? PrizeTierConfigModel.defaultConfig[5]!;
        final payout = cfg.calculatePayout(seriesCount);
        winners.add(
          WinningClaimModel(
            id: 'win_${result.drawId}_${ticket.id}',
            drawId: result.drawId,
            drawName: result.drawName,
            drawDate: result.drawDateStr,
            drawTime: result.drawTimeStr,
            prizeTier: '🏅 5th Prize',
            winningNumber: tNo4Digits,
            prizeAmount: payout,
            seriesCount: seriesCount,
            baseAmount: cfg.baseAmount,
            superBonus: cfg.superBonus * seriesCount,
            specialIncentive: cfg.specialIncentive * seriesCount,
            buyerName: ticket.buyerName.isNotEmpty ? ticket.buyerName : 'Walk-in Customer',
            sellerName: ticket.agentName.isNotEmpty ? ticket.agentName : 'Rajiv',
            ticketSeries: ticket.ticketSeries,
            ticketNumber: ticket.ticketNumber,
            verifiedAt: now,
          ),
        );
      }
    }

    return winners;
  }

  /// Matches published result against Unsold Returned Tickets (Shop / Self Claims)
  static List<WinningClaimModel> verifyUnsoldWinners({
    required LotterySambadResultModel result,
    required List<UnsoldModel> unsoldList,
    Map<int, PrizeTierConfigModel>? prizeConfig,
  }) {
    final List<WinningClaimModel> winners = [];
    final now = DateTime.now();
    final configMap = prizeConfig ?? PrizeTierConfigModel.defaultConfig;

    String format5Digits(String numStr) {
      final digits = numStr.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length >= 5) {
        return digits.substring(digits.length - 5);
      }
      return digits.padLeft(5, '0');
    }

    String format4Digits(String numStr) {
      final digits = numStr.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length >= 4) {
        return digits.substring(digits.length - 4);
      }
      return digits.padLeft(4, '0');
    }

    final firstPrize5Digits = format5Digits(result.firstPrize);
    final consolation5Digits = format5Digits(result.consolationPrize.isNotEmpty ? result.consolationPrize : result.firstPrize);
    final secondPrize5Digits = result.secondPrizeNumbers.map(format5Digits).toSet();
    final thirdPrize4Digits = result.thirdPrizeNumbers.map(format4Digits).toSet();
    final fourthPrize4Digits = result.fourthPrizeNumbers.map(format4Digits).toSet();
    final fifthPrize4Digits = result.fifthPrizeNumbers.map(format4Digits).toSet();

    for (final unsold in unsoldList) {
      if (result.drawDateStr.isNotEmpty) {
        final resultDateFormatted = _formatToDdMmYyyy(result.drawDateStr);
        final unsoldDateFormatted = _formatToDdMmYyyy(unsold.date);
        if (resultDateFormatted.isNotEmpty && unsoldDateFormatted.isNotEmpty && resultDateFormatted != unsoldDateFormatted) {
          continue;
        }
      }

      if (result.drawName.isNotEmpty && !_matchesShift(unsold.drawShift, result.drawName)) {
        continue;
      }

      final fNum = int.tryParse(unsold.fromTicket.replaceAll(RegExp(r'\D'), '')) ?? 0;
      final tNum = int.tryParse(unsold.toTicket.replaceAll(RegExp(r'\D'), '')) ?? fNum;
      final series = unsold.series.isNotEmpty ? unsold.series : '12';
      final seriesCount = int.tryParse(series.replaceAll(RegExp(r'\D'), '')) ?? 1;

      for (int n = fNum; n <= tNum; n++) {
        final tkt5 = n.toString().padLeft(5, '0');
        final tkt4 = tkt5.length >= 4 ? tkt5.substring(tkt5.length - 4) : tkt5;

        // 1. 1st Prize / Consolation Prize (Match 5 Digits directly)
        if (result.firstPrize.trim().isNotEmpty &&
            (tkt5 == firstPrize5Digits || (consolation5Digits.isNotEmpty && tkt5 == consolation5Digits))) {
          final isFirst = tkt5 == firstPrize5Digits;
          final cfg = configMap[1] ?? PrizeTierConfigModel.defaultConfig[1]!;
          winners.add(WinningClaimModel(
            id: 'unsold_win_${result.drawId}_${unsold.id}_$tkt5',
            drawId: result.drawId,
            drawName: result.drawName,
            drawDate: result.drawDateStr,
            drawTime: result.drawTimeStr,
            prizeTier: isFirst ? '🏆 1st Prize (Unsold)' : '🏅 Consolation (Unsold)',
            winningNumber: tkt5,
            prizeAmount: cfg.calculatePayout(seriesCount),
            seriesCount: seriesCount,
            buyerName: 'Self (Unsold Return)',
            sellerName: unsold.partyName,
            ticketSeries: series,
            ticketNumber: tkt5,
            verifiedAt: now,
          ));
        }

        // 2. 2nd Prize (Match 5 Digits)
        if (secondPrize5Digits.contains(tkt5)) {
          final cfg = configMap[2] ?? PrizeTierConfigModel.defaultConfig[2]!;
          winners.add(WinningClaimModel(
            id: 'unsold_win_${result.drawId}_${unsold.id}_$tkt5',
            drawId: result.drawId,
            drawName: result.drawName,
            drawDate: result.drawDateStr,
            drawTime: result.drawTimeStr,
            prizeTier: '🥈 2nd Prize (Unsold)',
            winningNumber: tkt5,
            prizeAmount: cfg.calculatePayout(seriesCount),
            seriesCount: seriesCount,
            buyerName: 'Self (Unsold Return)',
            sellerName: unsold.partyName,
            ticketSeries: series,
            ticketNumber: tkt5,
            verifiedAt: now,
          ));
        }

        // 3. 3rd Prize (Last 4 Digits Match)
        if (thirdPrize4Digits.contains(tkt4)) {
          final cfg = configMap[3] ?? PrizeTierConfigModel.defaultConfig[3]!;
          winners.add(WinningClaimModel(
            id: 'unsold_win_${result.drawId}_${unsold.id}_$tkt5',
            drawId: result.drawId,
            drawName: result.drawName,
            drawDate: result.drawDateStr,
            drawTime: result.drawTimeStr,
            prizeTier: '🥉 3rd Prize (Unsold)',
            winningNumber: tkt4,
            prizeAmount: cfg.calculatePayout(seriesCount),
            seriesCount: seriesCount,
            buyerName: 'Self (Unsold Return)',
            sellerName: unsold.partyName,
            ticketSeries: series,
            ticketNumber: tkt5,
            verifiedAt: now,
          ));
        }

        // 4. 4th Prize (Last 4 Digits Match)
        if (fourthPrize4Digits.contains(tkt4)) {
          final cfg = configMap[4] ?? PrizeTierConfigModel.defaultConfig[4]!;
          winners.add(WinningClaimModel(
            id: 'unsold_win_${result.drawId}_${unsold.id}_$tkt5',
            drawId: result.drawId,
            drawName: result.drawName,
            drawDate: result.drawDateStr,
            drawTime: result.drawTimeStr,
            prizeTier: '🏅 4th Prize (Unsold)',
            winningNumber: tkt4,
            prizeAmount: cfg.calculatePayout(seriesCount),
            seriesCount: seriesCount,
            buyerName: 'Self (Unsold Return)',
            sellerName: unsold.partyName,
            ticketSeries: series,
            ticketNumber: tkt5,
            verifiedAt: now,
          ));
        }

        // 5. 5th Prize (Last 4 Digits Match)
        if (fifthPrize4Digits.contains(tkt4)) {
          final cfg = configMap[5] ?? PrizeTierConfigModel.defaultConfig[5]!;
          winners.add(WinningClaimModel(
            id: 'unsold_win_${result.drawId}_${unsold.id}_$tkt5',
            drawId: result.drawId,
            drawName: result.drawName,
            drawDate: result.drawDateStr,
            drawTime: result.drawTimeStr,
            prizeTier: '🏅 5th Prize (Unsold)',
            winningNumber: tkt4,
            prizeAmount: cfg.calculatePayout(seriesCount),
            seriesCount: seriesCount,
            buyerName: 'Self (Unsold Return)',
            sellerName: unsold.partyName,
            ticketSeries: series,
            ticketNumber: tkt5,
            verifiedAt: now,
          ));
        }
      }
    }

    return winners;
  }

  /// Fetches all stored lottery results and verifies if any of the provided sales are winners.
  static Future<List<WinningClaimModel>> checkSalesForWinners(
    List<TicketSaleModel> sales, {
    List<LotterySambadResultModel>? knownResults,
    Map<int, PrizeTierConfigModel>? prizeConfig,
  }) async {
    if (sales.isEmpty) return [];
    try {
      final List<LotterySambadResultModel> results = [];
      if (knownResults != null && knownResults.isNotEmpty) {
        results.addAll(knownResults);
      }

      // Fetch persisted results from SQLite database
      final rows = await DatabaseService.instance.getLotteryResults();
      for (final r in rows) {
        final sec = (r['secondPrizeNumbers']?.toString() ?? '')
            .split(',')
            .where((e) => e.trim().isNotEmpty)
            .toList();
        final th = (r['thirdPrizeNumbers']?.toString() ?? '')
            .split(',')
            .where((e) => e.trim().isNotEmpty)
            .toList();
        final fo = (r['fourthPrizeNumbers']?.toString() ?? '')
            .split(',')
            .where((e) => e.trim().isNotEmpty)
            .toList();
        final fi = (r['fifthPrizeNumbers']?.toString() ?? '')
            .split(',')
            .where((e) => e.trim().isNotEmpty)
            .toList();

        final drawId = r['id']?.toString() ?? '';
        // Avoid duplicate results if already supplied in knownResults
        if (results.any((x) => x.drawId == drawId && drawId.isNotEmpty)) {
          continue;
        }

        results.add(LotterySambadResultModel(
          drawId: drawId,
          drawName: r['drawName']?.toString() ?? '',
          drawDateStr: r['drawDateStr']?.toString() ?? '',
          drawTimeStr: r['drawTimeStr']?.toString() ?? '',
          firstPrize: r['firstPrize']?.toString() ?? '',
          consolationPrize: '',
          secondPrizeNumbers: sec,
          thirdPrizeNumbers: th,
          fourthPrizeNumbers: fo,
          fifthPrizeNumbers: fi,
          publishedAt: DateTime.tryParse(r['publishedAt']?.toString() ?? '') ?? DateTime.now(),
        ));
      }

      if (results.isEmpty) return [];

      final List<WinningClaimModel> allWinners = [];
      for (final res in results) {
        final claims = verifyWinners(
          result: res,
          soldTickets: sales,
          prizeConfig: prizeConfig,
        );
        allWinners.addAll(claims);
      }
      return allWinners;
    } catch (e) {
      debugPrint('Error verifying winners in checkSalesForWinners: $e');
      return [];
    }
  }
}

class _VerifyWinnersArgs {
  final LotterySambadResultModel result;
  final List<TicketSaleModel> soldTickets;
  final Map<int, PrizeTierConfigModel>? prizeConfig;

  const _VerifyWinnersArgs(this.result, this.soldTickets, this.prizeConfig);
}

List<WinningClaimModel> _verifyWinnersIsolateEntry(_VerifyWinnersArgs args) {
  return WinnerVerificationEngine.verifyWinners(
    result: args.result,
    soldTickets: args.soldTickets,
    prizeConfig: args.prizeConfig,
  );
}

