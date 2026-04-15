import 'dart:async';
import 'dart:convert';
import 'package:best_flutter_ui_templates/models/user_role.dart';
import 'package:flutter/foundation.dart';

import '../models/alert_log.dart';
import '../models/command_log.dart';
import '../models/program_command.dart';
import '../models/program_definition.dart';
import '../models/robot_state.dart';
import '../models/schedule_definition.dart';
import '../models/user_session.dart';
import '../services/robot_gateway_service.dart';

class AppController extends ChangeNotifier {
  AppController({required RobotGatewayService service}) : _service = service;

  final RobotGatewayService _service;

  final ValueNotifier<UserSession?> sessionNotifier = ValueNotifier<UserSession?>(null);
  final ValueNotifier<RobotState?> robotStateNotifier = ValueNotifier<RobotState?>(null);

  List<CommandLog> commandLogs = const <CommandLog>[];
  List<AlertLog> alertLogs = const <AlertLog>[];
  List<UserSession> users = const <UserSession>[];
  List<ProgramDefinition> programs = const <ProgramDefinition>[];
  List<ScheduleDefinition> schedules = const <ScheduleDefinition>[];

  String? selectedProgramId;
  DateTime? selectedScheduleTime;
  bool showAdvancedJson = false;

  String draftProgramId = 'draft';
  String draftProgramName = 'Program 1';
  String draftProgramDescription = 'Pick and place demo program';
  int draftDefaultDelayMs = 1000;
  List<ProgramCommand> draftCommands = <ProgramCommand>[];

  bool initializing = true;
  bool busy = false;
  String? errorMessage;

  StreamSubscription<RobotState>? _subscription;

  UserSession? get session => sessionNotifier.value;
  RobotState? get robotState => robotStateNotifier.value;
  bool get canManageUsers => session?.role.canManageUsers == true;
  bool get canSchedule => session?.role.canPlanScenario == true;
  bool get canControlJoints => session?.role.canControlJoints == true;
  bool get isViewerOnly => session?.role.isViewerOnly == true;

  ProgramDefinition? get selectedProgram {
    if (selectedProgramId == null) return null;
    for (final item in programs) {
      if (item.id == selectedProgramId) return item;
    }
    return null;
  }

  int get estimatedRuntimeMs {
    var total = 0;
    for (final command in draftCommands) {
      total += command.delayAfterMs;
    }
    return total;
  }

  String get generatedProgramJson {
    final program = ProgramDefinition(
      id: draftProgramId,
      name: draftProgramName,
      description: draftProgramDescription,
      commands: draftCommands,
      defaultDelayMs: draftDefaultDelayMs,
    );
    return const JsonEncoder.withIndent('  ').convert(program.toJson());
  }

  Future<void> initialize() async {
    initializing = false;
    notifyListeners();
  }

  Future<void> login(String username, String password) async {
    await _guard(() async {
      final nextSession = await _service.login(username: username, password: password);
      sessionNotifier.value = nextSession;
      robotStateNotifier.value = await _service.loadInitialRobotState();
      await _loadSupportData();
      _primeDraft();

      await _subscription?.cancel();
      _subscription = _service.robotStateStream().listen((state) {
        robotStateNotifier.value = state;
      });
    });
  }

  Future<void> logout() async {
    for (final timer in _jointRepeatTimers.values) {
      timer.cancel();
    }
    _jointRepeatTimers.clear();
    await _service.logout();
    await _subscription?.cancel();
    _subscription = null;

    sessionNotifier.value = null;
    robotStateNotifier.value = null;
    commandLogs = const <CommandLog>[];
    alertLogs = const <AlertLog>[];
    users = const <UserSession>[];
    programs = const <ProgramDefinition>[];
    schedules = const <ScheduleDefinition>[];
    selectedProgramId = null;
    selectedScheduleTime = null;
    errorMessage = null;
    _resetDraft();
    notifyListeners();
  }

  Future<void> refreshAll() async => _guard(_loadSupportData);

  Future<void> refreshLogs() async {
    commandLogs = await _service.fetchCommandLogs();
    alertLogs = await _service.fetchAlertLogs();
    notifyListeners();
  }

  void selectProgram(String? programId) {
    selectedProgramId = programId;
    if (programId == null) {
      notifyListeners();
      return;
    }
    final program = programs.firstWhere((item) => item.id == programId);
    loadProgramToDraft(program);
  }

  void loadProgramToDraft(ProgramDefinition program) {
    draftProgramId = program.id;
    draftProgramName = program.name;
    draftProgramDescription = program.description;
    draftDefaultDelayMs = program.defaultDelayMs;
    draftCommands = program.commands.map((e) => e.copyWith()).toList(growable: true);
    selectedProgramId = program.id;
    notifyListeners();
  }

