import 'program_definition.dart';
import 'schedule_definition.dart';

class MqttCommandRequest {
  const MqttCommandRequest({
    required this.requestId,
    required this.type,
    required this.timestamp,
    required this.robotId,
    required this.username,
    this.program,
    this.schedule,
    this.scheduleId,
    this.enabled,
  });

  final String requestId;
  final String type;
  final DateTime timestamp;
  final String robotId;
  final String username;
  final ProgramDefinition? program;
  final ScheduleDefinition? schedule;
  final String? scheduleId;
  final bool? enabled;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'requestId': requestId,
        'type': type,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'source': <String, dynamic>{
          'client': 'remote_app',
          'username': username,
        },
        'robotId': robotId,
        if (program != null) 'program': program!.toJson(),
        if (schedule != null)
          'schedule': <String, dynamic>{
            ...schedule!.toJson(),
            if (program != null) 'program': program!.toJson(),
          },
        if (scheduleId != null) 'scheduleId': scheduleId,
        if (enabled != null) 'enabled': enabled,
      };
}
