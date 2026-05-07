from __future__ import annotations

import threading
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any

from app.config.settings import settings
from app.models.enums import Authority, RobotMode
from app.utils.time_utils import iso_utc_now, utc_now


@dataclass
class RobotStateStore:
    online: bool = False
    mode: str = settings.default_mode
    state: str = 'IDLE'
    fault_active: bool = False
    fault_code: str | None = None
    fault_severity: str | None = None
    fault_message: str | None = None
    joints: list[float] = field(default_factory=lambda: [0.0] * 6)
    heartbeat_counter: int = 0
    latency_ms: int = 0
    authority: str = settings.default_authority
    authority_reason: str = 'Remote scheduling is allowed.'
    schedule_allowed: bool = True
    current_program_id: str | None = None
    current_schedule_id: str | None = None
    last_feedback_iso: str | None = None
    busy: bool = False
    current_operation: str = 'IDLE'
    operation_source: str | None = None
    operation_started_at: str | None = None
    operation_expires_at: str | None = None
    operation_details: dict[str, Any] | None = None
    auto_pick_state: str = 'IDLE'
    auto_pick_message: str = 'Auto-pick is idle.'

    def __post_init__(self) -> None:
        self._lock = threading.Lock()
        self._sync_authority_with_mode()

    def update_from_feedback(self, feedback: dict[str, Any]) -> None:
        with self._lock:
            if 'joints' in feedback:
                joints = [float(v) for v in feedback['joints']]
                if len(joints) == 6:
                    self.joints = joints
            if 'state' in feedback and feedback['state'] is not None:
                self.state = str(feedback['state'])
            if 'mode' in feedback and feedback['mode'] is not None:
                self.mode = str(feedback['mode'])
            if 'faultActive' in feedback:
                self.fault_active = bool(feedback['faultActive'])
            if 'faultCode' in feedback:
                self.fault_code = feedback['faultCode']
            if 'severity' in feedback:
                self.fault_severity = feedback['severity']
            if 'message' in feedback:
                self.fault_message = feedback['message']
            if 'latencyMs' in feedback and feedback['latencyMs'] is not None:
                self.latency_ms = int(feedback['latencyMs'])
            self.online = True
            self.last_feedback_iso = iso_utc_now()

    def mark_running(self, program_id: str, schedule_id: str) -> None:
        with self._lock:
            self.state = 'RUNNING'
            self.current_program_id = program_id
            self.current_schedule_id = schedule_id

    def mark_idle(self) -> None:
        with self._lock:
            self.state = 'IDLE'
            self.current_program_id = None
            self.current_schedule_id = None

    def mark_fault(self, code: str | None, message: str) -> None:
        with self._lock:
            self.state = 'FAULT'
            self.fault_active = True
            self.fault_code = code
            self.fault_message = message

    def increment_heartbeat(self) -> None:
        with self._lock:
            self.heartbeat_counter += 1

    def refresh_online_state(self) -> None:
        with self._lock:
            if not self.last_feedback_iso:
                self.online = False
                return
            last_dt = datetime.fromisoformat(self.last_feedback_iso.replace('Z', '+00:00'))
            age = (utc_now() - last_dt).total_seconds()
            self.online = age <= settings.online_timeout_sec

    def note_uart_activity(self) -> None:
        with self._lock:
            self.last_feedback_iso = iso_utc_now()
            self.online = True

    def is_schedule_authority_available(self) -> tuple[bool, str]:
        if self.authority != Authority.REMOTE_SCHEDULER.value:
            return False, self.authority_reason
        if not self.schedule_allowed:
            return False, self.authority_reason
        return True, 'OK'

    def is_joint_authority_available(self) -> tuple[bool, str]:
        if self.authority != Authority.REMOTE_JOINT_CONTROL.value:
            return False, self.authority_reason
        return True, 'OK'

    def is_schedule_allowed(self) -> tuple[bool, str]:
        with self._lock:
            allowed, reason = self.is_schedule_authority_available()
            if not allowed:
                return False, reason
            if self.busy and self.current_operation not in {'IDLE', 'SCHEDULE_EXECUTION'}:
                return False, f'Robot đang bận bởi {self.current_operation}.'
            if str(self.mode).upper() != RobotMode.AUTO.value:
                return False, 'Remote schedule chỉ được phép khi robot ở AUTO.'
            return True, 'OK'

    def is_joint_control_allowed(self) -> tuple[bool, str]:
        with self._lock:
            allowed, reason = self.is_joint_authority_available()
            if not allowed:
                return False, reason
            if self.busy and self.current_operation not in {'IDLE', 'REMOTE_JOINT_CONTROL'}:
                return False, f'Robot đang bận bởi {self.current_operation}.'
            if str(self.mode).upper() != RobotMode.MANUAL.value:
                return False, 'Remote joint control chỉ được phép khi robot ở MANUAL.'
            if self.fault_active:
                return False, self.fault_message or 'Robot đang FAULT.'
            return True, 'OK'

    def is_auto_pick_allowed(self) -> tuple[bool, str]:
        with self._lock:
            allowed, reason = self.is_schedule_authority_available()
            if not allowed:
                return False, reason
            if self.busy and self.current_operation not in {'IDLE', 'AUTO_PICK'}:
                return False, f'Robot đang bận bởi {self.current_operation}.'
            if str(self.mode).upper() != RobotMode.AUTO.value:
                return False, 'Auto-pick chỉ được phép khi robot ở AUTO.'
            if self.fault_active:
                return False, self.fault_message or 'Robot đang FAULT.'
            return True, 'OK'

    def set_authority(self, authority: str, allowed: bool, reason: str) -> None:
        with self._lock:
            self.authority = authority
            self.schedule_allowed = allowed
            self.authority_reason = reason

    def set_mode(self, mode: str) -> None:
        with self._lock:
            self.mode = str(mode).upper()
            self._sync_authority_with_mode()


    def _sync_authority_with_mode(self) -> None:
        mode = str(self.mode).upper()
        if mode == RobotMode.MANUAL.value:
            self.authority = Authority.REMOTE_JOINT_CONTROL.value
            self.schedule_allowed = False
            self.authority_reason = 'Remote manual control is allowed.'
        elif mode == RobotMode.AUTO.value:
            self.authority = Authority.REMOTE_SCHEDULER.value
            self.schedule_allowed = True
            self.authority_reason = 'Remote scheduling is allowed.'

    def set_operation(self, *, busy: bool, current_operation: str, source: str | None, started_at: str | None, expires_at: str | None, details: dict[str, Any] | None = None) -> None:
        with self._lock:
            self.busy = busy
            self.current_operation = current_operation
            self.operation_source = source
            self.operation_started_at = started_at
            self.operation_expires_at = expires_at
            self.operation_details = details


    def current_joints(self) -> list[float]:
        with self._lock:
            return list(self.joints)

    def current_fault(self) -> tuple[bool, str | None, str | None]:
        with self._lock:
            return self.fault_active, self.fault_code, self.fault_message

    def clear_fault(self) -> None:
        with self._lock:
            self.fault_active = False
            self.fault_code = None
            self.fault_severity = None
            self.fault_message = None

    def set_auto_pick_state(self, state: str, message: str) -> None:
        with self._lock:
            self.auto_pick_state = state
            self.auto_pick_message = message

    def status_payload(self, robot_code: str) -> dict[str, Any]:
        with self._lock:
            return {
                'robotCode': robot_code,
                'online': self.online,
                'mode': self.mode,
                'state': self.state,
                'faultActive': self.fault_active,
                'currentProgramId': self.current_program_id,
                'currentScheduleId': self.current_schedule_id,
                'busy': self.busy,
                'currentOperation': self.current_operation,
                'operationSource': self.operation_source,
                'operationStartedAt': self.operation_started_at,
                'operationExpiresAt': self.operation_expires_at,
                'autoPickState': self.auto_pick_state,
                'autoPickMessage': self.auto_pick_message,
                'timestamp': iso_utc_now(),
            }

    def telemetry_payload(self, robot_code: str) -> dict[str, Any]:
        with self._lock:
            return {
                'robotCode': robot_code,
                'joints': list(self.joints),
                'heartbeatCounter': self.heartbeat_counter,
                'latencyMs': self.latency_ms,
                'busy': self.busy,
                'currentOperation': self.current_operation,
                'autoPickState': self.auto_pick_state,
                'timestamp': iso_utc_now(),
            }

    def fault_payload(self, robot_code: str) -> dict[str, Any]:
        with self._lock:
            return {
                'robotCode': robot_code,
                'faultCode': self.fault_code,
                'severity': self.fault_severity,
                'message': self.fault_message,
                'active': self.fault_active,
                'timestamp': iso_utc_now(),
            }

    def heartbeat_payload(self, robot_code: str) -> dict[str, Any]:
        with self._lock:
            return {
                'robotCode': robot_code,
                'alive': self.online,
                'seq': self.heartbeat_counter,
                'timestamp': iso_utc_now(),
            }

    def authority_payload(self, robot_code: str) -> dict[str, Any]:
        with self._lock:
            return {
                'robotCode': robot_code,
                'authority': self.authority,
                'scheduleAllowed': self.schedule_allowed,
                'reason': self.authority_reason,
                'busy': self.busy,
                'currentOperation': self.current_operation,
                'operationSource': self.operation_source,
                'autoPickState': self.auto_pick_state,
                'autoPickMessage': self.auto_pick_message,
                'timestamp': iso_utc_now(),
            }
