from __future__ import annotations

from app.config.settings import settings
from app.robot.protocols.base import RobotProtocol
from app.robot.protocols.csv6_protocol import Csv6Protocol
from app.robot.protocols.json_line_protocol import JsonLineProtocol
from app.robot.protocols.simple_text_protocol import SimpleTextProtocol


def build_protocol() -> RobotProtocol:
    if settings.uart_protocol == 'csv6':
        return Csv6Protocol()
    if settings.uart_protocol == 'line_json':
        return JsonLineProtocol()
    if settings.uart_protocol == 'simple_text':
        return SimpleTextProtocol()
    raise ValueError(f'Unsupported UART_PROTOCOL={settings.uart_protocol}')
