from __future__ import annotations

from app.robot.feedback_models import RobotFeedback
from app.robot.protocols.base import RobotProtocol


class SimpleTextProtocol(RobotProtocol):
    def encode_run_program(self, *, program_id: str, schedule_id: str, command_values: list[float] | None = None) -> bytes:
        return f'RUN_PROGRAM;programId={program_id};scheduleId={schedule_id}\n'.encode('utf-8')

    def encode_stop(self) -> bytes:
        return b'STOP\n'

    def try_parse_line(self, line: str) -> RobotFeedback | None:
        line = line.strip()
        if not line:
            return None
        parts = line.split(';')
        kind = parts[0].strip().lower()
        payload: dict[str, object] = {'raw': line}
        for part in parts[1:]:
            if '=' not in part:
                continue
            key, value = part.split('=', 1)
            payload[key.strip()] = value.strip()
        if kind == 'tel':
            joints = []
            for idx in range(1, 7):
                raw = payload.get(f'j{idx}')
                joints.append(float(raw) if raw is not None else 0.0)
            payload['joints'] = joints
            kind = 'telemetry'
        elif kind == 'ack':
            kind = 'ack'
        elif kind == 'done':
            kind = 'done'
        elif kind == 'err':
            kind = 'error'
        elif kind == 'state':
            kind = 'state'
        return RobotFeedback(kind=kind, payload=payload)
