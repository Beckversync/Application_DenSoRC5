from __future__ import annotations

import threading
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any

from app.coordination.operation_policy import can_preempt


def _iso_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')


@dataclass
class OperationLease:
    owner: str
    source: str
    priority: int
    started_at: str
    expires_at: str | None = None
    details: dict[str, Any] | None = None

    def is_expired(self) -> bool:
        if not self.expires_at:
            return False
        expires = datetime.fromisoformat(self.expires_at.replace('Z', '+00:00'))
        return datetime.now(timezone.utc) >= expires


class OperationManager:
    def __init__(self) -> None:
        self._lock = threading.RLock()
        self._lease: OperationLease | None = None

    def acquire(
        self,
        owner: str,
        source: str,
        priority: int,
        ttl_sec: float | None = None,
        details: dict[str, Any] | None = None,
    ) -> tuple[bool, str]:
        """Acquire the exclusive robot lease using explicit priority rules.

        Same-owner refresh is allowed. Higher-priority operations can preempt
        only if operation_policy.can_preempt says so; this prevents ambiguous
        races such as a schedule interrupting a manual command.
        """

        with self._lock:
            self._clear_expired_locked()
            if self._lease is None:
                self._lease = self._build_lease(owner, source, priority, ttl_sec, details)
                return True, 'OK'
            if self._lease.owner == owner:
                self._lease = self._build_lease(owner, source, priority, ttl_sec, details)
                return True, 'OK'
            if can_preempt(owner, self._lease.owner, priority, self._lease.priority):
                previous_owner = self._lease.owner
                self._lease = self._build_lease(owner, source, priority, ttl_sec, details)
                return True, f'PREEMPTED:{previous_owner}'
            return False, f'Robot đang bận bởi {self._lease.owner}.'

    def release(self, owner: str) -> bool:
        with self._lock:
            self._clear_expired_locked()
            if self._lease is None or self._lease.owner != owner:
                return False
            self._lease = None
            return True

    def force_release(self) -> None:
        with self._lock:
            self._lease = None

    def current(self) -> OperationLease | None:
        with self._lock:
            self._clear_expired_locked()
            return self._lease

    def is_busy(self) -> bool:
        return self.current() is not None

    def owner(self) -> str | None:
        lease = self.current()
        return lease.owner if lease else None

    def snapshot(self) -> dict[str, Any]:
        lease = self.current()
        if lease is None:
            return {
                'busy': False,
                'currentOperation': 'IDLE',
                'operationSource': None,
                'operationStartedAt': None,
                'operationExpiresAt': None,
                'operationDetails': None,
            }
        return {
            'busy': True,
            'currentOperation': lease.owner,
            'operationSource': lease.source,
            'operationStartedAt': lease.started_at,
            'operationExpiresAt': lease.expires_at,
            'operationDetails': lease.details,
        }

    def _build_lease(self, owner: str, source: str, priority: int, ttl_sec: float | None, details: dict[str, Any] | None) -> OperationLease:
        started = _iso_now()
        expires = None
        if ttl_sec is not None and ttl_sec > 0:
            expires_dt = datetime.now(timezone.utc) + timedelta(seconds=ttl_sec)
            expires = expires_dt.isoformat().replace('+00:00', 'Z')
        return OperationLease(
            owner=owner,
            source=source,
            priority=priority,
            started_at=started,
            expires_at=expires,
            details=details,
        )

    def _clear_expired_locked(self) -> None:
        if self._lease and self._lease.is_expired():
            self._lease = None
