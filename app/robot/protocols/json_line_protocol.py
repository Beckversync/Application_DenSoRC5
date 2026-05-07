from __future__ import annotations

import json

from app.robot.feedback_models import RobotFeedback
from app.robot.protocols.base import RobotProtocol


class JsonLineProtocol(RobotProtocol):
    def encode_run_program(self, *, program_id: str, schedule_id: str, command_values: list[float] | None = None) -> bytes:
        body = {'type': 'run_program', 'programId': program_id, 'scheduleId': schedule_id}
        return (json.dumps(body, separators=(',', ':')) + "\n").encode('utf-8')

    def encode_stop(self) -> bytes:
        return (json.dumps({'type': 'stop'}) + "\n").encode('utf-8')

    def try_parse_line(self, line: str) -> RobotFeedback | None:
        line = line.strip()
        if not line:
            return None
        data = json.loads(line)
        kind = str(data.get('type', '')).lower()
        if not kind:
            return None
        return RobotFeedback(kind=kind, payload=data)
