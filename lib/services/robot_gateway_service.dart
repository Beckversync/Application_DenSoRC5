import 'dart:async';
import 'dart:math';

import '../models/alert_log.dart';
import '../models/command_log.dart';
import '../models/program_command.dart';
import '../models/program_definition.dart';
import '../models/robot_authority.dart';
import '../models/robot_mode.dart';
import '../models/robot_state.dart';
import '../models/schedule_definition.dart';
import '../models/user_role.dart';
import '../models/user_session.dart';
import 'mqtt_gateway_service.dart';
import 'robot_mqtt_topics.dart';

abstract class RobotGatewayService {
  Future<UserSession> login({required String username, required String password});
  Future<void> logout();
  Future<RobotState> loadInitialRobotState();
  Stream<RobotState> robotStateStream();

  Future<List<CommandLog>> fetchCommandLogs();
  Future<List<AlertLog>> fetchAlertLogs();
  Future<List<UserSession>> fetchUsers();

  Future<List<ProgramDefinition>> fetchPrograms();
  Future<ProgramDefinition> saveProgram({required UserSession session, required ProgramDefinition program});
  Future<void> deleteProgram({required UserSession session, required String programId});

  Future<List<ScheduleDefinition>> fetchSchedules();
  Future<void> createSchedule({
    required UserSession session,
    required ProgramDefinition program,
    required DateTime scheduledAt,
  });
  Future<void> sendJointCommand({
    required UserSession session,
    required List<double> targetJoints,
    required int changedJointIndex,
    required double stepDeg,
  });
  Future<void> setScheduleEnabled({
    required UserSession session,
    required String scheduleId,
    required bool enabled,
  });
  Future<void> deleteSchedule({required UserSession session, required String scheduleId});
  Future<void> dispose();
}

class MqttRobotGatewayService implements RobotGatewayService {
  MqttRobotGatewayService({
    required MqttGatewayService gateway,
    required this.robotId,
  })  : _gateway = gateway,
        _topics = RobotMqttTopics(robotId) {
    _robotState = RobotState(
      robotId: robotId,
      robotName: 'DENSO RC5',
      mode: RobotMode.manual,
      connectionStatus: ConnectionStatus.connecting,
      jointAngles: const <double>[0, 0, 0, 0, 0, 0],
      lastUpdate: DateTime.now(),
      alertMessage: null,
      authority: RobotAuthority.unknown,
    );
    _seedPrograms();
  }

  final MqttGatewayService _gateway;
  final String robotId;
  final RobotMqttTopics _topics;

  final StreamController<RobotState> _robotController = StreamController<RobotState>.broadcast();
  final List<CommandLog> _commandLogs = <CommandLog>[];
  final List<AlertLog> _alertLogs = <AlertLog>[];
  final List<ProgramDefinition> _programs = <ProgramDefinition>[];
  final List<ScheduleDefinition> _schedules = <ScheduleDefinition>[];

  StreamSubscription<MqttInboundMessage>? _mqttSubscription;
  UserSession? _session;
  late RobotState _robotState;

