import '../models/winning_claim_model.dart';
import '../models/lottery_sambad_result_model.dart';
import '../models/prize_config_model.dart';
import '../../unsold/models/voucher_model.dart';
import '../../unsold/models/unsold_model.dart';

class PartySeriesHisab {
  final String series;
  int voucherQty;
  int unsoldQty;
  double rate;

  PartySeriesHisab({
    required this.series,
    this.voucherQty = 0,
    this.unsoldQty = 0,
    required this.rate,
  });

  int get netSoldQty => (voucherQty >= unsoldQty) ? voucherQty - unsoldQty : 0;
  double get grossAmount => voucherQty * rate;
  double get unsoldCredit => unsoldQty * rate;
  double get netAmount => netSoldQty * rate;
}

class ShiftHisabBreakdown {
  final String shift;
  final String canonicalShift;
  final List<VoucherModel> vouchers;
  final List<UnsoldModel> unsold;
  final List<PartySeriesHisab> seriesHisabList;
  final int totalVouchers;
  final int totalUnsold;
  final int totalNetSold;
  final double totalVoucherAmount;
  final double totalUnsoldAmount;
  final double totalNetAmount;
  final List<WinningClaimModel> customerWins;
  final bool hasEntry;

  ShiftHisabBreakdown({
    required this.shift,
    required this.canonicalShift,
    required this.vouchers,
    required this.unsold,
    required this.seriesHisabList,
    required this.totalVouchers,
    required this.totalUnsold,
    required this.totalNetSold,
    required this.totalVoucherAmount,
    required this.totalUnsoldAmount,
    required this.totalNetAmount,
    required this.customerWins,
    required this.hasEntry,
  });

  double get totalCustomerWinAmount => customerWins.fold(0.0, (s, w) => s + w.prizeAmount);
  double get finalNetPayable => totalNetAmount - totalCustomerWinAmount;
}

class DateHisabBreakdown {
  final String date;
  final String formattedDate;
  final List<ShiftHisabBreakdown> shifts;
  final int totalVouchers;
  final int totalUnsold;
  final int totalNetSold;
  final double totalVoucherAmount;
  final double totalUnsoldAmount;
  final double totalNetAmount;
  final double totalWinAmount;
  final double finalNetPayable;
  final bool hasEntry;

  DateHisabBreakdown({
    required this.date,
    required this.formattedDate,
    required this.shifts,
    required this.totalVouchers,
    required this.totalUnsold,
    required this.totalNetSold,
    required this.totalVoucherAmount,
    required this.totalUnsoldAmount,
    required this.totalNetAmount,
    required this.totalWinAmount,
    required this.finalNetPayable,
    required this.hasEntry,
  });
}

class SubSellerHisabItem {
  final String sellerName;
  final int totalVouchers;
  final int totalUnsold;
  final int totalNetSold;
  final double totalVoucherAmount;
  final double totalUnsoldAmount;
  final double totalNetAmount;
  final double totalWinAmount;
  final double finalNetPayable;

  SubSellerHisabItem({
    required this.sellerName,
    required this.totalVouchers,
    required this.totalUnsold,
    required this.totalNetSold,
    required this.totalVoucherAmount,
    required this.totalUnsoldAmount,
    required this.totalNetAmount,
    required this.totalWinAmount,
    required this.finalNetPayable,
  });
}

class PartyHisabSummary {
  final String partyName;
  final String? dealerName;
  final bool isDealer;
  final List<SubSellerHisabItem> subSellerBreakdowns;
  final String date;
  final String shift;
  final List<PartySeriesHisab> seriesHisabList;
  final int totalVouchers;
  final int totalUnsold;
  final int totalNetSold;
  final int khullaCount;
  final double totalVoucherAmount;
  final double totalUnsoldAmount;
  final double totalNetAmount;
  final List<WinningClaimModel> customerWins;
  final List<WinningClaimModel> unsoldWins;
  final List<VoucherModel> rawVouchers;
  final List<UnsoldModel> rawUnsold;
  final List<DateHisabBreakdown> dateBreakdowns;

  PartyHisabSummary({
    required this.partyName,
    this.dealerName,
    this.isDealer = false,
    this.subSellerBreakdowns = const [],
    required this.date,
    required this.shift,
    required this.seriesHisabList,
    required this.totalVouchers,
    required this.totalUnsold,
    required this.totalNetSold,
    required this.khullaCount,
    required this.totalVoucherAmount,
    required this.totalUnsoldAmount,
    required this.totalNetAmount,
    required this.customerWins,
    required this.unsoldWins,
    required this.rawVouchers,
    required this.rawUnsold,
    this.dateBreakdowns = const [],
  });

