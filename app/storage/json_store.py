from __future__ import annotations

import json
import threading
from pathlib import Path
from typing import Any


class JsonStore:
    def __init__(self, path: str, default: Any):
        self._path = Path(path)
        self._default = default
        self._lock = threading.RLock()
        self._path.parent.mkdir(parents=True, exist_ok=True)
        if not self._path.exists():
            self.write(default)

    def read(self) -> Any:
        with self._lock:
            if not self._path.exists():
                return self._default
            raw = self._path.read_text(encoding='utf-8').strip()
            if not raw:
                return self._default
            return json.loads(raw)

    def write(self, value: Any) -> None:
        with self._lock:
            self._path.parent.mkdir(parents=True, exist_ok=True)
            temp_path = self._path.with_suffix(f'{self._path.suffix}.tmp')
            temp_path.write_text(json.dumps(value, indent=2, ensure_ascii=False), encoding='utf-8')
            temp_path.replace(self._path)
