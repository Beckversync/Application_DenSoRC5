class AlertLog {
  const AlertLog({
    required this.timestamp,
    required this.level,
    required this.message,
  });

  final DateTime timestamp;
  final String level;
  final String message;

  factory AlertLog.fromJson(Map<String, dynamic> json) {
    return AlertLog(
      timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ?? DateTime.now(),
      level: json['level']?.toString() ?? 'INFO',
      message: json['message']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'timestamp': timestamp.toUtc().toIso8601String(),
        'level': level,
        'message': message,
      };
}