  double get totalCustomerWinAmount => customerWins.fold(0.0, (s, w) => s + w.prizeAmount);
  double get totalUnsoldWinAmount => unsoldWins.fold(0.0, (s, w) => s + w.prizeAmount);
  double get finalNetPayable => totalNetAmount - totalCustomerWinAmount;
}

class PartyHisabSettlementEngine {
  static double getRateForSeries(String series) {
    switch (series.trim()) {
      case '5':  return 1.88;
      case '6':  return 2.25;
      case '12': return 4.50;
      case '20': return 7.50;
      case '24': return 9.00;
      case '36': return 13.50;
      case '40': return 15.00;
      case '50': return 18.75;
      case '60': return 22.50;
      case '84': return 31.50;
      case '100': return 37.50;
      default: return 4.50;
    }
  }

  static String normalizeDate(String d) {
    final clean = d.trim().replaceAll('/', '-');
    final parts = clean.split('-');
    if (parts.length == 3) {
      if (parts[0].length == 4) {
        return '${parts[0]}-${parts[1].padLeft(2, '0')}-${parts[2].padLeft(2, '0')}';
      } else if (parts[2].length == 4) {
        return '${parts[2]}-${parts[1].padLeft(2, '0')}-${parts[0].padLeft(2, '0')}';
      }
    }
    return clean;
  }

  static String _canonicalShift(String raw) {
    final lower = raw.toLowerCase().trim();
    if (lower.contains('1 pm') || lower.contains('1pm') || lower.contains('1:00') || lower.contains('morning')) {
      return '1PM';
    } else if (lower.contains('6 pm') || lower.contains('6pm') || lower.contains('6:00') || lower.contains('day')) {
      return '6PM';
    } else if (lower.contains('8 pm') || lower.contains('8pm') || lower.contains('8:00') || lower.contains('night') || lower.contains('evening')) {
      return '8PM';
    }
    return lower;
  }

