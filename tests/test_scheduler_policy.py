from datetime import datetime, timedelta, timezone

from app.scheduler.policy import SchedulableJob, SchedulingPolicy, is_deadline_missed, order_jobs


def test_edf_orders_by_priority_then_deadline():
    now = datetime(2026, 1, 1, tzinfo=timezone.utc)
    low_urgent = SchedulableJob('low', now, now, now + timedelta(seconds=1), priority=1)
    high_later = SchedulableJob('high', now, now, now + timedelta(seconds=10), priority=5)
    medium_earlier = SchedulableJob('medium', now, now, now + timedelta(seconds=2), priority=5)

    ordered = order_jobs([low_urgent, high_later, medium_earlier], SchedulingPolicy.EDF)

    assert [job.job_id for job in ordered] == ['medium', 'high', 'low']


def test_fifo_orders_by_acceptance_after_priority():
    now = datetime(2026, 1, 1, tzinfo=timezone.utc)
    first = SchedulableJob('first', now, now, now + timedelta(seconds=10), priority=0)
    second = SchedulableJob('second', now + timedelta(seconds=1), now, now + timedelta(seconds=1), priority=0)

    assert [job.job_id for job in order_jobs([second, first], SchedulingPolicy.FIFO)] == ['first', 'second']


def test_deadline_miss_detection():
    now = datetime(2026, 1, 1, tzinfo=timezone.utc)
    job = SchedulableJob('late', now, now, now + timedelta(seconds=5))

    assert is_deadline_missed(now + timedelta(seconds=6), job)
    assert not is_deadline_missed(now + timedelta(seconds=4), job)
