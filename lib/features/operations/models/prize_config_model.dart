/// Model defining Multi-Tier Prize Configurations (Base Amount, Super Bonus, Special Incentive)
class PrizeTierConfigModel {
  final int tierIndex;
  final String tierName;
  final double baseAmount;
  final double superBonus;
  final double specialIncentive;

  PrizeTierConfigModel({
    required this.tierIndex,
    required this.tierName,
    required this.baseAmount,
    required this.superBonus,
    required this.specialIncentive,
  });

  /// Formula: (baseAmount + superBonus + specialIncentive) * seriesCount
  double calculatePayout(int seriesCount) {
    final effectiveSeriesCount = seriesCount > 0 ? seriesCount : 1;
    return (baseAmount + superBonus + specialIncentive) * effectiveSeriesCount;
  }

  Map<String, dynamic> toMap() {
    return {
      'tierIndex': tierIndex,
      'tierName': tierName,
      'baseAmount': baseAmount,
      'superBonus': superBonus,
      'specialIncentive': specialIncentive,
    };
  }

  factory PrizeTierConfigModel.fromMap(Map<String, dynamic> map) {
    return PrizeTierConfigModel(
      tierIndex: (map['tierIndex'] as num?)?.toInt() ?? 1,
      tierName: map['tierName']?.toString() ?? '',
      baseAmount: (map['baseAmount'] as num?)?.toDouble() ?? 0.0,
      superBonus: (map['superBonus'] as num?)?.toDouble() ?? 0.0,
      specialIncentive: (map['specialIncentive'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// Default Nagaland Lottery Sambad 5-Tier Prize Matrix Config
  static Map<int, PrizeTierConfigModel> get defaultConfig => {
        1: PrizeTierConfigModel(
          tierIndex: 1,
          tierName: '🥇 1st Prize',
          baseAmount: 15000.0,
          superBonus: 10000.0,
          specialIncentive: 1000.0,
        ),
        2: PrizeTierConfigModel(
          tierIndex: 2,
          tierName: '🥈 2nd Prize',
          baseAmount: 5000.0,
          superBonus: 2500.0,
          specialIncentive: 100.0,
        ),
        3: PrizeTierConfigModel(
          tierIndex: 3,
          tierName: '🥉 3rd Prize',
          baseAmount: 500.0,
          superBonus: 120.0,
          specialIncentive: 12.0,
        ),
        4: PrizeTierConfigModel(
          tierIndex: 4,
          tierName: '🏅 4th Prize',
          baseAmount: 250.0,
          superBonus: 100.0,
          specialIncentive: 10.0,
        ),
        5: PrizeTierConfigModel(
          tierIndex: 5,
          tierName: '🏅 5th Prize',
          baseAmount: 100.0,
          superBonus: 50.0,
          specialIncentive: 10.0,
        ),
        6: PrizeTierConfigModel(
          tierIndex: 6,
          tierName: '🎁 Consolation Prize',
          baseAmount: 1000.0,
          superBonus: 500.0,
          specialIncentive: 50.0,
        ),
      };
}