  /// Calculates complete hisab settlement per party or dealer
  static List<PartyHisabSummary> calculatePartySettlements({
    required List<VoucherModel> vouchers,
    required List<UnsoldModel> unsoldList,
    required String selectedDate,
    String? startDate,
    String? endDate,
    required String selectedShift,
    String? selectedSeries,
    bool groupByDealer = false,
    LotterySambadResultModel? lotteryResult,
    List<LotterySambadResultModel>? allResults,
    Map<int, PrizeTierConfigModel>? prizeConfig,
  }) {
    final hasRange = startDate != null && startDate.isNotEmpty && endDate != null && endDate.isNotEmpty;

    // 1. Group Vouchers and Unsold by Party Name OR Dealer Name
    final Map<String, String> partyDisplayNames = {};
    final Map<String, List<VoucherModel>> partyVouchers = {};
    final Map<String, List<UnsoldModel>> partyUnsold = {};

    for (final v in vouchers) {
      if (selectedSeries != null && selectedSeries != 'ALL') {
        final serV = v.series.replaceAll(RegExp(r'\D'), '');
        final serFilter = selectedSeries.replaceAll(RegExp(r'\D'), '');
        if (serV.isNotEmpty && serFilter.isNotEmpty && serV != serFilter) continue;
        if (serV.isEmpty && v.series.trim().toUpperCase() != selectedSeries.trim().toUpperCase()) continue;
      }
      final vDateNorm = normalizeDate(v.date);
      final dateMatches = hasRange
          ? (vDateNorm.compareTo(startDate) >= 0 && vDateNorm.compareTo(endDate) <= 0)
          : _matchesFilter(v.date, selectedDate);

      if (dateMatches && _matchesShift(v.drawShift, selectedShift)) {
        final keyRaw = groupByDealer ? v.effectiveDealer : v.partyName;
        final rawP = keyRaw.trim().isEmpty ? (groupByDealer ? 'Direct Dealer' : 'Walk-in Party') : keyRaw.trim();
        final pKey = rawP.toUpperCase();
        partyDisplayNames.putIfAbsent(pKey, () => rawP);
        partyVouchers.putIfAbsent(pKey, () => []).add(v);
      }
    }

    for (final u in unsoldList) {
      if (selectedSeries != null && selectedSeries != 'ALL') {
        final serU = u.series.replaceAll(RegExp(r'\D'), '');
        final serFilter = selectedSeries.replaceAll(RegExp(r'\D'), '');
        if (serU.isNotEmpty && serFilter.isNotEmpty && serU != serFilter) continue;
        if (serU.isEmpty && u.series.trim().toUpperCase() != selectedSeries.trim().toUpperCase()) continue;
      }
      final uDateNorm = normalizeDate(u.date);
      final dateMatches = hasRange
          ? (uDateNorm.compareTo(startDate) >= 0 && uDateNorm.compareTo(endDate) <= 0)
          : _matchesFilter(u.date, selectedDate);

      if (dateMatches && _matchesShift(u.drawShift, selectedShift)) {
        final keyRaw = groupByDealer ? u.effectiveDealer : u.partyName;
        final rawP = keyRaw.trim().isEmpty ? (groupByDealer ? 'Direct Dealer' : 'Walk-in Party') : keyRaw.trim();
        final pKey = rawP.toUpperCase();
        partyDisplayNames.putIfAbsent(pKey, () => rawP);
        partyUnsold.putIfAbsent(pKey, () => []).add(u);
      }
    }

    final Set<String> allPartyKeys = {...partyVouchers.keys, ...partyUnsold.keys};
    final List<PartyHisabSummary> summaries = [];
    final Map<String, _DrawWinningIndex> indexCache = {};

    for (final partyKey in allPartyKeys) {
      final partyDisplayName = partyDisplayNames[partyKey] ?? partyKey;
      final pVouchers = partyVouchers[partyKey] ?? [];
      final pUnsold = partyUnsold[partyKey] ?? [];

      // Group by series
      final Map<String, PartySeriesHisab> seriesMap = {};
      int khullaCount = 0;

      for (final v in pVouchers) {
        final s = v.series.trim().isEmpty ? '12' : v.series.trim();
        final rate = v.pricePerTicket > 0 ? v.pricePerTicket : getRateForSeries(s);
        seriesMap.putIfAbsent(s, () => PartySeriesHisab(series: s, rate: rate));
        seriesMap[s]!.voucherQty += v.totalQty;
      }

      for (final u in pUnsold) {
        final s = u.series.trim().isEmpty ? '12' : u.series.trim();
        final rate = u.pricePerTicket > 0 ? u.pricePerTicket : getRateForSeries(s);
        seriesMap.putIfAbsent(s, () => PartySeriesHisab(series: s, rate: rate));
        seriesMap[s]!.unsoldQty += u.totalQty;

        if (u.totalQty == 1 || u.fromTicket == u.toTicket) {
          khullaCount += u.totalQty;
        }
      }

      final seriesList = seriesMap.values.toList()
        ..sort((a, b) => (int.tryParse(a.series) ?? 0).compareTo(int.tryParse(b.series) ?? 0));

      final totalV = seriesList.fold(0, (sum, s) => sum + s.voucherQty);
      final totalU = seriesList.fold(0, (sum, s) => sum + s.unsoldQty);
      final totalNet = seriesList.fold(0, (sum, s) => sum + s.netSoldQty);
      final totalVouchAmt = seriesList.fold(0.0, (sum, s) => sum + s.grossAmount);
      final totalUnsoldAmt = seriesList.fold(0.0, (sum, s) => sum + s.unsoldCredit);
      final totalNetAmt = seriesList.fold(0.0, (sum, s) => sum + s.netAmount);

      // Calculate winning claims for this party strictly by exact date and shift matching!
      List<WinningClaimModel> customerWins = [];
      const List<WinningClaimModel> unsoldWins = [];

      if (allResults != null && allResults.isNotEmpty) {
        // Group vouchers and unsold by exact date & shift so 1 PM vouchers only match 1 PM results, etc.
        final Map<String, List<VoucherModel>> shiftDateVouchers = {};
        final Map<String, List<UnsoldModel>> shiftDateUnsold = {};

        for (final v in pVouchers) {
          final k = '${normalizeDate(v.date)}_${_canonicalShift(v.drawShift)}';
          shiftDateVouchers.putIfAbsent(k, () => []).add(v);
        }
        for (final u in pUnsold) {
          final k = '${normalizeDate(u.date)}_${_canonicalShift(u.drawShift)}';
          shiftDateUnsold.putIfAbsent(k, () => []).add(u);
        }

        final allKeys = {...shiftDateVouchers.keys, ...shiftDateUnsold.keys};
        for (final k in allKeys) {
          final parts = k.split('_');
          final tDate = parts[0];
          final tShift = parts.length > 1 ? parts[1] : '';

          // Find or get precomputed index for this exact date & shift
          _DrawWinningIndex? index = indexCache[k];
          if (index == null) {
            final res = allResults.where((r) {
              final rDate = normalizeDate(r.drawDateStr);
              final rShift = _canonicalShift(r.drawName);
              return rDate == tDate && rShift == tShift;
            }).firstOrNull;

            if (res != null) {
              index = _DrawWinningIndex.fromResult(res, prizeConfig);
              indexCache[k] = index;
            }
          }

          if (index != null) {
            final wins = _matchPartyWinsFast(
              winningIndex: index,
              vouchers: shiftDateVouchers[k] ?? [],
              unsoldList: shiftDateUnsold[k] ?? [],
              partyName: partyDisplayName,
              prizeConfig: prizeConfig,
            );
            customerWins.addAll(wins);
          }
        }
      } else if (lotteryResult != null) {
        final k = '${normalizeDate(lotteryResult.drawDateStr)}_${_canonicalShift(lotteryResult.drawName)}';
        var index = indexCache[k];
        if (index == null) {
          index = _DrawWinningIndex.fromResult(lotteryResult, prizeConfig);
          indexCache[k] = index;
        }

        final matchingVouchers = pVouchers.where((v) => _matchesShift(v.drawShift, lotteryResult.drawName)).toList();
        final matchingUnsold = pUnsold.where((u) => _matchesShift(u.drawShift, lotteryResult.drawName)).toList();

        customerWins = _matchPartyWinsFast(
          winningIndex: index,
          vouchers: matchingVouchers,
          unsoldList: matchingUnsold,
          partyName: partyDisplayName,
          prizeConfig: prizeConfig,
        );
      }

      // Build Date & Shift Breakdowns (for Shift == ALL and Custom Date Ranges)
      final List<DateHisabBreakdown> dateBreakdowns = [];

      final List<String> datesToProcess = [];
      if (hasRange) {
        try {
          final sDate = DateTime.parse(startDate);
          final eDate = DateTime.parse(endDate);
          var curr = sDate;
          while (!curr.isAfter(eDate)) {
            datesToProcess.add('${curr.year}-${curr.month.toString().padLeft(2, '0')}-${curr.day.toString().padLeft(2, '0')}');
            curr = curr.add(const Duration(days: 1));
          }
        } catch (_) {
          datesToProcess.add(normalizeDate(selectedDate));
        }
      } else {
        datesToProcess.add(normalizeDate(selectedDate));
      }

      final shiftsToProcess = selectedShift == 'ALL'
          ? ['Dear 1 PM', 'Dear 6 PM', 'Dear 8 PM']
          : [selectedShift];

      for (final dStr in datesToProcess) {
        final List<ShiftHisabBreakdown> shiftBreakdowns = [];
        int dTotV = 0;
        int dTotU = 0;
        int dTotNet = 0;
        double dTotVAmt = 0.0;
        double dTotUAmt = 0.0;
        double dTotNetAmt = 0.0;
        double dTotWinAmt = 0.0;
        bool dateHasEntry = false;

        String formattedDate = dStr;
        try {
          final dt = DateTime.parse(dStr);
          const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
          final dayName = weekdays[dt.weekday - 1];
          formattedDate = '${dt.day.toString().padLeft(2, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.year} ($dayName)';
        } catch (_) {}

        for (final sh in shiftsToProcess) {
          final shCanonical = _canonicalShift(sh);

          final shVouchers = pVouchers.where((v) {
            return normalizeDate(v.date) == dStr && _canonicalShift(v.drawShift) == shCanonical;
          }).toList();

          final shUnsold = pUnsold.where((u) {
            return normalizeDate(u.date) == dStr && _canonicalShift(u.drawShift) == shCanonical;
          }).toList();

          final Map<String, PartySeriesHisab> shSeriesMap = {};
          for (final v in shVouchers) {
            final s = v.series.trim().isEmpty ? '12' : v.series.trim();
            final rate = v.pricePerTicket > 0 ? v.pricePerTicket : getRateForSeries(s);
            shSeriesMap.putIfAbsent(s, () => PartySeriesHisab(series: s, rate: rate));
            shSeriesMap[s]!.voucherQty += v.totalQty;
          }
          for (final u in shUnsold) {
            final s = u.series.trim().isEmpty ? '12' : u.series.trim();
            final rate = u.pricePerTicket > 0 ? u.pricePerTicket : getRateForSeries(s);
            shSeriesMap.putIfAbsent(s, () => PartySeriesHisab(series: s, rate: rate));
            shSeriesMap[s]!.unsoldQty += u.totalQty;
          }

          final shSeriesList = shSeriesMap.values.toList()
            ..sort((a, b) => (int.tryParse(a.series) ?? 0).compareTo(int.tryParse(b.series) ?? 0));

          final shTotV = shSeriesList.fold(0, (sum, s) => sum + s.voucherQty);
          final shTotU = shSeriesList.fold(0, (sum, s) => sum + s.unsoldQty);
          final shTotNet = shSeriesList.fold(0, (sum, s) => sum + s.netSoldQty);
          final shTotVAmt = shSeriesList.fold(0.0, (sum, s) => sum + s.grossAmount);
          final shTotUAmt = shSeriesList.fold(0.0, (sum, s) => sum + s.unsoldCredit);
          final shTotNetAmt = shSeriesList.fold(0.0, (sum, s) => sum + s.netAmount);

          final shWins = customerWins.where((w) {
            final wShift = _canonicalShift(w.drawName);
            final wDrawId = w.drawId;
            final matchesDraw = wDrawId.contains(dStr) || w.drawName.contains(dStr);
            return (datesToProcess.length > 1 ? matchesDraw : true) && wShift == shCanonical;
          }).toList();

          final bool hasEntry = shVouchers.isNotEmpty || shUnsold.isNotEmpty || shWins.isNotEmpty;
          if (hasEntry) dateHasEntry = true;

          final sb = ShiftHisabBreakdown(
            shift: sh,
            canonicalShift: shCanonical,
            vouchers: shVouchers,
            unsold: shUnsold,
            seriesHisabList: shSeriesList,
            totalVouchers: shTotV,
            totalUnsold: shTotU,
            totalNetSold: shTotNet,
            totalVoucherAmount: shTotVAmt,
            totalUnsoldAmount: shTotUAmt,
            totalNetAmount: shTotNetAmt,
            customerWins: shWins,
            hasEntry: hasEntry,
          );

          shiftBreakdowns.add(sb);
          dTotV += shTotV;
          dTotU += shTotU;
          dTotNet += shTotNet;
          dTotVAmt += shTotVAmt;
          dTotUAmt += shTotUAmt;
          dTotNetAmt += shTotNetAmt;
          dTotWinAmt += sb.totalCustomerWinAmount;
        }

        dateBreakdowns.add(DateHisabBreakdown(
          date: dStr,
          formattedDate: formattedDate,
          shifts: shiftBreakdowns,
          totalVouchers: dTotV,
          totalUnsold: dTotU,
          totalNetSold: dTotNet,
          totalVoucherAmount: dTotVAmt,
          totalUnsoldAmount: dTotUAmt,
          totalNetAmount: dTotNetAmt,
          totalWinAmount: dTotWinAmt,
          finalNetPayable: dTotNetAmt - dTotWinAmt,
          hasEntry: dateHasEntry,
        ));
      }

      // Compute Sub-Seller breakdowns if grouped by Dealer
      final List<SubSellerHisabItem> subSellerBreakdowns = [];
      String? resolvedDealer;

      if (groupByDealer) {
        resolvedDealer = partyDisplayName;
        final Map<String, List<VoucherModel>> subVouchers = {};
        final Map<String, List<UnsoldModel>> subUnsold = {};
        for (final v in pVouchers) {
          final sName = v.partyName.trim().isEmpty ? partyDisplayName : v.partyName.trim();
          subVouchers.putIfAbsent(sName, () => []).add(v);
        }
        for (final u in pUnsold) {
          final sName = u.partyName.trim().isEmpty ? partyDisplayName : u.partyName.trim();
          subUnsold.putIfAbsent(sName, () => []).add(u);
        }
        final allSubNames = {...subVouchers.keys, ...subUnsold.keys}.toList()..sort();
        for (final sName in allSubNames) {
          final sv = subVouchers[sName] ?? [];
          final su = subUnsold[sName] ?? [];
          final totV = sv.fold<int>(0, (sum, x) => sum + x.totalQty);
          final totU = su.fold<int>(0, (sum, x) => sum + x.totalQty);
          final totVAmt = sv.fold<double>(0.0, (sum, x) => sum + x.totalAmount);
          final totUAmt = su.fold<double>(0.0, (sum, x) => sum + x.totalAmount);
          final netQty = (totV >= totU) ? totV - totU : 0;
          final netAmt = (totVAmt >= totUAmt) ? totVAmt - totUAmt : 0.0;
          final sWins = customerWins.where((w) => w.sellerName.trim().toLowerCase() == sName.toLowerCase()).toList();
          final winAmt = sWins.fold<double>(0.0, (sum, w) => sum + w.prizeAmount);
          subSellerBreakdowns.add(SubSellerHisabItem(
            sellerName: sName,
            totalVouchers: totV,
            totalUnsold: totU,
            totalNetSold: netQty,
            totalVoucherAmount: totVAmt,
            totalUnsoldAmount: totUAmt,
            totalNetAmount: netAmt,
            totalWinAmount: winAmt,
            finalNetPayable: netAmt - winAmt,
          ));
        }
      } else {
        for (final v in pVouchers) {
          if (v.dealerName != null && v.dealerName!.trim().isNotEmpty) {
            resolvedDealer = v.dealerName!.trim();
            break;
          }
        }
        if (resolvedDealer == null) {
          for (final u in pUnsold) {
            if (u.dealerName != null && u.dealerName!.trim().isNotEmpty) {
              resolvedDealer = u.dealerName!.trim();
              break;
            }
          }
        }
      }

      summaries.add(PartyHisabSummary(
        partyName: partyDisplayName,
        dealerName: resolvedDealer,
        isDealer: groupByDealer || (resolvedDealer != null && resolvedDealer.toLowerCase() == partyDisplayName.toLowerCase()),
        subSellerBreakdowns: subSellerBreakdowns,
        date: (hasRange && startDate != endDate) ? '$startDate to $endDate' : selectedDate,
        shift: selectedShift,
        seriesHisabList: seriesList,
        totalVouchers: totalV,
        totalUnsold: totalU,
        totalNetSold: totalNet,
        khullaCount: khullaCount,
        totalVoucherAmount: totalVouchAmt,
        totalUnsoldAmount: totalUnsoldAmt,
        totalNetAmount: totalNetAmt,
        customerWins: customerWins,
        unsoldWins: unsoldWins,
        rawVouchers: pVouchers,
        rawUnsold: pUnsold,
        dateBreakdowns: dateBreakdowns,
      ));
    }

    return summaries;
  }

