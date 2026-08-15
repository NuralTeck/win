// Master Draw Time / Shift model

class DrawTimeModel {
  final String id;
  final String timeLabel; // e.g. "Dear 1 PM", "Dear 6 PM", "Dear 8 PM"
  final String timeCode;  // e.g. "1PM", "6PM", "8PM"
  final String shiftName; // e.g. "Morning", "Day", "Evening", "Night"
  final bool isActive;
  final DateTime createdAt;

  const DrawTimeModel({
    required this.id,
    required this.timeLabel,
    required this.timeCode,
    required this.shiftName,
    this.isActive = true,
    required this.createdAt,
  });

  DrawTimeModel copyWith({
    String? id,
    String? timeLabel,
    String? timeCode,
    String? shiftName,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return DrawTimeModel(
      id: id ?? this.id,
      timeLabel: timeLabel ?? this.timeLabel,
      timeCode: timeCode ?? this.timeCode,
      shiftName: shiftName ?? this.shiftName,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
