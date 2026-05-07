from __future__ import annotations

from app.models.schedule_models import ScheduleEntry
from app.storage.json_store import JsonStore


class ScheduleStore:
    def __init__(self, path: str) -> None:
        self._store = JsonStore(path, [])

    def list(self) -> list[ScheduleEntry]:
        return [ScheduleEntry.from_dict(item) for item in self._store.read()]

    def write_all(self, items: list[ScheduleEntry]) -> None:
        self._store.write([item.to_dict() for item in items])
