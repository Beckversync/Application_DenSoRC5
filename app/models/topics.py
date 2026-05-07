from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class TopicBuilder:
    namespace: str
    site: str
    robot_code: str

    @property
    def root(self) -> str:
        return f'{self.namespace}/{self.site}/{self.robot_code}'

    @property
    def robot_status(self) -> str:
        return f'{self.root}/robot/status'

    @property
    def robot_telemetry(self) -> str:
        return f'{self.root}/robot/telemetry'

    @property
    def robot_fault(self) -> str:
        return f'{self.root}/robot/fault'

    @property
    def robot_heartbeat(self) -> str:
        return f'{self.root}/robot/heartbeat'

    @property
    def robot_authority(self) -> str:
        return f'{self.root}/robot/authority'

    @property
    def robot_event(self) -> str:
        return f'{self.root}/robot/event'

    @property
    def schedule_request(self) -> str:
        return f'{self.root}/schedule/request'

    @property
    def schedule_response(self) -> str:
        return f'{self.root}/schedule/response'

    @property
    def schedule_list(self) -> str:
        return f'{self.root}/schedule/list'

    @property
    def schedule_execution(self) -> str:
        return f'{self.root}/schedule/execution'

    @property
    def robot_mode_request(self) -> str:
        return f'{self.root}/robot/mode/request'

    @property
    def robot_mode_response(self) -> str:
        return f'{self.root}/robot/mode/response'

    @property
    def robot_joint_request(self) -> str:
        return f'{self.root}/robot/joint/request'

    @property
    def robot_joint_response(self) -> str:
        return f'{self.root}/robot/joint/response'

    @property
    def robot_operation_status(self) -> str:
        return f'{self.root}/robot/operation/status'

    @property
    def robot_auto_pick_request(self) -> str:
        return f'{self.root}/robot/auto-pick/request'

    @property
    def robot_auto_pick_response(self) -> str:
        return f'{self.root}/robot/auto-pick/response'

    @property
    def robot_auto_pick_event(self) -> str:
        return f'{self.root}/robot/auto-pick/event'
