import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../models/user_role.dart';
import 'admin/user_management_screen.dart';
import 'dashboard_screen.dart';
import 'history/alert_history_screen.dart';
import 'history/command_history_screen.dart';
import 'schedules_screen.dart';

class NavigationShell extends StatefulWidget {
  const NavigationShell({super.key, required this.controller});

  final AppController controller;

  @override
  State<NavigationShell> createState() => _NavigationShellState();
}

class _NavigationShellState extends State<NavigationShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final session = widget.controller.session!;

    final pages = <Widget>[DashboardScreen(controller: widget.controller)];
    final destinations = <NavigationDestination>[
      const NavigationDestination(icon: Icon(Icons.space_dashboard_outlined), label: 'Dashboard'),
    ];

    if (!session.role.isViewerOnly) {
      pages.add(SchedulesScreen(controller: widget.controller));
      destinations.add(const NavigationDestination(icon: Icon(Icons.schedule_outlined), label: 'Schedules'));

      pages.add(CommandHistoryScreen(controller: widget.controller));
      destinations.add(const NavigationDestination(icon: Icon(Icons.history_outlined), label: 'Logs'));

      pages.add(AlertHistoryScreen(controller: widget.controller));
      destinations.add(const NavigationDestination(icon: Icon(Icons.warning_amber_outlined), label: 'Alerts'));
    }

    if (session.role == UserRole.admin) {
      pages.add(UserManagementScreen(controller: widget.controller));
      destinations.add(const NavigationDestination(icon: Icon(Icons.admin_panel_settings_outlined), label: 'Users'));
    }

    if (_index >= pages.length) {
      _index = 0;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('DENSO RC5 Remote Supervisor'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: widget.controller.refreshAll,
            icon: const Icon(Icons.refresh),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: widget.controller.logout,
              icon: const Icon(Icons.logout),
              label: const Text('Đăng xuất'),
            ),
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        destinations: destinations,
        onDestinationSelected: (value) => setState(() => _index = value),
      ),
    );
  }
}
