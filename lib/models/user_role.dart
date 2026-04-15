enum UserRole {
  admin,
  operator,
  viewer;

  String get label {
    switch (this) {
      case UserRole.admin:
        return 'Admin';
      case UserRole.operator:
        return 'Operator';
      case UserRole.viewer:
        return 'Viewer';
    }
  }

  bool get canViewStatus => true;

  bool get canViewLogs => this != UserRole.viewer;

  bool get canViewAlerts => this != UserRole.viewer;

  bool get canPlanScenario =>
      this == UserRole.admin || this == UserRole.operator;

  bool get canControlJoints =>
      this == UserRole.admin || this == UserRole.operator;

  bool get canManageUsers => this == UserRole.admin;

  bool get isViewerOnly => this == UserRole.viewer;
}