  void startNewProgramDraft() {
    draftProgramId = 'draft-${DateTime.now().millisecondsSinceEpoch}';
    draftProgramName = 'New Program';
    draftProgramDescription = '';
    draftDefaultDelayMs = 1000;
    draftCommands = <ProgramCommand>[];
    selectedProgramId = null;
    notifyListeners();
  }

  void updateDraftProgramMeta({String? name, String? description, int? defaultDelayMs}) {
    if (name != null) draftProgramName = name;
    if (description != null) draftProgramDescription = description;
    if (defaultDelayMs != null) draftDefaultDelayMs = defaultDelayMs;
    notifyListeners();
  }

  void selectScheduleTime(DateTime value) {
    selectedScheduleTime = value;
    notifyListeners();
  }

  void toggleAdvancedJson() {
    showAdvancedJson = !showAdvancedJson;
    notifyListeners();
  }

  void addCommand(ProgramCommand command) {
    draftCommands = <ProgramCommand>[...draftCommands, command];
    notifyListeners();
  }

  void updateCommand(String commandId, ProgramCommand next) {
    draftCommands = draftCommands.map((item) => item.id == commandId ? next : item).toList(growable: false);
    notifyListeners();
  }

  void duplicateCommand(String commandId) {
    final index = draftCommands.indexWhere((item) => item.id == commandId);
    if (index == -1) return;
    final source = draftCommands[index];
    final duplicate = source.copyWith(id: _generateCommandId());
    final next = List<ProgramCommand>.from(draftCommands);
    next.insert(index + 1, duplicate);
    draftCommands = next;
    notifyListeners();
  }

  void removeCommand(String commandId) {
    draftCommands = draftCommands.where((item) => item.id != commandId).toList(growable: false);
    notifyListeners();
  }

  void moveCommandUp(String commandId) {
    final index = draftCommands.indexWhere((item) => item.id == commandId);
    if (index <= 0) return;
    final next = List<ProgramCommand>.from(draftCommands);
    final item = next.removeAt(index);
    next.insert(index - 1, item);
    draftCommands = next;
    notifyListeners();
  }

  void moveCommandDown(String commandId) {
    final index = draftCommands.indexWhere((item) => item.id == commandId);
    if (index == -1 || index >= draftCommands.length - 1) return;
    final next = List<ProgramCommand>.from(draftCommands);
    final item = next.removeAt(index);
    next.insert(index + 1, item);
    draftCommands = next;
    notifyListeners();
  }

  Future<void> saveDraftProgram() async {
    final activeSession = session;
    if (activeSession == null) return;
    _validateDraft();

    await _guard(() async {
      final saved = await _service.saveProgram(
        session: activeSession,
        program: ProgramDefinition(
          id: draftProgramId,
          name: draftProgramName.trim(),
          description: draftProgramDescription.trim(),
          commands: draftCommands,
          defaultDelayMs: draftDefaultDelayMs,
        ),
      );

      programs = await _service.fetchPrograms();
      commandLogs = await _service.fetchCommandLogs();
      loadProgramToDraft(saved);
    });
  }

  Future<void> deleteSelectedProgram() async {
    final activeSession = session;
    final program = selectedProgram;
    if (activeSession == null || program == null) return;

    await _guard(() async {
      await _service.deleteProgram(session: activeSession, programId: program.id);
      programs = await _service.fetchPrograms();
      commandLogs = await _service.fetchCommandLogs();
      if (programs.isNotEmpty) {
        loadProgramToDraft(programs.first);
      } else {
        startNewProgramDraft();
      }
    });
  }



  final Map<int, Timer> _jointRepeatTimers = <int, Timer>{};

  Future<void> moveJoint(int jointIndex, {double stepDeg = 5}) async {
    final activeSession = session;
    final currentState = robotState;
    if (activeSession == null || currentState == null) return;

    final nextJoints = List<double>.from(currentState.jointAngles);
    if (jointIndex < 0 || jointIndex >= nextJoints.length) return;
    nextJoints[jointIndex] = nextJoints[jointIndex] + stepDeg;

    robotStateNotifier.value = currentState.copyWith(
      jointAngles: nextJoints,
      lastUpdate: DateTime.now(),
    );

    try {
      await _service.sendJointCommand(
        session: activeSession,
        targetJoints: nextJoints,
        changedJointIndex: jointIndex,
        stepDeg: stepDeg,
      );
      commandLogs = await _service.fetchCommandLogs();
      errorMessage = null;
      notifyListeners();
    } catch (error) {
      robotStateNotifier.value = currentState;
      errorMessage = error.toString().replaceFirst('Exception: ', '');
      notifyListeners();
    }
  }

