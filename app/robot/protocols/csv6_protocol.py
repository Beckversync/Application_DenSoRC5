from __future__ import annotations

from app.robot.feedback_models import RobotFeedback
from app.robot.protocols.base import RobotProtocol


class Csv6Protocol(RobotProtocol):
    """UART protocol for six comma-separated numeric values: a1,a2,a3,a4,a5,a6\r"""

    SCALE = 100.0

    def encode_run_program(
        self,
        *,
        program_id: str,
        schedule_id: str,
        command_values: list[float] | None = None,
    ) -> bytes:
        if command_values is None:
            raise ValueError(
                'CSV6 protocol requires a 6-value uartFrame for the target program. '
                f'programId={program_id} scheduleId={schedule_id}'
            )
        if len(command_values) != 6:
            raise ValueError(
                f'CSV6 protocol expected 6 command values, got {len(command_values)} '
                f'for programId={program_id}'
            )
        scaled_values = [float(v) * self.SCALE for v in command_values]
        values = ','.join(self._format_number(v) for v in scaled_values)
        return (values + '\r').encode('utf-8')

    def encode_stop(self) -> bytes:
        return b'0,0,0,0,0,0\r'

    def try_parse_line(self, line: str) -> RobotFeedback | None:
        cleaned = line.strip()
        if not cleaned:
            return None
        # Be tolerant if firmware sometimes wraps the frame with parentheses.
        if cleaned.startswith('(') and cleaned.endswith(')'):
            cleaned = cleaned[1:-1].strip()
        parts = [part.strip() for part in cleaned.split(',') if part.strip() != '']
        if len(parts) != 6:
            return RobotFeedback(kind='raw', payload={'raw': line})
        try:
            rc5_joints = [float(part) for part in parts]
        except ValueError:
            return RobotFeedback(kind='raw', payload={'raw': line})
        return RobotFeedback(
            kind='telemetry',
            payload={
                'raw': line,
                'joints': [value / self.SCALE for value in rc5_joints],
                'state': 'IDLE',
                'mode': None,
                'faultActive': False,
            },
        )

    @staticmethod
    def _format_number(value: float) -> str:
        text = f'{float(value):.10f}'.rstrip('0').rstrip('.')
        return text if text not in {'', '-0'} else '0'
