import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../core/app_theme.dart';
import '../models/robot_mode.dart';
import '../models/user_role.dart';
import 'widgets/app_card.dart';
import 'widgets/info_tile.dart';
import 'widgets/robot_3d_panel.dart';
import 'widgets/status_pill.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final session = controller.session;
    if (session == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return ValueListenableBuilder(
      valueListenable: controller.robotStateNotifier,
      builder: (context, robot, _) {
        if (robot == null) {
          return const Center(child: CircularProgressIndicator());
        }

        final statusColor = switch (robot.connectionStatus) {
          ConnectionStatus.online => AppTheme.success,
          ConnectionStatus.offline => AppTheme.danger,
          ConnectionStatus.connecting => AppTheme.warning,
        };

        if (controller.isViewerOnly) {
          return RefreshIndicator(
            onRefresh: controller.refreshAll,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('3D Viewer Mode', style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 8),
                      Text(
                        'Tài khoản Viewer chỉ được quan sát mô hình 3D của robot. Các chức năng điều khiển 6 joint và lập lịch đã bị khóa.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          StatusPill(label: robot.connectionStatus.label, color: statusColor),
                          StatusPill(label: 'Role: ${session.role.label}', color: AppTheme.primary),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Robot3DPanel(joints: robot.jointAngles),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: controller.refreshAll,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        Text(robot.robotName, style: Theme.of(context).textTheme.headlineSmall),
                        StatusPill(label: robot.connectionStatus.label, color: statusColor),
                        StatusPill(
                          label: 'Mode: ${robot.mode.label}',
                          color: robot.mode == RobotMode.manual ? AppTheme.secondary : AppTheme.warning,
                        ),
                        StatusPill(
                          label: 'Authority: ${robot.authority.label}',
                          color: robot.authority.canAcceptRemoteSchedule ? AppTheme.success : AppTheme.warning,
                        ),
                        StatusPill(label: 'Role: ${session.role.label}', color: AppTheme.primary),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(child: InfoTile(label: 'Robot ID', value: robot.robotId, icon: Icons.precision_manufacturing)),
                        const SizedBox(width: 12),
                        Expanded(child: InfoTile(label: 'Last Update', value: robot.lastUpdate.toLocal().toString(), icon: Icons.schedule)),
                        const SizedBox(width: 12),
                        Expanded(child: InfoTile(label: 'Robot State', value: robot.robotStateLabel ?? '-', icon: Icons.memory_outlined)),
                      ],
                    ),
                    if (robot.alertMessage != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.danger.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: AppTheme.danger),
                            const SizedBox(width: 12),
                            Expanded(child: Text(robot.alertMessage!)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final splitLayout = constraints.maxWidth > 980;
                  if (!splitLayout) {
                    return Column(
                      children: [
                        Robot3DPanel(joints: robot.jointAngles),
                        const SizedBox(height: 16),
                        _PendantControlPanel(controller: controller, jointAngles: robot.jointAngles, role: session.role),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 6, child: Robot3DPanel(joints: robot.jointAngles)),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 5,
                        child: _PendantControlPanel(
                          controller: controller,
                          jointAngles: robot.jointAngles,
                          role: session.role,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Schedule Template Summary', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(controller.draftProgramName, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(
                      '${controller.draftCommands.length} command(s) • default delay ${controller.draftDefaultDelayMs} ms',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PendantControlPanel extends StatelessWidget {
  const _PendantControlPanel({
    required this.controller,
    required this.jointAngles,
    required this.role,
  });

  final AppController controller;
  final List<double> jointAngles;
  final UserRole role;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(0),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            colors: [Color(0xFF223041), Color(0xFF131B24)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.gamepad_rounded, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          'Teach Pendant',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  _PendantIndicator(
                    icon: Icons.emergency_share_outlined,
                    label: controller.canControlJoints ? 'REMOTE ENABLED' : 'LOCKED',
                    color: controller.canControlJoints ? AppTheme.success : AppTheme.danger,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Tap để tăng/giảm 5°. Giữ nút để auto-repeat 2°. Mỗi lần thay đổi, app publish toàn bộ pose 6 joint và cập nhật 3D ngay.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Column(
                  children: [
                    _PendantReadoutRow(label: 'User Role', value: role.label),
                    const SizedBox(height: 8),
                    _PendantReadoutRow(label: 'Mode', value: controller.robotState?.mode.label ?? '-'),
                    const SizedBox(height: 8),
                    _PendantReadoutRow(label: 'Authority', value: controller.robotState?.authority.label ?? '-'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              for (var index = 0; index < 6; index++) ...[
                _JointPendantRow(
                  jointIndex: index,
                  currentAngle: index < jointAngles.length ? jointAngles[index] : 0,
                  enabled: controller.canControlJoints,
                  onStepNegative: () => controller.moveJoint(index, stepDeg: -1),
                  onStepPositive: () => controller.moveJoint(index, stepDeg: 1),
                  onHoldNegativeStart: () => controller.startContinuousJointMove(index, direction: -1),
                  onHoldPositiveStart: () => controller.startContinuousJointMove(index, direction: 1),
                  onHoldStop: () => controller.stopContinuousJointMove(index),
                ),
                if (index != 5) const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _JointPendantRow extends StatelessWidget {
  const _JointPendantRow({
    required this.jointIndex,
    required this.currentAngle,
    required this.enabled,
    required this.onStepNegative,
    required this.onStepPositive,
    required this.onHoldNegativeStart,
    required this.onHoldPositiveStart,
    required this.onHoldStop,
  });

  final int jointIndex;
  final double currentAngle;
  final bool enabled;
  final VoidCallback onStepNegative;
  final VoidCallback onStepPositive;
  final VoidCallback onHoldNegativeStart;
  final VoidCallback onHoldPositiveStart;
  final VoidCallback onHoldStop;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'J${jointIndex + 1}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${currentAngle.toStringAsFixed(1)}°',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: _JogButton(
                    label: '-',
                    hint: 'NEG',
                    enabled: enabled,
                    onTap: onStepNegative,
                    onLongPressStart: onHoldNegativeStart,
                    onLongPressEnd: onHoldStop,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _JogButton(
                    label: '+',
                    hint: 'POS',
                    enabled: enabled,
                    onTap: onStepPositive,
                    onLongPressStart: onHoldPositiveStart,
                    onLongPressEnd: onHoldStop,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _JogButton extends StatelessWidget {
  const _JogButton({
    required this.label,
    required this.hint,
    required this.enabled,
    required this.onTap,
    required this.onLongPressStart,
    required this.onLongPressEnd,
  });

  final String label;
  final String hint;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onLongPressStart;
  final VoidCallback onLongPressEnd;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        onLongPressStart: enabled ? (_) => onLongPressStart() : null,
        onLongPressEnd: enabled ? (_) => onLongPressEnd() : null,
        onLongPressCancel: enabled ? onLongPressEnd : null,
        child: Container(
          height: 72,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: enabled ? Colors.white.withOpacity(0.10) : Colors.white.withOpacity(0.04),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.14),
                      blurRadius: 14,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  hint,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white60,
                        letterSpacing: 1.2,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PendantIndicator extends StatelessWidget {
  const _PendantIndicator({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _PendantReadoutRow extends StatelessWidget {
  const _PendantReadoutRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white60),
          ),
        ),
        const SizedBox(width: 16),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white),
        ),
      ],
    );
  }
}
