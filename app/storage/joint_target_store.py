from __future__ import annotations

from typing import Any

from app.storage.json_store import JsonStore
from app.utils.time_utils import iso_utc_now


class JointTargetStore:
    def __init__(self, path: str) -> None:
        self._store = JsonStore(path, {'joints': [0.0] * 6, 'updatedAt': None, 'source': 'default'})

    def get_joints(self) -> list[float] | None:
        data = self._store.read()
        joints = data.get('joints')
        if not isinstance(joints, list) or len(joints) != 6:
            return None
        return [float(v) for v in joints]

    def write_joints(self, joints: list[float], source: str = 'mqtt') -> None:
        if len(joints) != 6:
            raise ValueError('Expected 6 joint values.')
        self._store.write({
            'joints': [float(v) for v in joints],
            'updatedAt': iso_utc_now(),
            'source': source,
        })

    def payload(self) -> dict[str, Any]:
        data = self._store.read()
        joints = data.get('joints')
        if not isinstance(joints, list) or len(joints) != 6:
            joints = [0.0] * 6
        return {
            'joints': [float(v) for v in joints],
            'updatedAt': data.get('updatedAt'),
            'source': data.get('source') or 'default',
        }
