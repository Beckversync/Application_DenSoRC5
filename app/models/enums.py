from __future__ import annotations

from enum import Enum


class RobotMode(str, Enum):
    AUTO = 'AUTO'
    MANUAL = 'MANUAL'
    LOCAL = 'LOCAL'
    UNKNOWN = 'UNKNOWN'


class Authority(str, Enum):
    REMOTE_SCHEDULER = 'REMOTE_SCHEDULER'
    REMOTE_JOINT_CONTROL = 'REMOTE_JOINT_CONTROL'
    LOCAL_OPERATOR = 'LOCAL_OPERATOR'
    LOCKED = 'LOCKED'
    MAINTENANCE = 'MAINTENANCE'


class ExecutionStatus(str, Enum):
    STARTED = 'STARTED'
    COMPLETED = 'COMPLETED'
    FAILED = 'FAILED'
    SKIPPED = 'SKIPPED'
    CANCELLED = 'CANCELLED'


class ScheduleAction(str, Enum):
    QUERY = 'QUERY'
    CREATE = 'CREATE'
    UPDATE = 'UPDATE'
    DELETE = 'DELETE'
    ENABLE = 'ENABLE'
    DISABLE = 'DISABLE'
