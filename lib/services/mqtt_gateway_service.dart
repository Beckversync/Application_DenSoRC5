import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MqttBrokerConfig {
  const MqttBrokerConfig({
    required this.host,
    required this.port,
    required this.useTls,
    required this.keepAliveSeconds,
    required this.commandQos,
    required this.telemetryQos,
    required this.clientIdPrefix,
    required this.username,
    required this.password,
  });

  final String host;
  final int port;
  final bool useTls;
  final int keepAliveSeconds;
  final MqttDelivery commandQos;
  final MqttDelivery telemetryQos;
  final String clientIdPrefix;
  final String username;
  final String password;
}

enum MqttDelivery { atMostOnce, atLeastOnce, exactlyOnce }

extension on MqttDelivery {
  MqttQos get qos {
    switch (this) {
      case MqttDelivery.atMostOnce:
        return MqttQos.atMostOnce;
      case MqttDelivery.atLeastOnce:
        return MqttQos.atLeastOnce;
      case MqttDelivery.exactlyOnce:
        return MqttQos.exactlyOnce;
    }
  }
}

class MqttInboundMessage {
  const MqttInboundMessage({required this.topic, required this.payload});

  final String topic;
  final Map<String, dynamic> payload;
}

class MqttGatewayService {
  MqttGatewayService({required this.config});

  final MqttBrokerConfig config;
  final StreamController<MqttInboundMessage> _messages = StreamController<MqttInboundMessage>.broadcast();
  final Map<String, MqttDelivery> _subscriptions = <String, MqttDelivery>{};

  MqttServerClient? _client;
  StreamSubscription? _updatesSubscription;

  Stream<MqttInboundMessage> get messages => _messages.stream;
  bool get isConnected => _client?.connectionStatus?.state == MqttConnectionState.connected;

  Future<void> connect() async {
    if (isConnected) return;

    final clientId = '${config.clientIdPrefix}-${DateTime.now().millisecondsSinceEpoch}';
    debugPrint('MQTT: connecting to ${config.host}:${config.port} with clientId=$clientId');

    final client = MqttServerClient(config.host, clientId)
      ..port = config.port
      ..secure = config.useTls
      ..autoReconnect = true
      ..resubscribeOnAutoReconnect = false
      ..keepAlivePeriod = config.keepAliveSeconds
      ..logging(on: false)
      ..onConnected = _handleConnected
      ..onAutoReconnect = _handleAutoReconnect
      ..onAutoReconnected = _handleAutoReconnected
      ..onDisconnected = _handleDisconnect
      ..pongCallback = _handlePong;

    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .authenticateAs(config.username, config.password)
        .keepAliveFor(config.keepAliveSeconds)
        .withWillQos(config.commandQos.qos)
        .startClean();

    _client = client;

    try {
      await client.connect();
    } catch (error, stackTrace) {
      debugPrint('MQTT ERROR: connect failed: $error');
      debugPrint('$stackTrace');
      client.disconnect();
      rethrow;
    }

    final state = client.connectionStatus?.state;
    final returnCode = client.connectionStatus?.returnCode;
    debugPrint('MQTT: connect returned with state=$state, returnCode=$returnCode');

    if (state != MqttConnectionState.connected) {
      throw Exception('MQTT connection failed: state=$state returnCode=$returnCode');
    }

    await _updatesSubscription?.cancel();
    _updatesSubscription = client.updates?.listen(_handleUpdates);
    _resubscribeAll();
  }

  void subscribe(String topic, {MqttDelivery qos = MqttDelivery.atLeastOnce}) {
    _subscriptions[topic] = qos;
    if (!isConnected) return;
    debugPrint('MQTT: subscribing to $topic qos=${qos.name}');
    _client!.subscribe(topic, qos.qos);
    debugPrint('MQTT: subscribed to $topic');
  }

  void unsubscribe(String topic) {
    _subscriptions.remove(topic);
    if (!isConnected) return;
    _client!.unsubscribe(topic);
    debugPrint('MQTT: unsubscribed from $topic');
  }

  void publishJson(String topic, Map<String, dynamic> payload, {MqttDelivery qos = MqttDelivery.atLeastOnce}) {
    if (!isConnected) {
      throw Exception('MQTT chưa kết nối tới broker.');
    }

    final text = jsonEncode(payload);
    final builder = MqttClientPayloadBuilder()..addString(text);
    _client!.publishMessage(topic, qos.qos, builder.payload!);
    debugPrint('MQTT: published to $topic payload=$text');
  }

  Future<void> disconnect() async {
    await _updatesSubscription?.cancel();
    _updatesSubscription = null;
    _client?.disconnect();
    _client = null;
  }

  void _handleUpdates(List<MqttReceivedMessage<MqttMessage?>>? events) {
    if (events == null) return;
    for (final event in events) {
      final publish = event.payload as MqttPublishMessage;
      final payloadString = MqttPublishPayload.bytesToStringAsString(publish.payload.message);
      debugPrint('MQTT: message received on ${event.topic} payload=$payloadString');
      try {
        final map = jsonDecode(payloadString);
        if (map is Map<String, dynamic>) {
          _messages.add(MqttInboundMessage(topic: event.topic, payload: map));
        } else if (map is Map) {
          _messages.add(MqttInboundMessage(topic: event.topic, payload: map.cast<String, dynamic>()));
        }
      } catch (error) {
        debugPrint('MQTT: ignore non-JSON payload on ${event.topic}: $error');
      }
    }
  }

  void _resubscribeAll() {
    if (!isConnected) return;
    for (final entry in _subscriptions.entries) {
      debugPrint('MQTT: resubscribing to ${entry.key}');
      _client!.subscribe(entry.key, entry.value.qos);
    }
  }

  void _handleConnected() {
    debugPrint('MQTT: onConnected fired.');
  }

  void _handleDisconnect() {
    debugPrint('MQTT: onDisconnected fired.');
  }

  void _handleAutoReconnect() {
    debugPrint('MQTT: auto reconnect started.');
  }

  void _handleAutoReconnected() {
    debugPrint('MQTT: auto reconnect completed.');
    _resubscribeAll();
  }

  void _handlePong() {
    debugPrint('MQTT: ping response received.');
  }

  Future<void> dispose() async {
    await disconnect();
    await _messages.close();
  }
}
