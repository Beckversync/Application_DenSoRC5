class MqttAckResponse {
  const MqttAckResponse({
    required this.requestId,
    required this.robotId,
    required this.accepted,
    required this.status,
    required this.message,
    required this.timestamp,
  });

  final String requestId;
  final String robotId;
  final bool accepted;
  final String status;
  final String message;
  final DateTime timestamp;

  factory MqttAckResponse.fromJson(Map<String, dynamic> json) {
    return MqttAckResponse(
      requestId: json['requestId']?.toString() ?? '',
      robotId: json['robotId']?.toString() ?? 'RB001',
      accepted: json['accepted'] == true,
      status: json['status']?.toString() ?? 'UNKNOWN',
      message: json['message']?.toString() ?? '',
      timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}