  @override
  Future<UserSession> login({required String username, required String password}) async {
    final normalized = username.trim().toLowerCase();
    if (password.trim().isEmpty) {
      throw Exception('Mật khẩu không được để trống.');
    }

    final role = switch (normalized) {
      'admin' => UserRole.admin,
      'operator' => UserRole.operator,
      'viewer' => UserRole.viewer,
      _ => UserRole.operator,
    };

    await _gateway.connect();

    await _mqttSubscription?.cancel();
    _mqttSubscription = _gateway.messages.listen(_handleInboundMessage);

    _gateway.subscribe(_topics.status, qos: MqttDelivery.atLeastOnce);
    _gateway.subscribe(_topics.telemetry, qos: MqttDelivery.atMostOnce);
    _gateway.subscribe(_topics.fault, qos: MqttDelivery.atLeastOnce);
    _gateway.subscribe(_topics.heartbeat, qos: MqttDelivery.atMostOnce);
    _gateway.subscribe(_topics.authority, qos: MqttDelivery.atLeastOnce);
    _gateway.subscribe(_topics.jointResponse, qos: MqttDelivery.atLeastOnce);
    _gateway.subscribe(_topics.scheduleList, qos: MqttDelivery.atLeastOnce);
    _gateway.subscribe(_topics.scheduleResponse, qos: MqttDelivery.atLeastOnce);
    _gateway.subscribe(_topics.scheduleExecution, qos: MqttDelivery.atLeastOnce);
    _gateway.subscribe(_topics.systemAlert(), qos: MqttDelivery.atLeastOnce);

    _session = UserSession(
      userId: 'U-${role.name.toUpperCase()}',
      username: username.trim().isEmpty ? role.label.toLowerCase() : username.trim(),
      role: role,
      token: 'mqtt-session-${DateTime.now().millisecondsSinceEpoch}',
    );

    _robotState = _robotState.copyWith(
      connectionStatus: ConnectionStatus.connecting,
      lastUpdate: DateTime.now(),
    );
    _robotController.add(_robotState);

    _logAction(
      username: _session!.username,
      commandType: 'MQTT_CONNECT',
      message: 'Connected to broker and subscribed to production topics under ${_topics.topicSummary}.',
      success: true,
    );

    _querySchedules();
    return _session!;
  }

  @override
  Future<void> logout() async {
    await _mqttSubscription?.cancel();
    _mqttSubscription = null;
    await _gateway.disconnect();
    _session = null;
    _robotState = _robotState.copyWith(
      connectionStatus: ConnectionStatus.offline,
      lastUpdate: DateTime.now(),
    );
  }

  @override
  Future<RobotState> loadInitialRobotState() async => _robotState;

  @override
  Stream<RobotState> robotStateStream() => _robotController.stream;

  @override
  Future<List<CommandLog>> fetchCommandLogs() async => List<CommandLog>.unmodifiable(_commandLogs);

  @override
  Future<List<AlertLog>> fetchAlertLogs() async => List<AlertLog>.unmodifiable(_alertLogs);

  @override
  Future<List<UserSession>> fetchUsers() async => const <UserSession>[
        UserSession(userId: 'U-ADMIN', username: 'admin', role: UserRole.admin, token: 'x'),
        UserSession(userId: 'U-OP', username: 'operator', role: UserRole.operator, token: 'x'),
        UserSession(userId: 'U-VIEW', username: 'viewer', role: UserRole.viewer, token: 'x'),
      ];

  @override
  Future<List<ProgramDefinition>> fetchPrograms() async => List<ProgramDefinition>.unmodifiable(_programs);

  @override
  Future<ProgramDefinition> saveProgram({required UserSession session, required ProgramDefinition program}) async {
    _ensurePlanner(session, 'lưu mẫu chương trình');
    final index = _programs.indexWhere((item) => item.id == program.id);
    final saved = index == -1 ? program.copyWith(id: 'P-${DateTime.now().millisecondsSinceEpoch}') : program;

    if (index == -1) {
      _programs.insert(0, saved);
    } else {
      _programs[index] = saved;
    }

    _logAction(
      username: session.username,
      commandType: index == -1 ? 'PROGRAM_TEMPLATE_CREATE' : 'PROGRAM_TEMPLATE_UPDATE',
      message: '${saved.name} saved locally as schedule template.',
      success: true,
    );

    return saved;
  }

  @override
  Future<void> deleteProgram({required UserSession session, required String programId}) async {
    _ensurePlanner(session, 'xóa mẫu chương trình');
    final index = _programs.indexWhere((item) => item.id == programId);
    if (index == -1) {
      throw Exception('Không tìm thấy chương trình.');
    }

    final removed = _programs.removeAt(index);
    _logAction(
      username: session.username,
      commandType: 'PROGRAM_TEMPLATE_DELETE',
      message: '${removed.name} removed from local schedule templates.',
      success: true,
    );
  }

