class CommandLog {
  const CommandLog({
    required this.timestamp,
    required this.username,
    required this.commandType,
    required this.message,
    required this.success,
  });

  final DateTime timestamp;
  final String username;
  final String commandType;
  final String message;
  final bool success;

  factory CommandLog.fromJson(Map<String, dynamic> json) {
    return CommandLog(
      timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ?? DateTime.now(),
      username: json['username']?.toString() ?? 'system',
      commandType: json['commandType']?.toString() ?? 'UNKNOWN',
      message: json['message']?.toString() ?? '',
      success: json['success'] == true,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'timestamp': timestamp.toUtc().toIso8601String(),
        'username': username,
        'commandType': commandType,
        'message': message,
        'success': success,
      };
}
