from __future__ import annotations

import logging
import threading
import time
from typing import Any
from uuid import uuid4

from dateutil.parser import isoparse

from app.automation.auto_pick_manager import AutoPickManager
from app.config.settings import settings
from app.coordination.operation_manager import OperationManager
from app.coordination.operation_policy import OperationPriority
from app.models.enums import ExecutionStatus, ScheduleAction
from app.models.schedule_models import ScheduleEntry, ScheduleRequest
from app.models.topics import TopicBuilder
from app.mqtt.client_service import MqttClientService
from app.robot.executor import RobotExecutor
from app.robot.execution_state_machine import ExecutionState, RobotExecutionStateMachine
from app.robot.protocol_factory import build_protocol
from app.robot.state_store import RobotStateStore
from app.robot.uart_client import UartClient
from app.scheduler.manager import ScheduleManager
from app.storage.joint_target_store import JointTargetStore
from app.storage.program_registry import ProgramRegistry
from app.storage.request_cache import RequestCache
from app.storage.schedule_store import ScheduleStore
from app.utils.time_utils import iso_utc_now, utc_now
from app.security_access import AccessControl
from app.validation.joints import parse_six_joint_values, validate_manual_joint_values

logger = logging.getLogger(__name__)


class MiniPcService:
    """Main composition root for Mini PC robot orchestration.

    Wires MQTT, UART, scheduling, robot state storage, and operation arbitration.
    Domain rules that can be tested independently are delegated to smaller
    helpers such as AccessControl and joint validators.
    """

    def __init__(self) -> None:
        self.topics = TopicBuilder(settings.mqtt_namespace, settings.mqtt_site, settings.robot_code)
        self.state = RobotStateStore()
        self.protocol = build_protocol()
        self.uart = UartClient(self._handle_uart_line)
        self.executor = RobotExecutor(self.uart, self.protocol)
        self.mqtt = MqttClientService(
            host=settings.mqtt_host,
            port=settings.mqtt_port,
            username=settings.mqtt_username,
            password=settings.mqtt_password,
            client_id=settings.mqtt_client_id,
            keepalive=settings.mqtt_keepalive,
            clean_session=settings.mqtt_clean_session,
            use_tls=settings.mqtt_use_tls,
        )
        self.mqtt.add_handler(self._handle_mqtt_message)
        self.schedule_store = ScheduleStore(settings.schedule_db_path)
        self.request_cache = RequestCache(settings.request_cache_path, settings.request_cache_ttl_sec)
        self.program_registry = ProgramRegistry(settings.program_registry_path)
        self.joint_target_store = JointTargetStore(settings.joint_target_cache_path)
        self.scheduler = ScheduleManager(self._execute_schedule)
        self.operation_manager = OperationManager()
        self.execution_fsm = RobotExecutionStateMachine()
        self.auto_pick = AutoPickManager(self._on_auto_pick_state_change)
        self._stop = threading.Event()
        self._periodic_threads: list[threading.Thread] = []
        self._last_telemetry_publish_monotonic = 0.0

    def start_forever(self) -> None:
        self.scheduler.start()
        for item in self.schedule_store.list():
            self.scheduler.upsert(item)
        self.mqtt.subscribe(self.topics.schedule_request, qos=1)
        self.mqtt.subscribe(self.topics.robot_joint_request, qos=1)
        self.mqtt.subscribe(self.topics.robot_mode_request, qos=1)
        self.mqtt.subscribe(self.topics.robot_auto_pick_request, qos=1)
        self.mqtt.connect()
        self.uart.start()
        self.publish_initial_state()
        self._start_periodic(self._heartbeat_loop)
        self._start_periodic(self._status_loop)
        self._start_periodic(self._authority_loop)
        try:
            while True:
                time.sleep(0.5)
        except KeyboardInterrupt:
            logger.info('Service stopping by keyboard interrupt')
        finally:
            self.shutdown()

    def shutdown(self) -> None:
        self._stop.set()
        self.scheduler.shutdown()
        self.uart.stop()
        self.mqtt.disconnect()

    def publish_initial_state(self) -> None:
        self.publish_status()
        self.publish_fault()
        self.publish_authority()
        self._sync_operation_state()
        self.publish_operation_status()
        self.publish_schedule_list(None)
        cached = self.joint_target_store.get_joints()
        if cached is not None:
            self.state.update_from_feedback({'joints': cached})
            self.publish_telemetry()

    def publish_status(self) -> None:
        self.state.refresh_online_state()
        payload = self.state.status_payload(settings.robot_code)
        payload['authority'] = self.state.authority
        payload['schemaVersion'] = settings.mqtt_schema_version
        payload['uartConnected'] = self.uart.is_ready
        self.mqtt.publish(self.topics.robot_status, payload, qos=1, retain=True)

    def publish_fault(self) -> None:
        payload = self.state.fault_payload(settings.robot_code)
        payload['schemaVersion'] = settings.mqtt_schema_version
        self.mqtt.publish(self.topics.robot_fault, payload, qos=1, retain=True)

    def publish_authority(self) -> None:
        payload = self.state.authority_payload(settings.robot_code)
        payload['schemaVersion'] = settings.mqtt_schema_version
        self.mqtt.publish(self.topics.robot_authority, payload, qos=1, retain=True)

    def publish_operation_status(self) -> None:
        payload = {
            'robotCode': settings.robot_code,
            'schemaVersion': settings.mqtt_schema_version,
            **self.operation_manager.snapshot(),
            **self.execution_fsm.snapshot(),
            'autoPick': self.auto_pick.status(),
            'uartConnected': self.uart.is_ready,
            'timestamp': iso_utc_now(),
        }
        self.mqtt.publish(self.topics.robot_operation_status, payload, qos=1, retain=True)

    def publish_auto_pick_response(self, request_id: str | None, accepted: bool, code: str, message: str, action: str, data: dict[str, Any] | None = None) -> None:
        payload = {
            'requestId': request_id,
            'robotCode': settings.robot_code,
            'schemaVersion': settings.mqtt_schema_version,
            'accepted': accepted,
            'code': code,
            'message': message,
            'action': action,
            'data': data or self.auto_pick.status(),
            'timestamp': iso_utc_now(),
        }
        self._cache_if_request(request_id, payload)
        self.mqtt.publish(self.topics.robot_auto_pick_response, payload, qos=1, retain=False)

    def publish_auto_pick_event(self, event_type: str, message: str) -> None:
        payload = {
            'eventId': f'auto-pick-{uuid4().hex[:8]}',
            'robotCode': settings.robot_code,
            'schemaVersion': settings.mqtt_schema_version,
            'eventType': event_type,
            'message': message,
            'data': self.auto_pick.status(),
            'timestamp': iso_utc_now(),
        }
        self.mqtt.publish(self.topics.robot_auto_pick_event, payload, qos=1, retain=False)

    def publish_heartbeat(self) -> None:
        self.state.refresh_online_state()
        self.state.increment_heartbeat()
        payload = self.state.heartbeat_payload(settings.robot_code)
        payload['schemaVersion'] = settings.mqtt_schema_version
        payload['uartConnected'] = self.uart.is_ready
        self.mqtt.publish(self.topics.robot_heartbeat, payload, qos=0, retain=False)

    def publish_telemetry(self) -> None:
        payload = self.state.telemetry_payload(settings.robot_code)
        payload['schemaVersion'] = settings.mqtt_schema_version
        self.mqtt.publish(self.topics.robot_telemetry, payload, qos=0, retain=True)

    def publish_schedule_list(self, request_id: str | None) -> None:
        payload = {
            'robotCode': settings.robot_code,
            'schemaVersion': settings.mqtt_schema_version,
            'requestId': request_id,
            'schedules': [item.to_dict() for item in self.schedule_store.list()],
            'timestamp': iso_utc_now(),
        }
        self.mqtt.publish(self.topics.schedule_list, payload, qos=1, retain=True)

    def publish_schedule_response(
        self,
        request: ScheduleRequest,
        accepted: bool,
        code: str,
        message: str,
        data: dict[str, Any] | None = None,
    ) -> None:
        payload = {
            'requestId': request.requestId,
            'robotCode': settings.robot_code,
            'schemaVersion': settings.mqtt_schema_version,
            'action': request.action,
            'accepted': accepted,
            'code': code,
            'message': message,
            'data': data,
            'timestamp': iso_utc_now(),
        }
        self.request_cache.put(request.requestId, payload, payload['timestamp'])
        self.mqtt.publish(self.topics.schedule_response, payload, qos=1, retain=False)

    def publish_joint_response(
        self,
        request_id: str,
        accepted: bool,
        code: str,
        message: str,
        joints: list[float] | None = None,
        serial_command: str | None = None,
    ) -> None:
        payload = {
            'requestId': request_id,
            'robotCode': settings.robot_code,
            'schemaVersion': settings.mqtt_schema_version,
            'accepted': accepted,
            'code': code,
            'message': message,
            'joints': joints,
            'serialCommand': serial_command,
            'timestamp': iso_utc_now(),
        }
        self.request_cache.put(request_id, payload, payload['timestamp'])
        self.mqtt.publish(self.topics.robot_joint_response, payload, qos=1, retain=False)

    def publish_mode_response(self, request_id: str | None, accepted: bool, code: str, message: str, requested_mode: str | None = None) -> None:
        payload = {
            'requestId': request_id,
            'robotCode': settings.robot_code,
            'schemaVersion': settings.mqtt_schema_version,
            'accepted': accepted,
            'code': code,
            'message': message,
            'mode': self.state.mode,
            'requestedMode': requested_mode,
            'timestamp': iso_utc_now(),
        }
        if request_id:
            self.request_cache.put(request_id, payload, payload['timestamp'])
        self.mqtt.publish(self.topics.robot_mode_response, payload, qos=1, retain=False)

    def publish_schedule_execution(self, schedule_id: str, program_id: str, status: ExecutionStatus, message: str, reason_code: str | None = None) -> None:
        payload = {
            'eventId': f'exec-{schedule_id}-{status.value.lower()}-{uuid4().hex[:6]}',
            'robotCode': settings.robot_code,
            'schemaVersion': settings.mqtt_schema_version,
            'scheduleId': schedule_id,
            'programId': program_id,
            'status': status.value,
            'message': message,
            'reasonCode': reason_code,
            'timestamp': iso_utc_now(),
        }
        self.mqtt.publish(self.topics.schedule_execution, payload, qos=1, retain=False)

    def publish_robot_event(self, event_type: str, message: str, details: dict[str, Any] | None) -> None:
        payload = {
            'eventId': f'evt-{uuid4().hex[:8]}',
            'robotCode': settings.robot_code,
            'schemaVersion': settings.mqtt_schema_version,
            'eventType': event_type,
            'message': message,
            'details': details,
            'timestamp': iso_utc_now(),
        }
        self.mqtt.publish(self.topics.robot_event, payload, qos=1, retain=False)

    def _cache_if_request(self, request_id: str | None, payload: dict[str, Any]) -> None:
        if request_id:
            self.request_cache.put(request_id, payload, payload['timestamp'])

    def _start_periodic(self, target) -> None:
        thread = threading.Thread(target=target, daemon=True)
        thread.start()
        self._periodic_threads.append(thread)

    def _heartbeat_loop(self) -> None:
        while not self._stop.is_set():
            self.publish_heartbeat()
            time.sleep(settings.heartbeat_interval_sec)

    def _status_loop(self) -> None:
        while not self._stop.is_set():
            self._sync_operation_state()
            self.publish_status()
            time.sleep(settings.status_publish_interval_sec)

    def _authority_loop(self) -> None:
        while not self._stop.is_set():
            self._sync_operation_state()
            self.publish_authority()
            self.publish_operation_status()
            time.sleep(settings.authority_publish_interval_sec)

    def _handle_uart_line(self, line: str) -> None:
        self.state.note_uart_activity()
        feedback = self.protocol.try_parse_line(line)
        if feedback is None:
            return
        logger.info('UART parsed kind=%s payload=%s', feedback.kind, feedback.payload)
        self.executor.notify_feedback(feedback.kind, feedback.payload)

        if feedback.kind == 'raw':
            logger.debug('UART raw frame not mapped to state update payload=%s', feedback.payload)
            return

        if feedback.kind in {'telemetry', 'state', 'fault'}:
            normalized: dict[str, Any] = {}
            if feedback.kind == 'telemetry':
                normalized['joints'] = feedback.payload.get('joints')
                normalized['state'] = feedback.payload.get('state')
                normalized['mode'] = feedback.payload.get('mode')
                normalized['faultActive'] = feedback.payload.get('faultActive') or feedback.payload.get('fault') in {'1', 1, True}
                normalized['latencyMs'] = feedback.payload.get('latencyMs', 0)
            elif feedback.kind == 'state':
                normalized['state'] = feedback.payload.get('state')
                normalized['mode'] = feedback.payload.get('mode')
            elif feedback.kind == 'fault':
                normalized['faultActive'] = True
                normalized['faultCode'] = feedback.payload.get('faultCode')
                normalized['severity'] = feedback.payload.get('severity')
                normalized['message'] = feedback.payload.get('message') or feedback.payload.get('raw')
            if not self._is_feedback_plausible(normalized):
                self.state.mark_fault('INVALID_TELEMETRY', 'Rejected implausible robot telemetry frame.')
                self.publish_fault()
                self.publish_robot_event('INVALID_TELEMETRY', 'Robot telemetry failed plausibility validation.', {'payload': normalized})
                return
            self.state.update_from_feedback(normalized)
            now = time.monotonic()
            if now - self._last_telemetry_publish_monotonic >= settings.telemetry_publish_min_interval_sec:
                self.publish_telemetry()
                self._last_telemetry_publish_monotonic = now
            if feedback.kind == 'fault':
                self.publish_fault()
                self.publish_status()

    def _is_feedback_plausible(self, feedback: dict[str, Any]) -> bool:
        """Reject impossible robot feedback before it mutates system state.

        This is a defensive layer against firmware bugs or corrupted UART frames:
        the backend does not blindly trust telemetry. Joint values must be six
        finite numbers within configured limits and must not jump unrealistically
        between frames unless the previous state is unavailable.
        """

        raw_joints = feedback.get('joints')
        if raw_joints is None:
            return True
        try:
            joints = [float(v) for v in raw_joints]
        except (TypeError, ValueError):
            return False
        if len(joints) != 6:
            return False
        min_deg = settings.joint_limit_min_deg
        max_deg = settings.joint_limit_max_deg
        if any(value < min_deg or value > max_deg for value in joints):
            return False
        previous = self.state.current_joints()
        if len(previous) == 6:
            max_jump = max(abs(a - b) for a, b in zip(joints, previous))
            if max_jump > settings.telemetry_max_jump_deg:
                logger.warning('Rejected telemetry jump maxJumpDeg=%s joints=%s previous=%s', max_jump, joints, previous)
                return False
        return True

    def _handle_mqtt_message(self, topic: str, payload: dict[str, Any]) -> None:
        request_id = str(payload.get('requestId') or '')
        if request_id:
            cached = self.request_cache.get(request_id)
            if cached is not None:
                if topic == self.topics.schedule_request:
                    self.mqtt.publish(self.topics.schedule_response, cached, qos=1, retain=False)
                elif topic == self.topics.robot_joint_request:
                    self.mqtt.publish(self.topics.robot_joint_response, cached, qos=1, retain=False)
                elif topic == self.topics.robot_mode_request:
                    self.mqtt.publish(self.topics.robot_mode_response, cached, qos=1, retain=False)
                elif topic == self.topics.robot_auto_pick_request:
                    self.mqtt.publish(self.topics.robot_auto_pick_response, cached, qos=1, retain=False)
                return

        if topic == self.topics.robot_joint_request:
            self._handle_joint_request(payload)
            return
        if topic == self.topics.robot_mode_request:
            self._handle_mode_request(payload)
            return
        if topic == self.topics.robot_auto_pick_request:
            self._handle_auto_pick_request(payload)
            return
        if topic != self.topics.schedule_request:
            return
        request = ScheduleRequest.from_dict(payload)
        valid, reason = request.validate_basic()
        if not valid:
            logger.warning('Rejected invalid schedule request reason=%s payload=%s', reason, payload)
            return
        logger.info('Handle schedule request action=%s requestId=%s', request.action, request.requestId)
        self._process_schedule_request(request)

    def _handle_joint_request(self, payload: dict[str, Any]) -> None:
        request_id = str(payload.get('requestId', ''))
        robot_code = str(payload.get('robotCode', ''))
        if not request_id:
            logger.warning('Rejected joint request missing requestId payload=%s', payload)
            return
        if robot_code != settings.robot_code:
            self.publish_joint_response(request_id, False, 'INVALID_PAYLOAD', 'robotCode does not match target robot.')
            return
        if not AccessControl.is_token_valid(payload):
            self.publish_joint_response(request_id, False, 'AUTH_FAILED', 'Invalid operator token.')
            return
        parsed, joints, parse_reason = parse_six_joint_values(payload.get('joints'))
        if not parsed or joints is None:
            self.publish_joint_response(request_id, False, 'INVALID_PAYLOAD', parse_reason)
            return
        valid_joints, joint_reason = validate_manual_joint_values(joints, payload)
        if not valid_joints:
            self.publish_joint_response(request_id, False, 'INVALID_RANGE', joint_reason, joints=joints)
            return

        role = AccessControl.normalize_role(payload)
        if not AccessControl.can_control_joints(role):
            self.publish_joint_response(request_id, False, 'PERMISSION_DENIED', 'Chỉ Operator hoặc Admin mới được điều khiển joint.', joints=joints)
            return
        if not self.uart.is_ready:
            self.publish_joint_response(request_id, False, 'UART_NOT_READY', 'UART chưa sẵn sàng.', joints=joints)
            return

        allowed, reason = self.state.is_joint_control_allowed()
        if not allowed:
            self.publish_joint_response(request_id, False, 'AUTHORITY_DENIED', reason, joints=joints)
            return

        acquired, lock_reason = self.operation_manager.acquire(
            owner='REMOTE_JOINT_CONTROL',
            source='mqtt_joint_request',
            priority=OperationPriority.MANUAL,
            ttl_sec=settings.joint_command_lease_sec,
            details={'requestId': request_id, 'operator': payload.get('operator')},
        )
        self._sync_operation_state()
        if not acquired:
            self.publish_joint_response(request_id, False, 'ROBOT_BUSY', lock_reason, joints=joints)
            return

        result = self.executor.send_joint_positions(joints, source='MQTT_JOINT_REQUEST')
        if not result.ok:
            self.publish_joint_response(request_id, False, result.code, result.message, joints=joints)
            return

        self.joint_target_store.write_joints(joints, source='mqtt_joint_request')
        self.state.update_from_feedback({'joints': joints, 'latencyMs': 0})
        serial_command = payload.get('serialCommand')
        if not isinstance(serial_command, str) or not serial_command.strip():
            serial_command = ','.join(str(v) for v in joints) + '\r'
        self.publish_telemetry()
        self.publish_operation_status()
        self.publish_joint_response(request_id, True, 'OK', 'Joint command accepted and forwarded to UART.', joints=joints, serial_command=serial_command)

    def _handle_auto_pick_request(self, payload: dict[str, Any]) -> None:
        request_id = str(payload.get('requestId', '')) or None
        robot_code = str(payload.get('robotCode', ''))
        action = str(payload.get('action', 'QUERY')).strip().upper()
        if robot_code and robot_code != settings.robot_code:
            self.publish_auto_pick_response(request_id, False, 'INVALID_PAYLOAD', 'robotCode does not match target robot.', action)
            return
        if not AccessControl.is_token_valid(payload):
            self.publish_auto_pick_response(request_id, False, 'AUTH_FAILED', 'Invalid operator token.', action)
            return

        if action == 'QUERY':
            self.publish_auto_pick_response(request_id, True, 'OK', 'Auto-pick status query accepted.', action)
            self.publish_operation_status()
            return

        if action == 'START':
            if not self.uart.is_ready:
                self.publish_auto_pick_response(request_id, False, 'UART_NOT_READY', 'UART chưa sẵn sàng.', action)
                return
            allowed, reason = self.state.is_auto_pick_allowed()
            if not allowed:
                self.publish_auto_pick_response(request_id, False, 'AUTHORITY_DENIED', reason, action)
                return
            acquired, lock_reason = self.operation_manager.acquire(
                owner='AUTO_PICK',
                source='mqtt_auto_pick_request',
                priority=OperationPriority.AUTO_PICK,
                ttl_sec=None,
                details={'requestId': request_id, 'operator': payload.get('operator')},
            )
            self._sync_operation_state()
            if not acquired:
                self.publish_auto_pick_response(request_id, False, 'ROBOT_BUSY', lock_reason, action)
                return
            result = self.auto_pick.start()
            if not result.ok:
                self.operation_manager.release('AUTO_PICK')
                self._sync_operation_state()
                self.publish_auto_pick_response(request_id, False, result.code, result.message, action)
                return
            self.publish_operation_status()
            self.publish_auto_pick_response(request_id, True, result.code, result.message, action)
            return

        if action == 'STOP':
            result = self.auto_pick.stop()
            self.operation_manager.release('AUTO_PICK')
            self._sync_operation_state()
            self.publish_operation_status()
            self.publish_auto_pick_response(request_id, True, result.code, result.message, action)
            return

        self.publish_auto_pick_response(request_id, False, 'INVALID_ACTION', f'Unsupported auto-pick action={action}', action)

    def _handle_mode_request(self, payload: dict[str, Any]) -> None:
        request_id = str(payload.get('requestId', '')).strip() or None
        robot_code = str(payload.get('robotCode', '')).strip()
        requested_mode = str(payload.get('mode', '')).strip().upper()

        if robot_code and robot_code != settings.robot_code:
            self.publish_mode_response(request_id, False, 'INVALID_PAYLOAD', 'robotCode does not match target robot.', requested_mode)
            return
        if requested_mode not in {'AUTO', 'MANUAL'}:
            self.publish_mode_response(request_id, False, 'INVALID_PAYLOAD', 'mode must be AUTO or MANUAL.', requested_mode)
            return
        if not AccessControl.is_token_valid(payload):
            self.publish_mode_response(request_id, False, 'AUTH_FAILED', 'Invalid operator token.', requested_mode)
            return

        role = AccessControl.normalize_role(payload)
        if not AccessControl.can_switch_mode(role):
            self.publish_mode_response(request_id, False, 'PERMISSION_DENIED', 'Chỉ Operator hoặc Admin mới được đổi mode.', requested_mode)
            return

        self._sync_operation_state()
        current_operation = str(self.state.current_operation or 'IDLE').upper()
        if self.state.busy and current_operation not in {'IDLE', 'REMOTE_JOINT_CONTROL'}:
            self.publish_mode_response(request_id, False, 'ROBOT_BUSY', f'Không thể đổi mode khi robot đang bận bởi {self.state.current_operation}.', requested_mode)
            return

        current_mode = str(self.state.mode).upper()
        if current_mode == requested_mode:
            self.publish_mode_response(request_id, True, 'OK', f'Robot đã ở mode {requested_mode}.', requested_mode)
            return

        if requested_mode == 'MANUAL' and self.auto_pick.status().get('state') not in {'IDLE', 'STOPPED'}:
            self.auto_pick.stop()
            self.operation_manager.release('AUTO_PICK')
            self._sync_operation_state()

        if requested_mode == 'AUTO':
            self.operation_manager.release('REMOTE_JOINT_CONTROL')
            self._sync_operation_state()

        # Supervisory mode gate used for arbitration between remote manual / schedule / auto-pick.
        self.state.set_mode(requested_mode)
        if requested_mode == 'MANUAL':
            self.state.set_authority('REMOTE_JOINT_CONTROL', False, 'Remote manual control is allowed.')
        else:
            self.state.set_authority('REMOTE_SCHEDULER', True, 'Remote scheduling is allowed.')

        self.publish_status()
        self.publish_authority()
        self.publish_operation_status()
        self.publish_mode_response(request_id, True, 'OK', f'Robot supervisory mode switched to {requested_mode}.', requested_mode)

    def _process_schedule_request(self, request: ScheduleRequest) -> None:
        if request.robotCode != settings.robot_code:
            self.publish_schedule_response(request, False, 'INVALID_PAYLOAD', 'robotCode does not match target robot.')
            return
        if not AccessControl.is_token_valid({'operator': request.operator, 'authToken': request.authToken}):
            self.publish_schedule_response(request, False, 'AUTH_FAILED', 'Invalid operator token.')
            return

        try:
            action = ScheduleAction(request.action)
        except ValueError:
            self.publish_schedule_response(request, False, 'INVALID_ACTION', f'Unsupported action={request.action}')
            return

        if action == ScheduleAction.QUERY:
            self.publish_schedule_response(request, True, 'OK', 'Schedule query accepted.')
            self.publish_schedule_list(request.requestId)
            return

        role = str(request.role or '').strip().upper()
        if not role:
            role = 'ADMIN' if str(request.operator).strip().lower() == 'admin' else 'OPERATOR'
        if not AccessControl.can_manage_schedule(role):
            self.publish_schedule_response(request, False, 'PERMISSION_DENIED', 'Chỉ Admin mới được tạo hoặc sửa lịch từ xa.')
            return

        allowed, reason = self.state.is_schedule_allowed()
        if not allowed:
            self.publish_schedule_response(request, False, 'AUTHORITY_DENIED', reason)
            return

        if action == ScheduleAction.CREATE:
            self._handle_create(request)
            return
        if action == ScheduleAction.DELETE:
            self._handle_delete(request)
            return
        if action in {ScheduleAction.ENABLE, ScheduleAction.DISABLE, ScheduleAction.UPDATE}:
            self._handle_update_like(request, action)
            return

        self.publish_schedule_response(request, False, 'INVALID_ACTION', f'Unsupported action={action.value}')

    def _extract_schedule_target_joints(self, data: dict[str, Any]) -> list[float] | None:
        raw = data.get('targetJoints') or data.get('joints')
        if not isinstance(raw, list) or len(raw) != 6:
            return None
        try:
            joints = [float(v) for v in raw]
        except (TypeError, ValueError):
            return None
        valid, _ = validate_manual_joint_values(joints, {})
        return joints if valid else None

    def _handle_create(self, request: ScheduleRequest) -> None:
        data = request.data
        program_id = str(data.get('programId', '')).strip() or f'TEACH-{request.requestId[-6:]}'
        trigger_time = str(data.get('triggerTime', ''))
        if not trigger_time:
            self.publish_schedule_response(request, False, 'INVALID_PAYLOAD', 'triggerTime is required.')
            return
        try:
            trigger_dt = isoparse(trigger_time)
        except (TypeError, ValueError):
            self.publish_schedule_response(request, False, 'INVALID_PAYLOAD', 'triggerTime is not a valid ISO-8601 value.')
            return
        if trigger_dt <= utc_now():
            self.publish_schedule_response(request, False, 'INVALID_PAYLOAD', 'triggerTime must be in the future.')
            return

        target_joints = self._extract_schedule_target_joints(data)
        if target_joints is None:
            registry_target = self.program_registry.get_uart_frame(program_id)
            if registry_target is not None and len(registry_target) == 6:
                try:
                    target_joints = [float(v) for v in registry_target]
                except (TypeError, ValueError):
                    target_joints = None
        if target_joints is None:
            self.publish_schedule_response(request, False, 'INVALID_PAYLOAD', f'Schedule must include valid targetJoints or a registered program target for programId={program_id}.')
            return

        repeat_type = str(data.get('repeatType', 'ONCE')).strip().upper() or 'ONCE'
        if repeat_type != 'ONCE':
            self.publish_schedule_response(request, False, 'INVALID_PAYLOAD', 'Current backend supports repeatType=ONCE only.')
            return

        schedule = ScheduleEntry(
            scheduleId=f'LOCAL-{request.requestId}',
            programId=program_id,
            programName=str(data.get('programName', program_id)),
            triggerTime=trigger_time,
            repeatType=repeat_type,
            enabled=bool(data.get('enabled', True)),
            createdBy=request.operator,
            createdAt=iso_utc_now(),
            updatedAt=iso_utc_now(),
            note=data.get('note'),
            targetJoints=target_joints,
        )
        items = self.schedule_store.list()
        if any(item.scheduleId == schedule.scheduleId for item in items):
            self.publish_schedule_response(request, False, 'DUPLICATE_SCHEDULE', 'Schedule requestId already exists.')
            return
        items.append(schedule)
        self.schedule_store.write_all(items)
        self.scheduler.upsert(schedule)
        self.publish_schedule_response(request, True, 'OK', 'Schedule created successfully.', {'scheduleId': schedule.scheduleId, 'schedule': schedule.to_dict()})
        self.publish_schedule_list(request.requestId)

    def _handle_delete(self, request: ScheduleRequest) -> None:
        schedule_id = str(request.data.get('scheduleId', ''))
        items = self.schedule_store.list()
        new_items = [item for item in items if item.scheduleId != schedule_id]
        if len(new_items) == len(items):
            self.publish_schedule_response(request, False, 'SCHEDULE_NOT_FOUND', 'scheduleId not found.')
            return
        self.schedule_store.write_all(new_items)
        self.scheduler.remove(schedule_id)
        self.publish_schedule_response(request, True, 'OK', 'Schedule deleted successfully.', {'scheduleId': schedule_id})
        self.publish_schedule_list(request.requestId)

    def _handle_update_like(self, request: ScheduleRequest, action: ScheduleAction) -> None:
        schedule_id = str(request.data.get('scheduleId', ''))
        items = self.schedule_store.list()
        found = None
        for item in items:
            if item.scheduleId == schedule_id:
                found = item
                break
        if found is None:
            self.publish_schedule_response(request, False, 'SCHEDULE_NOT_FOUND', 'scheduleId not found.')
            return

        if action == ScheduleAction.ENABLE:
            found.enabled = True
        elif action == ScheduleAction.DISABLE:
            found.enabled = False
        elif action == ScheduleAction.UPDATE:
            if 'triggerTime' in request.data:
                try:
                    trigger_dt = isoparse(str(request.data['triggerTime']))
                except (TypeError, ValueError):
                    self.publish_schedule_response(request, False, 'INVALID_PAYLOAD', 'triggerTime is invalid.')
                    return
                if trigger_dt <= utc_now():
                    self.publish_schedule_response(request, False, 'INVALID_PAYLOAD', 'triggerTime must be in the future.')
                    return
                found.triggerTime = str(request.data['triggerTime'])
            if 'programId' in request.data:
                next_program_id = str(request.data['programId']).strip()
                next_target = self._extract_schedule_target_joints(request.data) or found.targetJoints
                if not self.program_registry.has_program(next_program_id) and next_target is None:
                    self.publish_schedule_response(request, False, 'INVALID_PAYLOAD', 'programId is not registered and targetJoints is missing.')
                    return
                found.programId = next_program_id
            if 'repeatType' in request.data:
                repeat_type = str(request.data['repeatType']).strip().upper()
                if repeat_type != 'ONCE':
                    self.publish_schedule_response(request, False, 'INVALID_PAYLOAD', 'Current backend supports repeatType=ONCE only.')
                    return
                found.repeatType = repeat_type
            if 'programName' in request.data:
                found.programName = str(request.data['programName'])
            if 'note' in request.data:
                found.note = request.data['note']
            if 'enabled' in request.data:
                found.enabled = bool(request.data['enabled'])
            next_target = self._extract_schedule_target_joints(request.data)
            if next_target is not None:
                found.targetJoints = next_target
        found.updatedAt = iso_utc_now()
        self.schedule_store.write_all(items)
        self.scheduler.upsert(found)
        self.publish_schedule_response(request, True, 'OK', f'{action.value} successful.', {'scheduleId': schedule_id, 'schedule': found.to_dict()})
        self.publish_schedule_list(request.requestId)

    def _execute_schedule(self, schedule: ScheduleEntry) -> None:
        logger.info('Execute schedule scheduleId=%s programId=%s triggerTime=%s targetJoints=%s', schedule.scheduleId, schedule.programId, schedule.triggerTime, schedule.targetJoints)

        lateness_sec = abs((utc_now() - schedule.trigger_dt).total_seconds())
        if lateness_sec > settings.scheduler_max_lateness_sec:
            self.publish_schedule_execution(schedule.scheduleId, schedule.programId, ExecutionStatus.SKIPPED, 'Scheduler fired too late for this one-shot command.', 'MISFIRE_TOO_LATE')
            self._consume_one_shot_schedule(schedule.scheduleId)
            self.publish_schedule_list(None)
            return

        allowed, reason = self.state.is_schedule_allowed()
        if not allowed:
            self.publish_schedule_execution(schedule.scheduleId, schedule.programId, ExecutionStatus.SKIPPED, reason, 'AUTHORITY_DENIED')
            return
        if not self.uart.is_ready:
            self.publish_schedule_execution(schedule.scheduleId, schedule.programId, ExecutionStatus.SKIPPED, 'UART not ready.', 'UART_NOT_READY')
            return

        acquired, lock_reason = self.operation_manager.acquire(
            owner='SCHEDULE_EXECUTION',
            source='scheduler',
            priority=OperationPriority.SCHEDULE,
            ttl_sec=None,
            details={'scheduleId': schedule.scheduleId, 'programId': schedule.programId},
        )
        self._sync_operation_state()
        if not acquired:
            self.publish_schedule_execution(schedule.scheduleId, schedule.programId, ExecutionStatus.SKIPPED, lock_reason, 'ROBOT_BUSY')
            return

        try:
            self.state.clear_fault()
            self.state.mark_running(schedule.programId, schedule.scheduleId)
            operation_id = f'schedule:{schedule.scheduleId}'
            self.execution_fsm.dispatch(
                operation_id,
                max_attempts=settings.schedule_retry_max_attempts,
                scheduleId=schedule.scheduleId,
                programId=schedule.programId,
            )
            self.publish_status()
            self.publish_operation_status()
            self.publish_schedule_execution(schedule.scheduleId, schedule.programId, ExecutionStatus.STARTED, 'Scheduled target execution started.')

            command_values = schedule.targetJoints
            if command_values is None:
                command_values = self.program_registry.get_uart_frame(schedule.programId)
            if command_values is None or len(command_values) != 6:
                raise ValueError(f'No valid target pose for scheduleId={schedule.scheduleId}, programId={schedule.programId}')
            logger.info('Resolved schedule target scheduleId=%s joints=%s', schedule.scheduleId, command_values)
            command_values = [float(v) for v in command_values]

            final_code = 'UNKNOWN'
            final_message = 'Schedule execution did not complete.'
            for attempt in range(1, settings.schedule_retry_max_attempts + 1):
                result = self.executor.send_joint_positions(command_values, source=f'SCHEDULE_EXECUTION:{schedule.scheduleId}:attempt:{attempt}')
                if not result.ok:
                    self.execution_fsm.transition(ExecutionState.FAILED, reason_code=result.code, message=result.message)
                    final_code, final_message = result.code, result.message
                else:
                    self.execution_fsm.transition(ExecutionState.EXECUTING, message='Waiting for validated target telemetry.')
                    self.joint_target_store.write_joints(command_values, source='schedule_execution')
                    ok, code, message = self._wait_for_schedule_target(command_values)
                    final_code, final_message = code, message
                    if ok:
                        self.execution_fsm.transition(ExecutionState.COMPLETED, message=message)
                        self.state.update_from_feedback({'joints': command_values, 'latencyMs': 0})
                        self.state.mark_idle()
                        self.publish_telemetry()
                        self.publish_schedule_execution(schedule.scheduleId, schedule.programId, ExecutionStatus.COMPLETED, message)
                        self._consume_one_shot_schedule(schedule.scheduleId)
                        self.publish_schedule_list(None)
                        return
                    terminal = ExecutionState.TIMEOUT if 'TIMEOUT' in code or code == 'NO_MOTION' else ExecutionState.FAILED
                    self.execution_fsm.transition(terminal, reason_code=code, message=message)

                if attempt < settings.schedule_retry_max_attempts:
                    time.sleep(settings.schedule_retry_backoff_sec)
                    self.execution_fsm.retry(final_code, f'Retrying after {final_code}: {final_message}')
                    self.publish_operation_status()

            self.state.mark_fault(final_code, final_message)
            self.publish_fault()
            self.publish_schedule_execution(schedule.scheduleId, schedule.programId, ExecutionStatus.FAILED, final_message, final_code)
        except ValueError as exc:
            self.state.mark_fault('INVALID_PROGRAM', str(exc))
            self.publish_fault()
            self.publish_schedule_execution(schedule.scheduleId, schedule.programId, ExecutionStatus.FAILED, str(exc), 'INVALID_PROGRAM')
        finally:
            try:
                if self.execution_fsm.snapshot().get('executionState') != 'IDLE':
                    self.execution_fsm.reset()
            except ValueError:
                logger.warning('Execution FSM reset skipped due to non-terminal state.')
            self.operation_manager.release('SCHEDULE_EXECUTION')
            self._sync_operation_state()
            self.publish_status()
            self.publish_operation_status()

    def _wait_for_schedule_target(self, target_joints: list[float]) -> tuple[bool, str, str]:
        """Wait until telemetry reaches the scheduled target and settles.

        The csv6 robot path used in this project does not emit a dedicated ACK/DONE
        frame. For scheduled motion, the reliable completion criterion is therefore:
        1) telemetry starts moving away from the initial pose within a motion-detect timeout,
        2) telemetry enters the target tolerance window,
        3) it remains in that window for a short settle period.
        """
        target = [float(v) for v in target_joints]
        start_monotonic = time.monotonic()
        motion_deadline = start_monotonic + settings.schedule_motion_detect_timeout_sec
        execution_deadline = start_monotonic + settings.schedule_execution_timeout_sec

        initial = self.state.current_joints()
        motion_detected = False
        in_tolerance_since: float | None = None
        tolerance = float(settings.schedule_position_tolerance_deg)

        def max_abs_diff(a: list[float], b: list[float]) -> float:
            return max(abs(float(x) - float(y)) for x, y in zip(a, b))

        if len(initial) == 6 and max_abs_diff(initial, target) <= tolerance:
            in_tolerance_since = start_monotonic

        while True:
            now = time.monotonic()
            if now > execution_deadline:
                return False, 'TARGET_TIMEOUT', 'Robot did not reach the scheduled target in time.'

            current = self.state.current_joints()
            if len(current) != 6:
                time.sleep(0.05)
                continue

            drift_from_start = max_abs_diff(current, initial)
            distance_to_target = max_abs_diff(current, target)

            if drift_from_start > tolerance:
                motion_detected = True

            if not motion_detected and now > motion_deadline and distance_to_target > tolerance:
                return False, 'NO_MOTION', 'Robot telemetry did not change after the scheduled command was sent.'

            if distance_to_target <= tolerance:
                if in_tolerance_since is None:
                    in_tolerance_since = now
                if now - in_tolerance_since >= settings.schedule_settle_time_sec:
                    return True, 'OK', 'Robot reached scheduled target.'
            else:
                in_tolerance_since = None

            if self.state.fault_active:
                _, code, message = self.state.current_fault()
                return False, code or 'ROBOT_FAULT', message or 'Robot entered FAULT during schedule execution.'

            time.sleep(0.05)

    def _sync_operation_state(self) -> None:
        snapshot = self.operation_manager.snapshot()
        self.state.set_operation(
            busy=bool(snapshot.get('busy', False)),
            current_operation=str(snapshot.get('currentOperation') or 'IDLE'),
            source=snapshot.get('operationSource'),
            started_at=snapshot.get('operationStartedAt'),
            expires_at=snapshot.get('operationExpiresAt'),
            details=snapshot.get('operationDetails'),
        )

    def _on_auto_pick_state_change(self, state: str, message: str) -> None:
        self.state.set_auto_pick_state(state, message)
        if state in {'IDLE', 'ERROR', 'STOPPED'}:
            self.operation_manager.release('AUTO_PICK')
            self._sync_operation_state()
        if state == 'ERROR':
            self.state.mark_fault('AUTO_PICK_ERROR', message)
            self.publish_fault()
        self.publish_status()
        self.publish_authority()
        self.publish_operation_status()