  @override
  Future<List<ScheduleDefinition>> fetchSchedules() async => List<ScheduleDefinition>.unmodifiable(_schedules);

  @override
  Future<void> sendJointCommand({
    required UserSession session,
    required List<double> targetJoints,
    required int changedJointIndex,
    required double stepDeg,
  }) async {
    _ensureJointOperator(session, 'điều khiển joint');
    _ensureRemoteJointControlAvailable();
    if (targetJoints.length != 6) {
      throw Exception('Payload joint phải gồm đúng 6 giá trị.');
    }

    final normalizedJoints = targetJoints.map((e) => double.parse(e.toStringAsFixed(2))).toList(growable: false);
    final csvPayload = '${normalizedJoints.map((e) => e % 1 == 0 ? e.toStringAsFixed(0) : e.toStringAsFixed(2)).join(',')}\r';

    _publishJointControl(
      session: session,
      payload: <String, dynamic>{
        'requestId': _newRequestId(),
        'robotCode': robotId,
        'operator': session.username,
        'role': session.role.name.toUpperCase(),
        'jointIndex': changedJointIndex,
        'stepDeg': stepDeg,
        'joints': normalizedJoints,
        'serialCommand': csvPayload,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      },
      commandType: 'JOINT_POSE_REQUEST',
      successMessage: 'Published full 6-joint pose to ${_topics.jointRequest}: $csvPayload',
    );

    _robotState = _robotState.copyWith(
      jointAngles: normalizedJoints,
      lastUpdate: DateTime.now(),
      connectionStatus: ConnectionStatus.online,
      clearAlert: true,
    );
    _robotController.add(_robotState);
  }

  @override
  Future<void> createSchedule({
    required UserSession session,
    required ProgramDefinition program,
    required DateTime scheduledAt,
  }) async {
    _ensurePlanner(session, 'lập lịch');
    _ensureRemoteSchedulingAvailable();

    final requestId = _newRequestId();
    final schedule = ScheduleDefinition(
      id: 'LOCAL-${DateTime.now().millisecondsSinceEpoch}',
      programId: program.id,
      programName: program.name,
      scheduledAt: scheduledAt,
      enabled: true,
      commandCount: program.commands.length,
      defaultDelayMs: program.defaultDelayMs,
      note: 'Created from remote monitoring app',
      requestId: requestId,
    );

    _gateway.publishJson(
      _topics.scheduleRequest,
      <String, dynamic>{
        'requestId': requestId,
        'robotCode': robotId,
        'action': 'CREATE',
        'operator': session.username,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'data': <String, dynamic>{
          'programId': program.id,
          'programName': program.name,
          'triggerTime': scheduledAt.toUtc().toIso8601String(),
          'repeatType': 'ONCE',
          'enabled': true,
          'note': schedule.note,
        },
      },
      qos: MqttDelivery.atLeastOnce,
    );

    final existingIndex = _schedules.indexWhere((item) => item.requestId == requestId);
    if (existingIndex == -1) {
      _schedules.insert(0, schedule);
    }

    _logAction(
      username: session.username,
      commandType: 'SCHEDULE_CREATE_REQUEST',
      message: 'CREATE request published to ${_topics.scheduleRequest} for ${program.name} at ${scheduledAt.toLocal()}.',
      success: true,
    );
  }

