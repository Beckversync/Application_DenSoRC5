enum RobotAuthority {
  localOperator,
  remoteSchedule,
  maintenance,
  locked,
  unknown;

  String get label {
    switch (this) {
      case RobotAuthority.localOperator:
        return 'Local Operator';
      case RobotAuthority.remoteSchedule:
        return 'Remote Scheduler';
      case RobotAuthority.maintenance:
        return 'Maintenance';
      case RobotAuthority.locked:
        return 'Locked';
      case RobotAuthority.unknown:
        return 'Unknown';
    }
  }

  bool get canAcceptRemoteSchedule => this == RobotAuthority.remoteSchedule;

  static RobotAuthority fromWireValue(String? value) {
    switch (value?.trim().toUpperCase()) {
      case 'LOCAL_OPERATOR':
        return RobotAuthority.localOperator;
      case 'REMOTE_SCENARIO':
      case 'REMOTE_SCHEDULE':
      case 'REMOTE_SCHEDULER':
        return RobotAuthority.remoteSchedule;
      case 'MAINTENANCE':
        return RobotAuthority.maintenance;
      case 'LOCKED':
        return RobotAuthority.locked;
      default:
        return RobotAuthority.unknown;
    }
  }

  String get wireValue {
    switch (this) {
      case RobotAuthority.localOperator:
        return 'LOCAL_OPERATOR';
      case RobotAuthority.remoteSchedule:
        return 'REMOTE_SCHEDULER';
      case RobotAuthority.maintenance:
        return 'MAINTENANCE';
      case RobotAuthority.locked:
        return 'LOCKED';
      case RobotAuthority.unknown:
        return 'UNKNOWN';
    }
  }
}
