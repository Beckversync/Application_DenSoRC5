from app.coordination.operation_manager import OperationManager
from app.coordination.operation_policy import OperationPriority


def test_manual_can_preempt_schedule_execution():
    manager = OperationManager()
    ok, _ = manager.acquire('SCHEDULE_EXECUTION', 'scheduler', OperationPriority.SCHEDULE)
    assert ok

    ok, reason = manager.acquire('REMOTE_JOINT_CONTROL', 'mqtt', OperationPriority.MANUAL)
    assert ok
    assert reason == 'PREEMPTED:SCHEDULE_EXECUTION'
    assert manager.owner() == 'REMOTE_JOINT_CONTROL'


def test_schedule_cannot_preempt_manual_control():
    manager = OperationManager()
    ok, _ = manager.acquire('REMOTE_JOINT_CONTROL', 'mqtt', OperationPriority.MANUAL)
    assert ok

    ok, reason = manager.acquire('SCHEDULE_EXECUTION', 'scheduler', OperationPriority.SCHEDULE)
    assert not ok
    assert 'REMOTE_JOINT_CONTROL' in reason
