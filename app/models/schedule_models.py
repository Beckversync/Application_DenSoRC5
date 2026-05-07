from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from typing import Any

from dateutil.parser import isoparse


@dataclass
class ScheduleRequest:
    requestId: str
    robotCode: str
    action: str
    operator: str
    role: str
    timestamp: str
    authToken: str = ''
    data: dict[str, Any] = field(default_factory=dict)

    @staticmethod
    def from_dict(payload: dict[str, Any]) -> 'ScheduleRequest':
        return ScheduleRequest(
            requestId=str(payload.get('requestId', '')),
            robotCode=str(payload.get('robotCode', '')),
            action=str(payload.get('action', '')),
            operator=str(payload.get('operator', 'unknown')),
            role=str(payload.get('role', '')),
            timestamp=str(payload.get('timestamp', '')),
            authToken=str(payload.get('authToken', '')),
            data=dict(payload.get('data', {})),
        )

    def validate_basic(self) -> tuple[bool, str]:
        if not self.requestId:
            return False, 'requestId is required'
        if not self.robotCode:
            return False, 'robotCode is required'
        if not self.action:
            return False, 'action is required'
        if not self.timestamp:
            return False, 'timestamp is required'
        return True, 'OK'


@dataclass
class ScheduleEntry:
    scheduleId: str
    programId: str
    programName: str
    triggerTime: str
    repeatType: str
    enabled: bool
    createdBy: str
    createdAt: str
    updatedAt: str
    note: str | None = None
    targetJoints: list[float] | None = None

    @property
    def trigger_dt(self) -> datetime:
        return isoparse(self.triggerTime)

    def to_dict(self) -> dict[str, Any]:
        return {
            'scheduleId': self.scheduleId,
            'programId': self.programId,
            'programName': self.programName,
            'triggerTime': self.triggerTime,
            'repeatType': self.repeatType,
            'enabled': self.enabled,
            'createdBy': self.createdBy,
            'createdAt': self.createdAt,
            'updatedAt': self.updatedAt,
            'note': self.note,
            'targetJoints': self.targetJoints,
        }

    @staticmethod
    def from_dict(payload: dict[str, Any]) -> 'ScheduleEntry':
        return ScheduleEntry(
            scheduleId=str(payload['scheduleId']),
            programId=str(payload['programId']),
            programName=str(payload.get('programName', payload['programId'])),
            triggerTime=str(payload['triggerTime']),
            repeatType=str(payload.get('repeatType', 'ONCE')),
            enabled=bool(payload.get('enabled', True)),
            createdBy=str(payload.get('createdBy', 'unknown')),
            createdAt=str(payload.get('createdAt')),
            updatedAt=str(payload.get('updatedAt')),
            note=payload.get('note'),
            targetJoints=[float(v) for v in payload['targetJoints']] if isinstance(payload.get('targetJoints'), list) and len(payload['targetJoints']) == 6 else None,
        )