  void startContinuousJointMove(int jointIndex, {required double direction, double stepDeg = 1}) {
    stopContinuousJointMove(jointIndex);
    moveJoint(jointIndex, stepDeg: direction >= 0 ? stepDeg : -stepDeg);
    _jointRepeatTimers[jointIndex] = Timer.periodic(const Duration(milliseconds: 140), (_) {
      moveJoint(jointIndex, stepDeg: direction >= 0 ? stepDeg : -stepDeg);
    });
  }

  void stopContinuousJointMove(int jointIndex) {
    _jointRepeatTimers.remove(jointIndex)?.cancel();
  }

  Future<void> createSchedule() async {
    final activeSession = session;
    final scheduledAt = selectedScheduleTime;
    if (activeSession == null) return;
    _validateDraft();

    if (scheduledAt == null) {
      errorMessage = 'Vui lòng chọn ngày giờ chạy.';
      notifyListeners();
      return;
    }

    if (scheduledAt.isBefore(DateTime.now())) {
      errorMessage = 'Ngày giờ chạy phải ở tương lai.';
      notifyListeners();
      return;
    }

    await _guard(() async {
      final program = ProgramDefinition(
        id: selectedProgramId ?? draftProgramId,
        name: draftProgramName.trim(),
        description: draftProgramDescription.trim(),
        commands: draftCommands,
        defaultDelayMs: draftDefaultDelayMs,
      );

      await _service.createSchedule(
        session: activeSession,
        program: program,
        scheduledAt: scheduledAt,
      );

      schedules = await _service.fetchSchedules();
      commandLogs = await _service.fetchCommandLogs();
      selectedScheduleTime = null;
      notifyListeners();
    });
  }

  Future<void> toggleSchedule(String scheduleId, bool enabled) async {
    final activeSession = session;
    if (activeSession == null) return;

    await _guard(() async {
      await _service.setScheduleEnabled(session: activeSession, scheduleId: scheduleId, enabled: enabled);
      schedules = await _service.fetchSchedules();
      commandLogs = await _service.fetchCommandLogs();
      notifyListeners();
    });
  }

  Future<void> deleteSchedule(String scheduleId) async {
    final activeSession = session;
    if (activeSession == null) return;

    await _guard(() async {
      await _service.deleteSchedule(session: activeSession, scheduleId: scheduleId);
      schedules = await _service.fetchSchedules();
      commandLogs = await _service.fetchCommandLogs();
      notifyListeners();
    });
  }

  Future<void> _loadSupportData() async {
    commandLogs = await _service.fetchCommandLogs();
    alertLogs = await _service.fetchAlertLogs();
    users = await _service.fetchUsers();
    programs = await _service.fetchPrograms();
    schedules = await _service.fetchSchedules();
    notifyListeners();
  }

  void _primeDraft() {
    if (programs.isNotEmpty) {
      loadProgramToDraft(programs.first);
    } else {
      _resetDraft();
    }
  }

  void _validateDraft() {
    if (draftProgramName.trim().isEmpty) {
      throw Exception('Tên chương trình không được để trống.');
    }
    if (draftCommands.isEmpty) {
      throw Exception('Cần ít nhất 1 command trong program.');
    }
    for (final command in draftCommands) {
      if (command.commandType == ProgramCommandType.moveJoints && command.jointAngles.length != 6) {
        throw Exception('MOVE_JOINTS phải có đúng 6 joint.');
      }
    }
  }

  Future<void> _guard(Future<void> Function() action) async {
    busy = true;
    errorMessage = null;
    notifyListeners();
    try {
      await action();
    } catch (error) {
      errorMessage = error.toString().replaceFirst('Exception: ', '');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  String _generateCommandId() => 'CMD-${DateTime.now().microsecondsSinceEpoch}';

  void _resetDraft() {
    draftProgramId = 'draft';
    draftProgramName = 'Program 1';
    draftProgramDescription = 'Pick and place demo program';
    draftDefaultDelayMs = 1000;
    draftCommands = <ProgramCommand>[];
  }

  @override
  void dispose() {
    for (final timer in _jointRepeatTimers.values) {
      timer.cancel();
    }
    _jointRepeatTimers.clear();
    _subscription?.cancel();
    sessionNotifier.dispose();
    robotStateNotifier.dispose();
    _service.dispose();
    super.dispose();
  }
}