  @override
  Future<void> setScheduleEnabled({
    required UserSession session,
    required String scheduleId,
    required bool enabled,
  }) async {
    _ensurePlanner(session, 'cập nhật lịch');
    _ensureRemoteSchedulingAvailable();
    final index = _schedules.indexWhere((item) => item.id == scheduleId);
    if (index == -1) {
      throw Exception('Không tìm thấy lịch.');
    }

    final current = _schedules[index];
    final requestId = _newRequestId();
    final action = enabled ? 'ENABLE' : 'DISABLE';
    _gateway.publishJson(
      _topics.scheduleRequest,
      <String, dynamic>{
        'requestId': requestId,
        'robotCode': robotId,
        'action': action,
        'operator': session.username,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'data': <String, dynamic>{
          'scheduleId': current.id,
        },
      },
      qos: MqttDelivery.atLeastOnce,
    );

    _schedules[index] = current.copyWith(enabled: enabled, requestId: requestId);
    _logAction(
      username: session.username,
      commandType: 'SCHEDULE_${action}_REQUEST',
      message: '${current.programName} ${enabled ? 'enabled' : 'disabled'} via ${_topics.scheduleRequest}.',
      success: true,
    );
  }

  @override
  Future<void> deleteSchedule({required UserSession session, required String scheduleId}) async {
    _ensurePlanner(session, 'xóa lịch');
    _ensureRemoteSchedulingAvailable();
    final index = _schedules.indexWhere((item) => item.id == scheduleId);
    if (index == -1) {
      throw Exception('Không tìm thấy lịch.');
    }

    final removed = _schedules.removeAt(index);
    final requestId = _newRequestId();
    _gateway.publishJson(
      _topics.scheduleRequest,
      <String, dynamic>{
        'requestId': requestId,
        'robotCode': robotId,
        'action': 'DELETE',
        'operator': session.username,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'data': <String, dynamic>{
          'scheduleId': removed.id,
        },
      },
      qos: MqttDelivery.atLeastOnce,
    );

    _logAction(
      username: session.username,
      commandType: 'SCHEDULE_DELETE_REQUEST',
      message: '${removed.programName} delete request published to ${_topics.scheduleRequest}.',
      success: true,
    );
  }

  void _querySchedules() {
    if (!_gateway.isConnected) {
      return;
    }
    _gateway.publishJson(
      _topics.scheduleRequest,
      <String, dynamic>{
        'requestId': _newRequestId(),
        'robotCode': robotId,
        'action': 'QUERY',
        'operator': _session?.username ?? 'remote-app',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'data': <String, dynamic>{},
      },
      qos: MqttDelivery.atLeastOnce,
    );
  }

  void _handleInboundMessage(MqttInboundMessage event) {
    if (event.topic == _topics.status) {
      _handleStatus(event.payload);
      return;
    }
    if (event.topic == _topics.telemetry) {
      _handleTelemetry(event.payload);
      return;
    }
    if (event.topic == _topics.fault || event.topic == _topics.systemAlert()) {
      _handleFault(event.payload, sourceTopic: event.topic);
      return;
    }
    if (event.topic == _topics.heartbeat) {
      _handleHeartbeat(event.payload);
      return;
    }
    if (event.topic == _topics.authority) {
      _handleAuthority(event.payload);
      return;
    }
    if (event.topic == _topics.jointResponse) {
      _handleJointResponse(event.payload);
      return;
    }
    if (event.topic == _topics.scheduleList) {
      _handleScheduleList(event.payload);
      return;
    }
    if (event.topic == _topics.scheduleResponse) {
      _handleScheduleResponse(event.payload);
      return;
    }
    if (event.topic == _topics.scheduleExecution) {
      _handleScheduleExecution(event.payload);
    }
  }

  void _handleStatus(Map<String, dynamic> json) {
    _robotState = _robotState.copyWith(
      robotId: json['robotCode']?.toString() ?? _robotState.robotId,
      robotName: json['robotName']?.toString() ?? _robotState.robotName,
      mode: _parseMode(json['mode']?.toString()),
      connectionStatus: json['online'] == true ? ConnectionStatus.online : ConnectionStatus.offline,
      lastUpdate: DateTime.tryParse(json['timestamp']?.toString() ?? '') ?? DateTime.now(),
      authority: RobotAuthority.fromWireValue(json['authority']?.toString()),
      robotStateLabel: json['state']?.toString(),
      faultActive: json['faultActive'] == true,
      runningProgramId: json['currentProgramId']?.toString() ?? json['programId']?.toString(),
      clearAlert: json['faultActive'] != true,
    );
    _robotController.add(_robotState);
  }

