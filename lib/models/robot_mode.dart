enum RobotMode { manual, auto }

enum ConnectionStatus { online, offline, connecting }

extension RobotModeX on RobotMode {
  String get label => this == RobotMode.manual ? 'Manual' : 'Auto';
}

extension ConnectionStatusX on ConnectionStatus {
  String get label {
    switch (this) {
      case ConnectionStatus.online:
        return 'Online';
      case ConnectionStatus.offline:
        return 'Offline';
      case ConnectionStatus.connecting:
        return 'Connecting';
    }
  }
}
