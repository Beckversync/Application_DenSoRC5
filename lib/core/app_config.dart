import '../services/mqtt_gateway_service.dart';

class AppConfig {
  AppConfig._();

  static const String mqttNamespace = 'robot';
  static const String mqttSchemaVersion = 'v1';
  static const String mqttSite = 'default';
  static const String defaultRobotId = 'RB001';

  static const MqttBrokerConfig brokerConfig = MqttBrokerConfig(
    host: 'mqtt.abcsolutions.com.vn',
    port: 1883,
    useTls: false,
    keepAliveSeconds: 20,
    commandQos: MqttDelivery.atLeastOnce,
    telemetryQos: MqttDelivery.atLeastOnce,
    clientIdPrefix: 'robot-remote-app',
    username: 'abcsolution',
    password: 'CseLAbC5c6',
  );
}
