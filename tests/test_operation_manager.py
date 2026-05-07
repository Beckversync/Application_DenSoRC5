import time

from app.coordination.operation_manager import OperationManager


def test_acquire_release_and_snapshot():
    manager = OperationManager()

    ok, reason = manager.acquire("SCHEDULE", "unit-test", priority=20)
    assert ok is True
    assert reason == "OK"
    assert manager.snapshot()["currentOperation"] == "SCHEDULE"

    ok, reason = manager.acquire("MANUAL", "unit-test", priority=30)
    assert ok is False
    assert "SCHEDULE" in reason

    assert manager.release("SCHEDULE") is True
    assert manager.snapshot()["busy"] is False


def test_expired_lease_is_cleared():
    manager = OperationManager()
    manager.acquire("MANUAL", "unit-test", priority=30, ttl_sec=0.01)

    time.sleep(0.02)

    assert manager.snapshot()["busy"] is False