  static bool _matchesFilter(String itemDate, String targetDate) {
    if (targetDate.isEmpty || targetDate == 'ALL') return true;
    return itemDate.contains(targetDate) || targetDate.contains(itemDate);
  }

  static bool _matchesShift(String itemShift, String targetShift) {
    if (targetShift.isEmpty || targetShift == 'ALL' || targetShift == 'All Shifts') return true;
    final i = itemShift.toLowerCase().trim();
    final t = targetShift.toLowerCase().trim();
    if (t.contains('1 pm') || t.contains('1pm') || t.contains('1:00') || t.contains('morning')) {
      return i.contains('1 pm') || i.contains('1pm') || i.contains('1:00') || i.contains('morning') || i == '1';
    }
    if (t.contains('6 pm') || t.contains('6pm') || t.contains('6:00') || t.contains('day')) {
      return i.contains('6 pm') || i.contains('6pm') || i.contains('6:00') || i.contains('day') || i == '6';
    }
    if (t.contains('8 pm') || t.contains('8pm') || t.contains('8:00') || t.contains('night') || t.contains('evening')) {
      return i.contains('8 pm') || i.contains('8pm') || i.contains('8:00') || i.contains('night') || i.contains('evening') || i == '8';
    }
    return i.contains(t) || t.contains(i);
  }

