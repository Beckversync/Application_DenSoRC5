from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from enum import Enum
from typing import Iterable


class SchedulingPolicy(str, Enum):
    """Supported scheduler arbitration policies for queued robot jobs."""

    EDF = 'EDF'  # Earliest deadline first. Default for deadline-sensitive robot jobs.
    FIFO = 'FIFO'


@dataclass(frozen=True)
class SchedulableJob:
    """Minimal job view used to reason about robot schedule ordering.

    Args:
        job_id: Stable job identifier.
        created_at: Time at which the job was accepted by the backend.
        run_at: Requested execution time.
        deadline_at: Latest acceptable completion/dispatch time.
        priority: Higher value wins before policy-specific tie-breaking.
    """

    job_id: str
    created_at: datetime
    run_at: datetime
    deadline_at: datetime
    priority: int = 0


def order_jobs(jobs: Iterable[SchedulableJob], policy: SchedulingPolicy = SchedulingPolicy.EDF) -> list[SchedulableJob]:
    """Return a deterministic execution order for pending jobs.

    The current product mostly uses APScheduler one-shot triggers. This function
    documents and tests the intended policy when the system is extended to more
    than one queued job or robot: priority first, then EDF or FIFO, then job_id
    for deterministic tie-breaking.
    """

    items = list(jobs)
    if policy == SchedulingPolicy.EDF:
        return sorted(items, key=lambda job: (-job.priority, job.deadline_at, job.run_at, job.job_id))
    if policy == SchedulingPolicy.FIFO:
        return sorted(items, key=lambda job: (-job.priority, job.created_at, job.job_id))
    raise ValueError(f'Unsupported scheduling policy={policy}')


def is_deadline_missed(now: datetime, job: SchedulableJob) -> bool:
    """Return True if a job should be skipped rather than executed late."""

    return now > job.deadline_at
