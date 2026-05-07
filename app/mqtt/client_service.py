from __future__ import annotations

import json
import logging
import threading
from collections.abc import Callable
from typing import Any

import paho.mqtt.client as mqtt

logger = logging.getLogger(__name__)
MessageHandler = Callable[[str, dict[str, Any]], None]


class MqttClientService:
    """MQTT transport wrapper with subscription replay and JSON dispatch."""

    def __init__(
        self,
        host: str,
        port: int,
        username: str,
        password: str,
        client_id: str,
        keepalive: int,
        clean_session: bool = False,
        use_tls: bool = False,
    ) -> None:
        self._host = host
        self._port = port
        self._client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id=client_id, clean_session=clean_session)
        if username:
            self._client.username_pw_set(username, password)
        if use_tls:
            self._client.tls_set()
        self._client.on_connect = self._on_connect
        self._client.on_disconnect = self._on_disconnect
        self._client.on_message = self._on_message
        self._client.on_publish = self._on_publish
        self._keepalive = keepalive
        self._handlers: list[MessageHandler] = []
        self._subscriptions: dict[str, int] = {}
        self._connected = threading.Event()

    def add_handler(self, handler: MessageHandler) -> None:
        self._handlers.append(handler)

    def connect(self) -> None:
        logger.info('MQTT connecting to %s:%s', self._host, self._port)
        self._client.connect(self._host, self._port, keepalive=self._keepalive)
        self._client.loop_start()

    def disconnect(self) -> None:
        self._client.loop_stop()
        self._client.disconnect()

    def subscribe(self, topic: str, qos: int = 1) -> None:
        self._subscriptions[topic] = qos
        self._client.subscribe(topic, qos=qos)
        logger.info('MQTT subscribed topic=%s qos=%s', topic, qos)

    def publish(self, topic: str, payload: dict[str, Any], qos: int = 1, retain: bool = False) -> None:
        body = json.dumps(payload, separators=(',', ':'), ensure_ascii=False)
        info = self._client.publish(topic, body, qos=qos, retain=retain)
        if info.rc != mqtt.MQTT_ERR_SUCCESS:
            logger.error('MQTT publish failed topic=%s rc=%s', topic, info.rc)
        logger.info('MQTT published topic=%s payload=%s', topic, body)

    def _on_connect(self, client, userdata, flags, reason_code, properties) -> None:
        logger.info('MQTT connected rc=%s', reason_code)
        self._connected.set()
        for topic, qos in self._subscriptions.items():
            self._client.subscribe(topic, qos=qos)
            logger.info('MQTT resubscribed topic=%s qos=%s', topic, qos)

    def _on_disconnect(self, client, userdata, flags, reason_code, properties=None) -> None:
        logger.warning('MQTT disconnected rc=%s', reason_code)
        self._connected.clear()

    def _on_publish(self, client, userdata, mid, reason_code, properties=None) -> None:
        return None

    def _on_message(self, client, userdata, msg) -> None:
        try:
            payload = json.loads(msg.payload.decode('utf-8'))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            logger.exception('MQTT invalid JSON topic=%s: %s', msg.topic, exc)
            return
        logger.info('MQTT received topic=%s payload=%s', msg.topic, json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
        for handler in list(self._handlers):
            handler(msg.topic, payload)
