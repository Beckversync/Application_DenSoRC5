from __future__ import annotations

from dataclasses import dataclass
from typing import Any


@dataclass
class RobotFeedback:
    kind: str
    payload: dict[str, Any]