  static Set<String> expandTicketRange(String fromStr, String toStr) {
    final cleanFrom = fromStr.replaceAll(RegExp(r'\D'), '');
    final cleanTo = toStr.replaceAll(RegExp(r'\D'), '');
    final start = int.tryParse(cleanFrom);
    if (start == null) return cleanFrom.isNotEmpty ? {cleanFrom.padLeft(5, '0')} : {};
    if (cleanTo.isEmpty || cleanTo == cleanFrom) return {start.toString().padLeft(5, '0')};

    int? end;
    if (cleanTo.length == 5) {
      end = int.tryParse(cleanTo);
    } else if (cleanTo.length < 5 && cleanFrom.length == 5) {
      final resolved = cleanFrom.substring(0, 5 - cleanTo.length) + cleanTo;
      end = int.tryParse(resolved);
    } else {
      end = int.tryParse(cleanTo);
    }

    if (end == null || end < start) return {start.toString().padLeft(5, '0')};
    final count = end - start + 1;
    if (count > 2000) return {start.toString().padLeft(5, '0')};

    final set = <String>{};
    for (int i = start; i <= end; i++) {
      set.add(i.toString().padLeft(5, '0'));
    }
    return set;
  }

  /// High-performance winning matcher for 50k - 100k records
  static List<WinningClaimModel> _matchPartyWinsFast({
    required _DrawWinningIndex winningIndex,
    required List<VoucherModel> vouchers,
    required List<UnsoldModel> unsoldList,
    required String partyName,
    Map<int, PrizeTierConfigModel>? prizeConfig,
  }) {
    final List<WinningClaimModel> claims = [];
    final now = DateTime.now();
    final configMap = prizeConfig ?? PrizeTierConfigModel.defaultConfig;

    // 1. Build integer unsold intervals per series for O(1) exclusion check
    final Map<String, List<_RangePair>> unsoldRangesBySeries = {};
    for (final u in unsoldList) {
      final ser = u.series.replaceAll(RegExp(r'\D'), '').toUpperCase();
      final fromDigits = u.fromTicket.replaceAll(RegExp(r'\D'), '');
      final toDigits = u.toTicket.replaceAll(RegExp(r'\D'), '');
      if (fromDigits.isEmpty) continue;
      final fromInt = int.tryParse(fromDigits.length > 5 ? fromDigits.substring(fromDigits.length - 5) : fromDigits) ?? 0;
      final toInt = toDigits.isEmpty
          ? fromInt
          : (int.tryParse(toDigits.length > 5 ? toDigits.substring(toDigits.length - 5) : toDigits) ?? fromInt);
      final range = _RangePair(fromInt, toInt < fromInt ? fromInt : toInt);
      unsoldRangesBySeries.putIfAbsent(ser, () => []).add(range);
    }

    // 2. For each voucher, query pre-sorted winning ticket list via binary search (O(log M) per voucher)
    for (final v in vouchers) {
      final fromDigits = v.fromTicket.replaceAll(RegExp(r'\D'), '');
      final toDigits = v.toTicket.replaceAll(RegExp(r'\D'), '');
      if (fromDigits.isEmpty) continue;

      final fromInt = int.tryParse(fromDigits.length > 5 ? fromDigits.substring(fromDigits.length - 5) : fromDigits) ?? 0;
      final toInt = toDigits.isEmpty
          ? fromInt
          : (int.tryParse(toDigits.length > 5 ? toDigits.substring(toDigits.length - 5) : toDigits) ?? fromInt);

      final minVal = fromInt <= toInt ? fromInt : toInt;
      final maxVal = fromInt <= toInt ? toInt : fromInt;

      final series = v.series.isNotEmpty ? v.series : '12';
      final serClean = series.replaceAll(RegExp(r'\D'), '').toUpperCase();
      final seriesCount = int.tryParse(serClean) ?? 1;

      // Find start index in sorted winning tickets
      int idx = _lowerBound(winningIndex.sortedWinningTickets, minVal);
      final listLen = winningIndex.sortedWinningTickets.length;

      while (idx < listLen && winningIndex.sortedWinningTickets[idx] <= maxVal) {
        final winningTktInt = winningIndex.sortedWinningTickets[idx];
        final info = winningIndex.winningMap[winningTktInt];

        if (info != null) {
          // Check if this winning ticket was returned in unsold
          bool isReturned = false;
          final ranges = unsoldRangesBySeries[serClean];
          if (ranges != null) {
            for (final r in ranges) {
              if (winningTktInt >= r.from && winningTktInt <= r.to) {
                isReturned = true;
                break;
              }
            }
          }

          if (!isReturned) {
            final tkt5Str = winningTktInt.toString().padLeft(5, '0');
            final cfg = configMap[info.tierIndex];
            final baseAmt = cfg?.baseAmount ?? info.baseAmount;
            final sBonus = cfg?.superBonus ?? info.superBonus;
            final sIncentive = cfg?.specialIncentive ?? info.specialIncentive;
            final payout = cfg != null
                ? cfg.calculatePayout(seriesCount)
                : (baseAmt + sBonus + sIncentive) * seriesCount;

            claims.add(WinningClaimModel(
              id: 'win_${now.microsecondsSinceEpoch}_${claims.length}',
              drawId: winningIndex.result.drawId,
              drawName: winningIndex.result.drawName,
              prizeTier: info.tier,
              winningNumber: '${info.winningNumberStr} (#$tkt5Str)',
              prizeAmount: payout,
              seriesCount: seriesCount,
              baseAmount: baseAmt,
              superBonus: sBonus,
              specialIncentive: sIncentive,
              buyerName: partyName,
              sellerName: partyName,
              ticketSeries: series,
              ticketNumber: tkt5Str,
              verifiedAt: now,
            ));
          }
        }
        idx++;
      }
    }

    return claims;
  }
}

