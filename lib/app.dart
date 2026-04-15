import 'package:flutter/material.dart';

import 'controllers/app_controller.dart';
import 'core/app_config.dart';
import 'core/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/navigation_shell.dart';
import 'services/mqtt_gateway_service.dart';
import 'services/robot_gateway_service.dart';

class DensoRc5App extends StatefulWidget {
  const DensoRc5App({super.key});

  @override
  State<DensoRc5App> createState() => _DensoRc5AppState();
}

class _DensoRc5AppState extends State<DensoRc5App> {
  late final AppController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AppController(
      service: MqttRobotGatewayService(
        gateway: MqttGatewayService(config: AppConfig.brokerConfig),
        robotId: AppConfig.defaultRobotId,
      ),
    )..initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: _controller.sessionNotifier,
      builder: (context, session, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'DENSO RC5 Remote Supervisor',
          theme: AppTheme.lightTheme,
          home: session == null
              ? LoginScreen(controller: _controller)
              : NavigationShell(controller: _controller),
        );
      },
    );
  }
}
