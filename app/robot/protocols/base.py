from __future__ import annotations

from abc import ABC, abstractmethod

from app.robot.feedback_models import RobotFeedback


class RobotProtocol(ABC):
    @abstractmethod
    def encode_run_program(
        self,
        *,
        program_id: str,
        schedule_id: str,
        command_values: list[float] | None = None,
    ) -> bytes: ...

    @abstractmethod
    def encode_stop(self) -> bytes: ...

    @abstractmethod
    def try_parse_line(self, line: str) -> RobotFeedback | None: ...
