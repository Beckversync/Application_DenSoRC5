enum ScheduleType { oneTime }

class ScheduleDefinition {
  const ScheduleDefinition({
    required this.id,
    required this.programId,
    required this.programName,
    required this.scheduledAt,
    required this.enabled,
    required this.commandCount,
    required this.defaultDelayMs,
    this.note,
    this.scheduleType = ScheduleType.oneTime,
    this.requestId,
  });

  final String id;
  final String programId;
  final String programName;
  final DateTime scheduledAt;
  final bool enabled;
  final int commandCount;
  final int defaultDelayMs;
  final String? note;
  final ScheduleType scheduleType;
  final String? requestId;

  ScheduleDefinition copyWith({
    String? id,
    String? programId,
    String? programName,
    DateTime? scheduledAt,
    bool? enabled,
    int? commandCount,
    int? defaultDelayMs,
    String? note,
    ScheduleType? scheduleType,
    String? requestId,
  }) {
    return ScheduleDefinition(
      id: id ?? this.id,
      programId: programId ?? this.programId,
      programName: programName ?? this.programName,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      enabled: enabled ?? this.enabled,
      commandCount: commandCount ?? this.commandCount,
      defaultDelayMs: defaultDelayMs ?? this.defaultDelayMs,
      note: note ?? this.note,
      scheduleType: scheduleType ?? this.scheduleType,
      requestId: requestId ?? this.requestId,
    );
  }

  factory ScheduleDefinition.fromJson(Map<String, dynamic> json) {
    return ScheduleDefinition(
      id: json['scheduleId']?.toString() ?? json['id']?.toString() ?? 'SCH-0',
      programId: json['programId']?.toString() ?? 'P-0',
      programName: json['programName']?.toString() ?? 'Program',
      scheduledAt: DateTime.tryParse(
            json['runAt']?.toString() ?? json['triggerTime']?.toString() ?? json['scheduledAt']?.toString() ?? '',
          ) ??
          DateTime.now(),
      enabled: json['enabled'] != false,
      commandCount: (json['commandCount'] as num?)?.toInt() ?? 0,
      defaultDelayMs: (json['defaultDelayMs'] as num?)?.toInt() ?? 1000,
      note: json['note']?.toString(),
      requestId: json['requestId']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'scheduleId': id,
        'programId': programId,
        'programName': programName,
        'triggerTime': scheduledAt.toUtc().toIso8601String(),
        'enabled': enabled,
        'commandCount': commandCount,
        'defaultDelayMs': defaultDelayMs,
        'note': note,
        'scheduleType': 'ONE_TIME',
        'requestId': requestId,
      };
}
