# Architecture Update Notes

This project was updated to match the new architecture:

- Added 6 manual joint control buttons on the dashboard for J1..J6.
- Added MQTT topics for manual joint control:
  - `robot/v1/default/{robotCode}/robot/joint/request`
  - `robot/v1/default/{robotCode}/robot/joint/response`
- Operator can:
  - view 3D model
  - control 6 joints
  - create and manage schedules
- Viewer can:
  - view 3D model only
- Navigation was updated so Viewer only sees the dashboard.
- Dashboard was updated so Viewer only sees the 3D panel.
- Joint command publish flow was added in `RobotGatewayService`.


## 2026-04-15 pendant update

- Replaced the old 6-button joint control with a teach-pendant layout using 12 buttons (`- / +` for J1..J6).
- Added short-tap step move (`MOVE_RELATIVE`, default 5 degrees).
- Reworked joint control to publish a full 6-joint pose on every tap/hold cycle; long-press now auto-repeats pose updates instead of sending `JOG START/STOP`.
- Viewer role remains limited to 3D monitoring only.

- MQTT joint payload now includes both `joints: [j1..j6]` and `serialCommand: "j1,j2,j3,j4,j5,j6\r"` for Mini PC / serial bridge integration.
