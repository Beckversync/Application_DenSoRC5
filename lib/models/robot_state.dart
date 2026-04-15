import 'robot_authority.dart';
import 'robot_mode.dart';

class RobotState {
  RobotState({
    required this.robotId,
    required this.robotName,
    required this.mode,
    required this.connectionStatus,
    required this.jointAngles,
    required this.lastUpdate,
    required this.alertMessage,
    required this.authority,
    this.robotStateLabel,
    this.faultActive = false,
    this.heartbeat,
    this.latencyMs,
    this.runningProgramId,
    this.currentStepNo,
  });

  final String robotId;
  final String robotName;
  final RobotMode mode;
  final ConnectionStatus connectionStatus;
  final List<double> jointAngles;
  final DateTime lastUpdate;
  final String? alertMessage;
  final RobotAuthority authority;
  final String? robotStateLabel;
  final bool faultActive;
  final int? heartbeat;
  final int? latencyMs;
  final String? runningProgramId;
  final int? currentStepNo;

  RobotState copyWith({
    String? robotId,
    String? robotName,
    RobotMode? mode,
    ConnectionStatus? connectionStatus,
    List<double>? jointAngles,
    DateTime? lastUpdate,
    String? alertMessage,
    bool clearAlert = false,
    RobotAuthority? authority,
    String? robotStateLabel,
    bool? faultActive,
    int? heartbeat,
    bool clearHeartbeat = false,
    int? latencyMs,
    bool clearLatency = false,
    String? runningProgramId,
    int? currentStepNo,
  }) {
    return RobotState(
      robotId: robotId ?? this.robotId,
      robotName: robotName ?? this.robotName,
      mode: mode ?? this.mode,
      connectionStatus: connectionStatus ?? this.connectionStatus,
      jointAngles: jointAngles ?? this.jointAngles,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      alertMessage: clearAlert ? null : alertMessage ?? this.alertMessage,
      authority: authority ?? this.authority,
      robotStateLabel: robotStateLabel ?? this.robotStateLabel,
      faultActive: faultActive ?? this.faultActive,
      heartbeat: clearHeartbeat ? null : heartbeat ?? this.heartbeat,
      latencyMs: clearLatency ? null : latencyMs ?? this.latencyMs,
      runningProgramId: runningProgramId ?? this.runningProgramId,
      currentStepNo: currentStepNo ?? this.currentStepNo,
    );
  }

  factory RobotState.fromJson(Map<String, dynamic> json) {
    RobotMode parseMode(String? value) {
      return value?.toUpperCase() == 'AUTO' ? RobotMode.auto : RobotMode.manual;
    }

    ConnectionStatus parseStatus(String? value, bool? online) {
      if (online == true) return ConnectionStatus.online;
      switch (value?.toUpperCase()) {
        case 'ONLINE':
          return ConnectionStatus.online;
        case 'CONNECTING':
          return ConnectionStatus.connecting;
        default:
          return ConnectionStatus.offline;
      }
    }

    final jointsRaw = json['jointAngles'] ?? json['joints'];
    final joints = jointsRaw is List
        ? jointsRaw.map((e) => (e as num).toDouble()).toList(growable: false)
        : const <double>[0, 0, 0, 0, 0, 0];

    return RobotState(
      robotId: json['robotId']?.toString() ?? json['robotCode']?.toString() ?? 'RB001',
      robotName: json['robotName']?.toString() ?? 'DENSO RC5',
      mode: parseMode(json['mode']?.toString()),
      connectionStatus: parseStatus(json['connectionStatus']?.toString(), json['online'] as bool?),
      jointAngles: joints,
      lastUpdate: DateTime.tryParse(
            json['lastUpdate']?.toString() ?? json['timestamp']?.toString() ?? '',
          ) ??
          DateTime.now(),
      alertMessage: json['alertMessage']?.toString(),
      authority: RobotAuthority.fromWireValue(json['authority']?.toString()),
      robotStateLabel: json['state']?.toString(),
      faultActive: json['faultActive'] == true,
      heartbeat: (json['heartbeat'] as num?)?.toInt(),
      latencyMs: (json['latencyMs'] as num?)?.toInt() ?? (json['latency'] as num?)?.toInt(),
      runningProgramId: json['runningProgramId']?.toString() ?? json['programId']?.toString(),
      currentStepNo: (json['currentStepNo'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'robotId': robotId,
        'robotName': robotName,
        'mode': mode == RobotMode.manual ? 'MANUAL' : 'AUTO',
        'connectionStatus': switch (connectionStatus) {
          ConnectionStatus.online => 'ONLINE',
          ConnectionStatus.offline => 'OFFLINE',
          ConnectionStatus.connecting => 'CONNECTING',
        },
        'jointAngles': jointAngles,
        'lastUpdate': lastUpdate.toUtc().toIso8601String(),
        'alertMessage': alertMessage,
        'authority': authority.wireValue,
        'state': robotStateLabel,
        'faultActive': faultActive,
        'heartbeat': heartbeat,
        'latencyMs': latencyMs,
        'runningProgramId': runningProgramId,
        'currentStepNo': currentStepNo,
      };
}
