enum OperationStatus {
  active,
  pending,
  completed,
  suspended,
  failed,
}

enum OperationPriority {
  critical,
  high,
  medium,
  low,
}

class OperationModel {
  final String id;
  final String code;
  final String title;
  final String category;
  final String assignees;
  final OperationStatus status;
  final OperationPriority priority;
  final double progress; // 0.0 to 1.0
  final DateTime createdAt;
  final DateTime updatedAt;
  final String nodeLocation;

  const OperationModel({
    required this.id,
    required this.code,
    required this.title,
    required this.category,
    required this.assignees,
    required this.status,
    required this.priority,
    required this.progress,
    required this.createdAt,
    required this.updatedAt,
    required this.nodeLocation,
  });

  OperationModel copyWith({
    String? id,
    String? code,
    String? title,
    String? category,
    String? assignees,
    OperationStatus? status,
    OperationPriority? priority,
    double? progress,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? nodeLocation,
  }) {
    return OperationModel(
      id: id ?? this.id,
      code: code ?? this.code,
      title: title ?? this.title,
      category: category ?? this.category,
      assignees: assignees ?? this.assignees,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      progress: progress ?? this.progress,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      nodeLocation: nodeLocation ?? this.nodeLocation,
    );
  }
}
