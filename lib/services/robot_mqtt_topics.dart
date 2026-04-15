class RobotMqttTopics {
  const RobotMqttTopics(
    this.robotCode, {
    this.namespace = 'robot',
    this.version = 'v1',
    this.site = 'default',
  });

  final String robotCode;
  final String namespace;
  final String version;
  final String site;

  String get _base => '$namespace/$version/$site/$robotCode';

  String get status => '$_base/robot/status';
  String get telemetry => '$_base/robot/telemetry';
  String get fault => '$_base/robot/fault';
  String get heartbeat => '$_base/robot/heartbeat';
  String get authority => '$_base/robot/authority';
  String get robotEvent => '$_base/robot/event';

  String get jointRequest => '$_base/robot/joint/request';
  String get jointResponse => '$_base/robot/joint/response';

  String get scheduleRequest => '$_base/schedule/request';
  String get scheduleResponse => '$_base/schedule/response';
  String get scheduleList => '$_base/schedule/list';
  String get scheduleExecution => '$_base/schedule/execution';

  String get topicSummary => '$_base/{robot|schedule}/...';

  String systemAlert({String channel = 'alert'}) => '$namespace/$version/system/$channel';
}
