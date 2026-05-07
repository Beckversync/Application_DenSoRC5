from __future__ import annotations

import logging
from collections.abc import Callable
from datetime import datetime, timezone

from apscheduler.jobstores.base import JobLookupError
from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.date import DateTrigger

from app.config.settings import settings
from app.models.schedule_models import ScheduleEntry

logger = logging.getLogger(__name__)


class ScheduleManager:
    """Small adapter around APScheduler for robot schedule entries."""

    def __init__(self, callback: Callable[[ScheduleEntry], None]) -> None:
        self._scheduler = BackgroundScheduler(timezone=timezone.utc)
        self._callback = callback

    def start(self) -> None:
        self._scheduler.start()

    def shutdown(self) -> None:
        self._scheduler.shutdown(wait=False)

    def upsert(self, entry: ScheduleEntry) -> None:
        run_date: datetime = entry.trigger_dt
        if not entry.enabled:
            self.remove(entry.scheduleId)
            return
        self._scheduler.add_job(
            self._callback,
            trigger=DateTrigger(run_date=run_date),
            args=[entry],
            id=entry.scheduleId,
            replace_existing=True,
            misfire_grace_time=settings.scheduler_misfire_grace_sec,
        )
        logger.info('Scheduler upserted job scheduleId=%s runDate=%s', entry.scheduleId, entry.triggerTime)

    def remove(self, schedule_id: str) -> None:
        try:
            self._scheduler.remove_job(schedule_id)
            logger.info('Scheduler removed job scheduleId=%s', schedule_id)
        except JobLookupError:
            logger.debug('Scheduler remove ignored missing scheduleId=%s', schedule_id)
