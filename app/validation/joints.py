from __future__ import annotations

from typing import Any

from app.config.settings import settings


def parse_six_joint_values(raw: Any) -> tuple[bool, list[float] | None, str]:
    """Parse a JSON value into exactly six joint angles.

    Args:
        raw: Value received from MQTT, expected to be a list of six numbers.

    Returns:
        Tuple of success flag, parsed joints, and human-readable reason.
    """
    if not isinstance(raw, list) or len(raw) != 6:
        return False, None, 'joints must be a list of 6 values.'
    try:
        return True, [float(value) for value in raw], 'OK'
    except (TypeError, ValueError):
        return False, None, 'joints contains non-numeric values.'


def validate_manual_joint_values(
    joints: list[float],
    payload: dict[str, Any],
) -> tuple[bool, str]:
    """Validate joint limits and optional manual step size.

    Args:
        joints: Parsed six-axis joint targets in degrees.
        payload: Original command payload; may contain ``stepDeg``.
    """
    for value in joints:
        if value < settings.joint_limit_min_deg or value > settings.joint_limit_max_deg:
            return False, f'Joint target {value} out of configured range.'

    step_deg = payload.get('stepDeg')
    if step_deg is not None:
        try:
            step = abs(float(step_deg))
        except (TypeError, ValueError):
            return False, 'stepDeg must be numeric.'
        if step > settings.manual_step_max_deg:
            return False, f'stepDeg must be <= {settings.manual_step_max_deg}.'
    return True, 'OK'
