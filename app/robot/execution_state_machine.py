from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Any

from app.utils.time_utils import iso_utc_now


class ExecutionState(str, Enum):
    """Formal state machine for one robot command execution."""

    IDLE = 'IDLE'
    DISPATCHED = 'DISPATCHED'
    EXECUTING = 'EXECUTING'
    COMPLETED = 'COMPLETED'
    FAILED = 'FAILED'
    TIMEOUT = 'TIMEOUT'
    CANCELLED = 'CANCELLED'


_ALLOWED_TRANSITIONS: dict[ExecutionState, set[ExecutionState]] = {
    ExecutionState.IDLE: {ExecutionState.DISPATCHED},
    ExecutionState.DISPATCHED: {
        ExecutionState.EXECUTING,
        ExecutionState.COMPLETED,
        ExecutionState.FAILED,
        ExecutionState.TIMEOUT,
        ExecutionState.CANCELLED,
    },
    ExecutionState.EXECUTING: {
        ExecutionState.COMPLETED,
        ExecutionState.FAILED,
        ExecutionState.TIMEOUT,
        ExecutionState.CANCELLED,
    },
    ExecutionState.COMPLETED: {ExecutionState.IDLE},
    ExecutionState.FAILED: {ExecutionState.IDLE},
    ExecutionState.TIMEOUT: {ExecutionState.IDLE, ExecutionState.DISPATCHED},
    ExecutionState.CANCELLED: {ExecutionState.IDLE},
}


@dataclass
class ExecutionSnapshot:
    """Serializable view of the current execution state."""

    state: ExecutionState = ExecutionState.IDLE
    operation_id: str | None = None
    attempt: int = 0
    max_attempts: int = 1
    reason_code: str | None = None
    message: str | None = None
    updated_at: str = field(default_factory=iso_utc_now)
    metadata: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return {
            'executionState': self.state.value,
            'operationId': self.operation_id,
            'attempt': self.attempt,
            'maxAttempts': self.max_attempts,
            'reasonCode': self.reason_code,
            'message': self.message,
            'updatedAt': self.updated_at,
            'metadata': self.metadata,
        }


class RobotExecutionStateMachine:
    """Validate and record execution state transitions.

    This class makes the execution lifecycle explicit for defense/review: a
    command is dispatched, observed through telemetry, and then completed or
    failed through deterministic transitions rather than implicit flags.
    """

    def __init__(self) -> None:
        self._snapshot = ExecutionSnapshot()

    def reset(self) -> None:
        """Return the state machine to IDLE after a terminal state."""

        self.transition(ExecutionState.IDLE, message='Execution state reset.')

    def dispatch(self, operation_id: str, max_attempts: int = 1, **metadata: Any) -> None:
        """Start a new execution attempt from IDLE."""

        if self._snapshot.state != ExecutionState.IDLE:
            raise ValueError(f'Cannot dispatch while state={self._snapshot.state.value}')
        self._snapshot = ExecutionSnapshot(
            state=ExecutionState.DISPATCHED,
            operation_id=operation_id,
            attempt=1,
            max_attempts=max_attempts,
            message='Command dispatched to robot.',
            metadata=metadata,
        )

    def retry(self, reason_code: str, message: str) -> None:
        """Start another dispatch attempt after TIMEOUT/FAILED if attempts remain."""

        if self._snapshot.state not in {ExecutionState.TIMEOUT, ExecutionState.FAILED}:
            raise ValueError(f'Cannot retry from state={self._snapshot.state.value}')
        if self._snapshot.attempt >= self._snapshot.max_attempts:
            raise ValueError('Retry budget exhausted')
        self.transition(
            ExecutionState.DISPATCHED,
            reason_code=reason_code,
            message=message,
            attempt=self._snapshot.attempt + 1,
        )

    def transition(
        self,
        next_state: ExecutionState,
        *,
        reason_code: str | None = None,
        message: str | None = None,
        attempt: int | None = None,
    ) -> None:
        """Move to the next state if the transition is allowed."""

        current = self._snapshot.state
        if next_state not in _ALLOWED_TRANSITIONS[current]:
            raise ValueError(f'Invalid execution transition {current.value}->{next_state.value}')
        self._snapshot.state = next_state
        self._snapshot.reason_code = reason_code
        self._snapshot.message = message
        if attempt is not None:
            self._snapshot.attempt = attempt
        self._snapshot.updated_at = iso_utc_now()

    def snapshot(self) -> dict[str, Any]:
        """Return a JSON-serializable state snapshot."""

        return self._snapshot.to_dict()
