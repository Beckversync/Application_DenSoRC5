# Mini PC scheduler fix

This version removes the false UART ACK dependency for `csv6` robots.

## Why the old scheduler failed
Manual joint control worked because it only transmitted the 6-axis frame.
Scheduled execution failed because it waited for `ACK` / `DONE`, but the `csv6`
protocol only streams pose telemetry and does not emit explicit ACK frames.

## What changed
- Manual jog and schedule now use the same UART TX path.
- Schedule completion is judged by telemetry reaching the target pose.
- One-shot schedules are automatically disabled after success or after a misfire.
- The backend rejects unsupported repeat types instead of pretending to support them.
- Settings dataclass was fixed for Python 3.12 (`default_factory`).

## Scheduler completion rule
A schedule is considered completed when:
1. command was sent to UART successfully,
2. robot starts moving or is already at target,
3. all 6 joints stay within `SCHEDULE_POSITION_TOLERANCE_DEG`
   for at least `SCHEDULE_SETTLE_TIME_SEC`.

## Recommended tuning
If the robot is slow or noisy, adjust:
- `SCHEDULE_POSITION_TOLERANCE_DEG`
- `SCHEDULE_SETTLE_TIME_SEC`
- `SCHEDULE_MOTION_DETECT_TIMEOUT_SEC`
- `SCHEDULE_EXECUTION_TIMEOUT_SEC`