  void _handleTelemetry(Map<String, dynamic> json) {
    final jointsRaw = json['joints'] ?? json['jointAngles'];
    final joints = jointsRaw is List
        ? jointsRaw.whereType<num>().map((e) => e.toDouble()).toList(growable: false)
        : _robotState.jointAngles;
    _robotState = _robotState.copyWith(
      jointAngles: joints,
      heartbeat: (json['heartbeatCounter'] as num?)?.toInt() ?? (json['heartbeat'] as num?)?.toInt(),
      latencyMs: (json['latencyMs'] as num?)?.toInt() ?? (json['latency'] as num?)?.toInt(),
      lastUpdate: DateTime.tryParse(json['timestamp']?.toString() ?? '') ?? DateTime.now(),
      connectionStatus: ConnectionStatus.online,
    );
    _robotController.add(_robotState);
  }

  void _handleFault(Map<String, dynamic> json, {required String sourceTopic}) {
    final alert = AlertLog(
      timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ?? DateTime.now(),
      level: json['severity']?.toString() ?? (sourceTopic == _topics.systemAlert() ? 'SYSTEM' : 'WARN'),
      message: [
        if (json['faultCode'] != null || json['code'] != null) '[${json['faultCode'] ?? json['code']}]',
        json['message']?.toString() ?? 'Unknown fault',
      ].join(' '),
    );
    _alertLogs.insert(0, alert);
    _robotState = _robotState.copyWith(
      alertMessage: alert.message,
      lastUpdate: alert.timestamp,
      faultActive: json['active'] != false,
    );
    _robotController.add(_robotState);
  }

  void _handleHeartbeat(Map<String, dynamic> json) {
    _robotState = _robotState.copyWith(
      connectionStatus: ConnectionStatus.online,
      heartbeat: (json['seq'] as num?)?.toInt() ?? (json['heartbeat'] as num?)?.toInt() ?? (json['count'] as num?)?.toInt(),
      lastUpdate: DateTime.tryParse(json['timestamp']?.toString() ?? '') ?? DateTime.now(),
    );
    _robotController.add(_robotState);
  }

  void _handleAuthority(Map<String, dynamic> json) {
    final authority = RobotAuthority.fromWireValue(
      json['authority']?.toString() ?? json['state']?.toString() ?? json['value']?.toString(),
    );
    _robotState = _robotState.copyWith(
      authority: authority,
      lastUpdate: DateTime.tryParse(json['timestamp']?.toString() ?? '') ?? DateTime.now(),
    );
    _robotController.add(_robotState);
  }

  void _handleJointResponse(Map<String, dynamic> json) {
    final accepted = json['accepted'] == true || json['success'] == true;
    final jointRef = json['jointId']?.toString() ?? 'POSE';
    final timestamp = DateTime.tryParse(json['timestamp']?.toString() ?? '') ?? DateTime.now();
    final message = json['message']?.toString() ?? (accepted ? 'Joint pose accepted.' : 'Joint pose rejected.');

    _logAction(
      username: 'mini_pc',
      commandType: 'JOINT_CONTROL_RESPONSE',
      message: '[$jointRef] $message',
      success: accepted,
      timestamp: timestamp,
    );

    if (!accepted) {
      _robotState = _robotState.copyWith(
        alertMessage: message,
        lastUpdate: timestamp,
      );
      _robotController.add(_robotState);
      return;
    }

    final jointsRaw = json['joints'] ?? json['jointAngles'];
    if (jointsRaw is List) {
      final nextJoints = jointsRaw.whereType<num>().map((e) => e.toDouble()).toList(growable: false);
      if (nextJoints.length == 6) {
        _robotState = _robotState.copyWith(
          jointAngles: nextJoints,
          lastUpdate: timestamp,
          connectionStatus: ConnectionStatus.online,
          clearAlert: true,
        );
        _robotController.add(_robotState);
        return;
      }
    }

    _robotState = _robotState.copyWith(
      lastUpdate: timestamp,
      connectionStatus: ConnectionStatus.online,
      clearAlert: true,
    );
    _robotController.add(_robotState);
  }

