from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()


def _env(key: str, default: str) -> str:
    return os.getenv(key, default)


def _env_int(key: str, default: int) -> int:
    return int(os.getenv(key, str(default)))


def _env_float(key: str, default: float) -> float:
    return float(os.getenv(key, str(default)))


def _env_bool(key: str, default: bool) -> bool:
    raw = os.getenv(key)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def _env_json(key: str, default: dict[str, str]) -> dict[str, str]:
    raw = os.getenv(key)
    if not raw:
        return default.copy()
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return default.copy()
    if not isinstance(data, dict):
        return default.copy()
    return {str(k).strip().lower(): str(v) for k, v in data.items()}


def _default_allowed_tokens() -> dict[str, str]:
    return _env_json(
        "ALLOWED_TOKENS_JSON",
        {
            "admin": "CHANGE_ME_ADMIN_TOKEN",
            "operator": "CHANGE_ME_OPERATOR_TOKEN",
            "viewer": "CHANGE_ME_VIEWER_TOKEN",
        },
    )


@dataclass(frozen=True)
class Settings:
    mqtt_host: str = _env("MQTT_HOST", "localhost")
    mqtt_port: int = _env_int("MQTT_PORT", 1883)
    mqtt_username: str = _env("MQTT_USERNAME", "")
    mqtt_password: str = _env("MQTT_PASSWORD", "")
    mqtt_client_id: str = _env("MQTT_CLIENT_ID", "minipc-rb001")
    mqtt_keepalive: int = _env_int("MQTT_KEEPALIVE", 30)
    mqtt_clean_session: bool = _env_bool("MQTT_CLEAN_SESSION", False)
    mqtt_use_tls: bool = _env_bool("MQTT_USE_TLS", False)
    mqtt_schema_version: str = _env("MQTT_SCHEMA_VERSION", "1.1")
    mqtt_namespace: str = _env("MQTT_NAMESPACE", "robot/v1")
    mqtt_site: str = _env("MQTT_SITE", "default")

    robot_code: str = _env("ROBOT_CODE", "RB001")
    default_authority: str = _env("DEFAULT_AUTHORITY", "REMOTE_SCHEDULER")
    default_mode: str = _env("DEFAULT_MODE", "AUTO")

    uart_port: str = _env("UART_PORT", "COM10")
    uart_baudrate: int = _env_int("UART_BAUDRATE", 115200)
    uart_bytesize: int = _env_int("UART_BYTESIZE", 8)
    uart_parity: str = _env("UART_PARITY", "N")
    uart_stopbits: int = _env_int("UART_STOPBITS", 1)
    uart_timeout_sec: float = _env_float("UART_TIMEOUT_SEC", 0.1)
    uart_write_timeout_sec: float = _env_float("UART_WRITE_TIMEOUT_SEC", 1.0)
    uart_reconnect_sec: float = _env_float("UART_RECONNECT_SEC", 2.0)
    uart_protocol: str = _env("UART_PROTOCOL", "csv6")
    uart_newline: str = _env("UART_NEWLINE", "\r")

    request_cache_ttl_sec: int = _env_int("REQUEST_CACHE_TTL_SEC", 300)
    command_ack_timeout_sec: float = _env_float("COMMAND_ACK_TIMEOUT_SEC", 2.0)
    program_done_timeout_sec: float = _env_float("PROGRAM_DONE_TIMEOUT_SEC", 180.0)
    telemetry_publish_min_interval_sec: float = _env_float("TELEMETRY_PUBLISH_MIN_INTERVAL_SEC", 0.1)
    status_publish_interval_sec: float = _env_float("STATUS_PUBLISH_INTERVAL_SEC", 5.0)
    heartbeat_interval_sec: float = _env_float("HEARTBEAT_INTERVAL_SEC", 5.0)
    authority_publish_interval_sec: float = _env_float("AUTHORITY_PUBLISH_INTERVAL_SEC", 5.0)
    online_timeout_sec: float = _env_float("ONLINE_TIMEOUT_SEC", 3.0)
    joint_command_lease_sec: float = _env_float("JOINT_COMMAND_LEASE_SEC", 0.8)

    # Scheduler tuned for robots that stream pose telemetry but do not emit ACK/DONE.
    schedule_position_tolerance_deg: float = _env_float("SCHEDULE_POSITION_TOLERANCE_DEG", 1.0)
    schedule_settle_time_sec: float = _env_float("SCHEDULE_SETTLE_TIME_SEC", 0.8)
    schedule_motion_detect_timeout_sec: float = _env_float("SCHEDULE_MOTION_DETECT_TIMEOUT_SEC", 2.5)
    schedule_execution_timeout_sec: float = _env_float("SCHEDULE_EXECUTION_TIMEOUT_SEC", 30.0)
    scheduler_misfire_grace_sec: int = _env_int("SCHEDULER_MISFIRE_GRACE_SEC", 30)
    scheduler_max_lateness_sec: float = _env_float("SCHEDULER_MAX_LATENESS_SEC", 5.0)
    schedule_retry_max_attempts: int = _env_int("SCHEDULE_RETRY_MAX_ATTEMPTS", 2)
    schedule_retry_backoff_sec: float = _env_float("SCHEDULE_RETRY_BACKOFF_SEC", 0.5)
    telemetry_max_jump_deg: float = _env_float("TELEMETRY_MAX_JUMP_DEG", 45.0)

    schedule_db_path: str = _env("SCHEDULE_DB_PATH", "data/schedules.json")
    request_cache_path: str = _env("REQUEST_CACHE_PATH", "data/request_cache.json")
    program_registry_path: str = _env("PROGRAM_REGISTRY_PATH", "programs/program_registry.json")
    joint_target_cache_path: str = _env("JOINT_TARGET_CACHE_PATH", "data/joint_target_cache.json")

    log_level: str = _env("LOG_LEVEL", "INFO")
    log_raw_uart: bool = _env_bool("LOG_RAW_UART", False)

    joint_limit_min_deg: float = _env_float("JOINT_LIMIT_MIN_DEG", -180.0)
    joint_limit_max_deg: float = _env_float("JOINT_LIMIT_MAX_DEG", 180.0)
    manual_step_max_deg: float = _env_float("MANUAL_STEP_MAX_DEG", 5.0)
    allowed_tokens: dict[str, str] = field(default_factory=_default_allowed_tokens)

    @property
    def project_root(self) -> Path:
        return Path(__file__).resolve().parents[2]


settings = Settings()
