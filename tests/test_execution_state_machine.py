import pytest

from app.robot.execution_state_machine import ExecutionState, RobotExecutionStateMachine


def test_schedule_execution_happy_path_state_transitions():
    fsm = RobotExecutionStateMachine()
    fsm.dispatch('schedule:1', max_attempts=2)
    assert fsm.snapshot()['executionState'] == 'DISPATCHED'

    fsm.transition(ExecutionState.EXECUTING, message='moving')
    fsm.transition(ExecutionState.COMPLETED, message='done')
    assert fsm.snapshot()['executionState'] == 'COMPLETED'

    fsm.reset()
    assert fsm.snapshot()['executionState'] == 'IDLE'


def test_retry_only_allowed_after_terminal_failure_state():
    fsm = RobotExecutionStateMachine()
    fsm.dispatch('schedule:1', max_attempts=2)
    fsm.transition(ExecutionState.TIMEOUT, reason_code='NO_MOTION', message='no motion')
    fsm.retry('NO_MOTION', 'retry once')

    snapshot = fsm.snapshot()
    assert snapshot['executionState'] == 'DISPATCHED'
    assert snapshot['attempt'] == 2


def test_invalid_transition_is_rejected():
    fsm = RobotExecutionStateMachine()
    with pytest.raises(ValueError):
        fsm.transition(ExecutionState.COMPLETED)