  void _handleScheduleList(Map<String, dynamic> json) {
    final raw = json['schedules'];
    if (raw is! List) {
      return;
    }
    _schedules
      ..clear()
      ..addAll(
        raw
            .whereType<Map>()
            .map((item) => ScheduleDefinition.fromJson(item.cast<String, dynamic>()))
            .toList(growable: false),
      );

    _logAction(
      username: 'mini_pc',
      commandType: 'SCHEDULE_LIST_SYNC',
      message: 'Received ${_schedules.length} schedule(s) from ${_topics.scheduleList}.',
      success: true,
      timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  void _handleScheduleResponse(Map<String, dynamic> json) {
    final accepted = json['accepted'] == true;
    final action = json['action']?.toString().toUpperCase() ?? 'UNKNOWN';
    final timestamp = DateTime.tryParse(json['timestamp']?.toString() ?? '') ?? DateTime.now();
    final data = json['data'];
    final code = json['code']?.toString() ?? (accepted ? 'OK' : 'ERROR');
    final message = json['message']?.toString() ?? 'Schedule response received.';

    if (data is Map) {
      final payload = data.cast<String, dynamic>();
      final schedulePayload = payload['schedule'];
      if (schedulePayload is Map) {
        final schedule = ScheduleDefinition.fromJson(schedulePayload.cast<String, dynamic>());
        final index = _schedules.indexWhere((item) => item.id == schedule.id || item.requestId == schedule.requestId);
        if (action == 'DELETE') {
          if (index != -1) {
            _schedules.removeAt(index);
          }
        } else if (index == -1) {
          _schedules.insert(0, schedule);
        } else {
          _schedules[index] = schedule;
        }
      } else if (payload['scheduleId'] != null && action == 'DELETE') {
        _schedules.removeWhere((item) => item.id == payload['scheduleId']?.toString());
      }
    }

    _logAction(
      username: 'mini_pc',
      commandType: 'SCHEDULE_${action}_RESPONSE',
      message: '[$code] $message',
      success: accepted,
      timestamp: timestamp,
    );
  }

  void _handleScheduleExecution(Map<String, dynamic> json) {
    final status = json['status']?.toString().toUpperCase() ?? 'UNKNOWN';
    final timestamp = DateTime.tryParse(json['timestamp']?.toString() ?? '') ?? DateTime.now();
    _logAction(
      username: 'mini_pc',
      commandType: 'SCHEDULE_EXEC_$status',
      message: 'Program ${json['programId'] ?? '-'} for schedule ${json['scheduleId'] ?? '-'} is $status.',
      success: status != 'FAILED',
      timestamp: timestamp,
    );

    if (status == 'FAILED') {
      _robotState = _robotState.copyWith(
        alertMessage: json['message']?.toString() ?? json['reason']?.toString() ?? 'Schedule execution failed.',
        lastUpdate: timestamp,
        faultActive: true,
      );
      _robotController.add(_robotState);
    }
  }

  RobotMode _parseMode(String? value) {
    switch (value?.toUpperCase()) {
      case 'AUTO':
        return RobotMode.auto;
      default:
        return RobotMode.manual;
    }
  }

  void _ensurePlanner(UserSession session, String action) {
    if (!session.role.canPlanScenario) {
      throw Exception('Tài khoản ${session.role.label} không có quyền $action.');
    }
    if (!_gateway.isConnected) {
      throw Exception('MQTT chưa kết nối tới broker.');
    }
  }

  void _ensureJointOperator(UserSession session, String action) {
    if (!session.role.canControlJoints) {
      throw Exception('Tài khoản ${session.role.label} không có quyền $action.');
    }
    if (!_gateway.isConnected) {
      throw Exception('MQTT chưa kết nối tới broker.');
    }
  }

  void _ensureRemoteJointControlAvailable() {
    if (_robotState.authority == RobotAuthority.localOperator) {
      throw Exception('Robot đang ở authority LOCAL_OPERATOR. Remote app chưa thể điều khiển 6 joint lúc này.');
    }
    if (_robotState.authority == RobotAuthority.maintenance) {
      throw Exception('Robot đang ở authority MAINTENANCE. Không thể gửi lệnh joint.');
    }
    if (_robotState.authority == RobotAuthority.locked) {
      throw Exception('Robot đang bị LOCKED. Không thể gửi lệnh joint.');
    }
  }

  void _ensureRemoteSchedulingAvailable() {
    if (_robotState.authority == RobotAuthority.localOperator) {
      throw Exception('Robot đang ở authority LOCAL_OPERATOR. Remote app chỉ được quan sát và chưa thể lập lịch lúc này.');
    }
    if (_robotState.authority == RobotAuthority.maintenance) {
      throw Exception('Robot đang ở authority MAINTENANCE. Không thể gửi schedule request.');
    }
    if (_robotState.authority == RobotAuthority.locked) {
      throw Exception('Robot đang bị LOCKED. Không thể gửi schedule request.');
    }
  }


  String _resolveJointId(int jointIndex) {
    if (jointIndex < 0 || jointIndex >= 6) {
      throw Exception('Joint index không hợp lệ. Hệ thống chỉ hỗ trợ J1 đến J6.');
    }
    return 'J${jointIndex + 1}';
  }

  void _publishJointControl({
    required UserSession session,
    required Map<String, dynamic> payload,
    required String commandType,
    required String successMessage,
  }) {
    _gateway.publishJson(
      _topics.jointRequest,
      payload,
      qos: MqttDelivery.atLeastOnce,
    );

    _logAction(
      username: session.username,
      commandType: commandType,
      message: successMessage,
      success: true,
    );
  }

  void _logAction({
    required String username,
    required String commandType,
    required String message,
    required bool success,
    DateTime? timestamp,
  }) {
    _commandLogs.insert(
      0,
      CommandLog(
        timestamp: timestamp ?? DateTime.now(),
        username: username,
        commandType: commandType,
        message: message,
        success: success,
      ),
    );
  }

  String _newRequestId() => 'req-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(9999)}';

  void _seedPrograms() {
    _programs.add(
      ProgramDefinition(
        id: 'P1',
        name: 'Program 1',
        description: 'Pick and place demo program',
        defaultDelayMs: 1000,
        commands: const <ProgramCommand>[
          ProgramCommand(
            id: 'C1',
            commandType: ProgramCommandType.moveJoints,
            jointAngles: <double>[0, 20, 10, 90, 0, 0],
            speed: 40,
            delayAfterMs: 1000,
            note: 'Home-like pose',
          ),
          ProgramCommand(
            id: 'C2',
            commandType: ProgramCommandType.moveJoints,
            jointAngles: <double>[10, 35, 10, 80, 15, 5],
            speed: 35,
            delayAfterMs: 1000,
            note: 'Approach pose',
          ),
          ProgramCommand(
            id: 'C3',
            commandType: ProgramCommandType.moveJoints,
            jointAngles: <double>[15, 40, -15, 75, 20, 10],
            speed: 30,
            delayAfterMs: 1000,
            note: 'Pick pose',
          ),
        ],
      ),
    );
  }

  @override
  Future<void> dispose() async {
    await _mqttSubscription?.cancel();
    await _gateway.dispose();
    await _robotController.close();
  }
}
