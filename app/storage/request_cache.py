from __future__ import annotations

from dataclasses import dataclass
from datetime import timedelta
from typing import Any

from dateutil.parser import isoparse

from app.storage.json_store import JsonStore
from app.utils.time_utils import utc_now


@dataclass
class CacheEntry:
    payload: dict[str, Any]
    created_at: str


class RequestCache:
    def __init__(self, path: str, ttl_sec: int) -> None:
        self._store = JsonStore(path, {})
        self._ttl = timedelta(seconds=ttl_sec)

    def get(self, request_id: str) -> dict[str, Any] | None:
        data = self._store.read()
        item = data.get(request_id)
        if not item:
            return None
        created_at = isoparse(item['created_at'])
        if utc_now() - created_at > self._ttl:
            data.pop(request_id, None)
            self._store.write(data)
            return None
        return item['payload']

    def put(self, request_id: str, payload: dict[str, Any], timestamp: str) -> None:
        data = self._store.read()
        data[request_id] = {'payload': payload, 'created_at': timestamp}
        self._store.write(data)
