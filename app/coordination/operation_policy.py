from __future__ import annotations

from enum import IntEnum


class OperationPriority(IntEnum):
    """Priority order for mutually exclusive robot operations.

    Higher value wins. Emergency/manual commands can preempt automated work, while
    scheduled jobs must not interrupt explicit operator control.
    """

    SCHEDULE = 20
    MANUAL = 30
    AUTO_PICK = 40
    EMERGENCY = 100


PREEMPTABLE_BY_PRIORITY: dict[str, set[str]] = {
    'REMOTE_JOINT_CONTROL': {'SCHEDULE_EXECUTION', 'AUTO_PICK'},
    'EMERGENCY_STOP': {'SCHEDULE_EXECUTION', 'REMOTE_JOINT_CONTROL', 'AUTO_PICK'},
}


def can_preempt(incoming_owner: str, current_owner: str, incoming_priority: int, current_priority: int) -> bool:
    """Return whether an incoming operation may replace the active operation."""

    allowed_targets = PREEMPTABLE_BY_PRIORITY.get(incoming_owner, set())
    return current_owner in allowed_targets and incoming_priority > current_priority
