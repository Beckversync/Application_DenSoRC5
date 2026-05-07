from __future__ import annotations

import logging
import threading
import time
from dataclasses import dataclass
from typing import Callable

logger = logging.getLogger(__name__)


@dataclass
class AutoPickResult:
    ok: bool
    code: str
    message: str


class AutoPickManager:
    """Cooperative wrapper for the future vision/grasp task.

    Replace _run_cycle() with the real detect-plan-pick pipeline.
    The manager keeps a single worker thread and exposes start/stop/query.
    """

    def __init__(self, on_state_change: Callable[[str, str], None] | None = None) -> None:
        self._lock = threading.RLock()
        self._thread: threading.Thread | None = None
        self._stop = threading.Event()
        self._state = 'IDLE'
        self._message = 'Auto-pick is idle.'
        self._on_state_change = on_state_change

    def start(self) -> AutoPickResult:
        with self._lock:
            if self._thread and self._thread.is_alive():
                return AutoPickResult(False, 'ALREADY_RUNNING', 'Auto-pick đang chạy.')
            self._stop.clear()
            self._set_state('STARTING', 'Auto-pick worker is starting.')
            self._thread = threading.Thread(target=self._worker, daemon=True)
            self._thread.start()
            return AutoPickResult(True, 'OK', 'Auto-pick started.')

    def stop(self) -> AutoPickResult:
        with self._lock:
            if not self._thread or not self._thread.is_alive():
                self._set_state('IDLE', 'Auto-pick is idle.')
                return AutoPickResult(True, 'OK', 'Auto-pick đã dừng.')
            self._set_state('STOPPING', 'Stopping auto-pick worker.')
            self._stop.set()
            return AutoPickResult(True, 'OK', 'Stop signal sent to auto-pick.')

    def status(self) -> dict[str, str | bool]:
        with self._lock:
            running = self._thread is not None and self._thread.is_alive()
            return {
                'state': self._state,
                'message': self._message,
                'running': running,
            }

    def _worker(self) -> None:
        self._set_state('RUNNING', 'Auto-pick is running.')
        try:
            while not self._stop.is_set():
                self._run_cycle()
        except Exception as exc:  # pragma: no cover - defensive runtime path
            logger.exception('Auto-pick worker failed: %s', exc)
            self._set_state('ERROR', str(exc))
        else:
            self._set_state('IDLE', 'Auto-pick stopped normally.')

    def _run_cycle(self) -> None:
        # Placeholder pipeline to be replaced by the real detect-plan-pick sequence.
        time.sleep(0.2)

    def _set_state(self, state: str, message: str) -> None:
        with self._lock:
            self._state = state
            self._message = message
        if self._on_state_change:
            self._on_state_change(state, message)
