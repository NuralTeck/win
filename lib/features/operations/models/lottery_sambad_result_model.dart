// Official Lottery Sambad / Nagaland State Lottery Result Model

class LotterySambadResultModel {
  final String drawId;
  final String drawName;
  final String drawDateStr; // e.g. 31.07.2026
  final String drawTimeStr; // e.g. 01:00 PM / 06:00 PM / 08:00 PM
  
  // Official Sambad Prize Tiers
  final String firstPrize; // e.g. "83L 28311"
  final double firstPrizeAmount; // e.g. 10000000 (₹1 Cr)
  
  final String consolationPrize; // e.g. "28311"
  final double consolationAmount; // e.g. 1000 (₹1,000)
  
  final List<String> secondPrizeNumbers; // 10 5-digit numbers (₹9,000)
  final double secondPrizeAmount;
  
  final List<String> thirdPrizeNumbers; // 10 4-digit numbers (₹500)
  final double thirdPrizeAmount;
  
  final List<String> fourthPrizeNumbers; // 10 4-digit numbers (₹250)
  final double fourthPrizeAmount;
  
  final List<String> fifthPrizeNumbers; // 100 4-digit numbers (₹120)
  final double fifthPrizeAmount;
  
  final DateTime publishedAt;
  final bool isVerified;

  const LotterySambadResultModel({
    required this.drawId,
    required this.drawName,
    required this.drawDateStr,
    required this.drawTimeStr,
    required this.firstPrize,
    this.firstPrizeAmount = 10000000.0,
    required this.consolationPrize,
    this.consolationAmount = 1000.0,
    required this.secondPrizeNumbers,
    this.secondPrizeAmount = 9000.0,
    required this.thirdPrizeNumbers,
    this.thirdPrizeAmount = 500.0,
    required this.fourthPrizeNumbers,
    this.fourthPrizeAmount = 250.0,
    required this.fifthPrizeNumbers,
    this.fifthPrizeAmount = 120.0,
    required this.publishedAt,
    this.isVerified = true,
  });
}
