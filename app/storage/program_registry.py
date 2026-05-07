from __future__ import annotations

from typing import Any

from app.storage.json_store import JsonStore


class ProgramRegistry:
    def __init__(self, path: str) -> None:
        self._store = JsonStore(path, {'programs': []})

    def _programs(self) -> list[dict[str, Any]]:
        data = self._store.read()
        return list(data.get('programs', []))

    def has_program(self, program_id: str) -> bool:
        return self.get_program(program_id) is not None

    def get_program(self, program_id: str) -> dict[str, Any] | None:
        for item in self._programs():
            if str(item.get('programId')) == program_id:
                return item
        return None

    def get_uart_frame(self, program_id: str) -> list[float] | None:
        item = self.get_program(program_id)
        if item is None:
            return None
        metadata = item.get('metadata') or {}
        frame = metadata.get('uartFrame') or metadata.get('positions') or item.get('uartFrame')
        if frame is None:
            return None
        if not isinstance(frame, list) or len(frame) != 6:
            raise ValueError(f'Program {program_id} has invalid uartFrame. Expected list of 6 values.')
        return [float(v) for v in frame]
