from __future__ import annotations

import logging
import threading
from dataclasses import dataclass

from app.robot.protocols.base import RobotProtocol
from app.robot.uart_client import UartClient

logger = logging.getLogger(__name__)


@dataclass
class ExecutionResult:
    ok: bool
    code: str
    message: str


class RobotExecutor:
    """Thin UART sender.

    Manual joint control and scheduled execution intentionally share the exact
    same TX path so the scheduler cannot diverge from the command format that is
    already proven to work during manual jog.
    """

    def __init__(self, uart: UartClient, protocol: RobotProtocol) -> None:
        self._uart = uart
        self._protocol = protocol
        self._lock = threading.Lock()

    def notify_feedback(self, kind: str, payload: dict) -> None:
        # Kept for compatibility with the rest of the service. The current
        # scheduler completion logic is driven by telemetry/state instead of
        # UART ACK/DONE, because the csv6 protocol does not emit those frames.
        return

    def send_joint_positions(self, joints: list[float], source: str = 'MQTT_JOINT_REQUEST') -> ExecutionResult:
        with self._lock:
            try:
                payload = self._protocol.encode_run_program(
                    program_id=source,
                    schedule_id='MANUAL',
                    command_values=joints,
                )
            except ValueError as exc:
                return ExecutionResult(False, 'INVALID_COMMAND', str(exc))
            try:
                self._uart.send(payload)
            except Exception as exc:
                logger.exception('UART send failed for source=%s', source)
                return ExecutionResult(False, 'UART_SEND_FAILED', str(exc))
            logger.info('Executor sent JOINT_POSITIONS source=%s payload=%s', source, payload)
            return ExecutionResult(True, 'OK', 'Joint positions sent to UART.')

    def run_program(self, *, program_id: str, schedule_id: str, command_values: list[float] | None = None) -> ExecutionResult:
        if command_values is None:
            return ExecutionResult(False, 'INVALID_COMMAND', f'No command values provided for scheduleId={schedule_id}')
        return self.send_joint_positions(command_values, source=f'SCHEDULE:{schedule_id}:{program_id}')
