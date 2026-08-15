import 'package:intl/intl.dart';
import '../models/lottery_sambad_result_model.dart';
import '../models/winning_claim_model.dart';
import '../models/prize_config_model.dart';
import '../../shared/models/ticket_sale_model.dart';

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

  static String _formatToDdMmYyyy(String raw) {
    try {
      final clean = raw.trim();
      if (clean.length >= 10 && clean.contains('-')) {
        final parts = clean.split('T')[0].split('-');
        if (parts.length == 3) {
          if (parts[0].length == 4) {
            return '${parts[2].padLeft(2, '0')}/${parts[1].padLeft(2, '0')}/${parts[0]}';
          } else {
            return '${parts[0].padLeft(2, '0')}/${parts[1].padLeft(2, '0')}/${parts[2]}';
          }
        }
      }
      if (clean.contains('/')) {
        final parts = clean.split('/');
        if (parts.length == 3) {
          return '${parts[0].padLeft(2, '0')}/${parts[1].padLeft(2, '0')}/${parts[2].length == 2 ? '20${parts[2]}' : parts[2]}';
        }
      }
    } catch (_) {}
    return raw;
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

    for (final ticket in soldTickets) {
      // 🛡️ 1. STRICT DATE MATCHING
      if (result.drawDateStr.isNotEmpty) {
        final ticketDateStr = DateFormat('dd/MM/yyyy').format(ticket.drawDate);
        final resultDateFormatted = _formatToDdMmYyyy(result.drawDateStr);
        if (resultDateFormatted.isNotEmpty && ticketDateStr != resultDateFormatted) {
          continue; // Target Date mismatch! Skip this ticket.
        }
      }

      // 🛡️ 2. STRICT SHIFT / DRAW TIME MATCHING
      if (result.drawName.isNotEmpty) {
        if (!_matchesShift(ticket.drawName, result.drawName)) {
          continue; // Draw Shift / Time mismatch! Skip this ticket.
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
      if (tNo5Digits == firstPrize5Digits || (consolation5Digits.isNotEmpty && tNo5Digits == consolation5Digits)) {
        final cfg = configMap[1] ?? PrizeTierConfigModel.defaultConfig[1]!;
        final payout = cfg.calculatePayout(seriesCount);
        winners.add(
          WinningClaimModel(
            id: 'win_${now.millisecondsSinceEpoch}_${ticket.id}',
            drawId: result.drawId,
            drawName: result.drawName,
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
            id: 'win_${now.millisecondsSinceEpoch}_${ticket.id}',
            drawId: result.drawId,
            drawName: result.drawName,
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
            id: 'win_${now.millisecondsSinceEpoch}_${ticket.id}',
            drawId: result.drawId,
            drawName: result.drawName,
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
            id: 'win_${now.millisecondsSinceEpoch}_${ticket.id}',
            drawId: result.drawId,
            drawName: result.drawName,
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
            id: 'win_${now.millisecondsSinceEpoch}_${ticket.id}',
            drawId: result.drawId,
            drawName: result.drawName,
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
}
