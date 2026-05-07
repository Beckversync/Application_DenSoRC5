from __future__ import annotations

from typing import Any

from app.config.settings import settings


class AccessControl:
    """Validate operator identity, role permissions, and command ownership.

    The service accepts MQTT messages from multiple UI roles. This helper keeps
    authentication and authorization rules out of the orchestration layer so the
    rules can be tested independently.
    """

    @staticmethod
    def normalize_role(payload: dict[str, Any]) -> str:
        """Return an upper-case role value from an MQTT payload."""
        return str(payload.get('role', '')).strip().upper()

    @staticmethod
    def operator_name(payload: dict[str, Any]) -> str:
        """Return a normalized operator name from an MQTT payload."""
        return str(payload.get('operator', 'unknown')).strip().lower()

    @staticmethod
    def is_token_valid(payload: dict[str, Any]) -> bool:
        """Check whether the payload contains a token registered for the operator."""
        username = AccessControl.operator_name(payload)
        token = str(payload.get('authToken') or '').strip()
        if not username or not token:
            return False
        expected = settings.allowed_tokens.get(username)
        return bool(expected and expected == token)

    @staticmethod
    def can_control_joints(role: str) -> bool:
        """Return True when the role may send manual joint commands."""
        return role in {'ADMIN', 'OPERATOR'}

    @staticmethod
    def can_manage_schedule(role: str) -> bool:
        """Return True when the role may create, update, or delete schedules."""
        return role == 'ADMIN'

    @staticmethod
    def can_switch_mode(role: str) -> bool:
        """Return True when the role may switch robot supervisory mode."""
        return role in {'ADMIN', 'OPERATOR'}