class _RangePair {
  final int from;
  final int to;
  _RangePair(this.from, this.to);
}

class _WinningTicketInfo {
  final String tier;
  final int tierIndex;
  final String winningNumberStr;
  final double baseAmount;
  final double superBonus;
  final double specialIncentive;

  _WinningTicketInfo({
    required this.tier,
    required this.tierIndex,
    required this.winningNumberStr,
    required this.baseAmount,
    required this.superBonus,
    required this.specialIncentive,
  });
}

class _DrawWinningIndex {
  final LotterySambadResultModel result;
  final List<int> sortedWinningTickets;
  final Map<int, _WinningTicketInfo> winningMap;

  _DrawWinningIndex({
    required this.result,
    required this.sortedWinningTickets,
    required this.winningMap,
  });

  static _DrawWinningIndex fromResult(LotterySambadResultModel result, Map<int, PrizeTierConfigModel>? prizeConfig) {
    final Map<int, _WinningTicketInfo> map = {};
    final configMap = prizeConfig ?? PrizeTierConfigModel.defaultConfig;

    int parse5(String s) {
      final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length >= 5) {
        return int.tryParse(digits.substring(digits.length - 5)) ?? 0;
      }
      return int.tryParse(digits) ?? 0;
    }

    int parse4(String s) {
      final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length >= 4) {
        return int.tryParse(digits.substring(digits.length - 4)) ?? 0;
      }
      return int.tryParse(digits) ?? 0;
    }

    // 1. 1st Prize (Exact 5 digits)
    final firstNum = parse5(result.firstPrize);
    final cfg1 = configMap[1];
    map[firstNum] = _WinningTicketInfo(
      tier: '🥇 1st Prize',
      tierIndex: 1,
      winningNumberStr: result.firstPrize,
      baseAmount: cfg1?.baseAmount ?? 15000.0,
      superBonus: cfg1?.superBonus ?? 10000.0,
      specialIncentive: cfg1?.specialIncentive ?? 1000.0,
    );

    // Consolation Prize
    if (result.consolationPrize.isNotEmpty) {
      final consNum = parse5(result.consolationPrize);
      final cfgCons = configMap[6];
      map.putIfAbsent(consNum, () => _WinningTicketInfo(
        tier: '🎁 Consolation Prize',
        tierIndex: 6,
        winningNumberStr: result.consolationPrize,
        baseAmount: cfgCons?.baseAmount ?? 1000.0,
        superBonus: cfgCons?.superBonus ?? 500.0,
        specialIncentive: cfgCons?.specialIncentive ?? 50.0,
      ));
    }

    // 2. 2nd Prize (Exact 5 digits)
    final cfg2 = configMap[2];
    for (final numStr in result.secondPrizeNumbers) {
      final num = parse5(numStr);
      map.putIfAbsent(num, () => _WinningTicketInfo(
        tier: '🥈 2nd Prize',
        tierIndex: 2,
        winningNumberStr: numStr,
        baseAmount: cfg2?.baseAmount ?? 5000.0,
        superBonus: cfg2?.superBonus ?? 2500.0,
        specialIncentive: cfg2?.specialIncentive ?? 100.0,
      ));
    }

    // 3. 3rd Prize (Last 4 digits exact match)
    final cfg3 = configMap[3];
    for (final numStr in result.thirdPrizeNumbers) {
      final last4 = parse4(numStr);
      for (int prefix = 0; prefix < 10; prefix++) {
        final num5 = prefix * 10000 + last4;
        map.putIfAbsent(num5, () => _WinningTicketInfo(
          tier: '🥉 3rd Prize',
          tierIndex: 3,
          winningNumberStr: numStr,
          baseAmount: cfg3?.baseAmount ?? 500.0,
          superBonus: cfg3?.superBonus ?? 120.0,
          specialIncentive: cfg3?.specialIncentive ?? 12.0,
        ));
      }
    }

    // 4. 4th Prize (Last 4 digits exact match)
    final cfg4 = configMap[4];
    for (final numStr in result.fourthPrizeNumbers) {
      final last4 = parse4(numStr);
      for (int prefix = 0; prefix < 10; prefix++) {
        final num5 = prefix * 10000 + last4;
        map.putIfAbsent(num5, () => _WinningTicketInfo(
          tier: '🏅 4th Prize',
          tierIndex: 4,
          winningNumberStr: numStr,
          baseAmount: cfg4?.baseAmount ?? 250.0,
          superBonus: cfg4?.superBonus ?? 100.0,
          specialIncentive: cfg4?.specialIncentive ?? 10.0,
        ));
      }
    }

    // 5. 5th Prize (Last 4 digits exact match)
    final cfg5 = configMap[5];
    for (final numStr in result.fifthPrizeNumbers) {
      final last4 = parse4(numStr);
      for (int prefix = 0; prefix < 10; prefix++) {
        final num5 = prefix * 10000 + last4;
        map.putIfAbsent(num5, () => _WinningTicketInfo(
          tier: '🏅 5th Prize',
          tierIndex: 5,
          winningNumberStr: numStr,
          baseAmount: cfg5?.baseAmount ?? 100.0,
          superBonus: cfg5?.superBonus ?? 50.0,
          specialIncentive: cfg5?.specialIncentive ?? 10.0,
        ));
      }
    }

    final sorted = map.keys.toList()..sort();
    return _DrawWinningIndex(
      result: result,
      sortedWinningTickets: sorted,
      winningMap: map,
    );
  }
}

int _lowerBound(List<int> list, int value) {
  int low = 0;
  int high = list.length;
  while (low < high) {
    final mid = (low + high) >> 1;
    if (list[mid] < value) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  return low;
}
