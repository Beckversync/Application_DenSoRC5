# Production MQTT contract

## App scope
- Observe 3D robot state from MQTT telemetry
- Create/query/enable/disable/delete schedules by MQTT
- No direct robot control from the app

## Authority
Authority is retained because the Mini PC can still take local control of the robot.
The remote app uses authority only for visibility and to block schedule requests when the robot is under local control, maintenance, or locked.

## Namespace
- `robot/v1/default/{robotCode}/robot/status`
- `robot/v1/default/{robotCode}/robot/telemetry`
- `robot/v1/default/{robotCode}/robot/fault`
- `robot/v1/default/{robotCode}/robot/heartbeat`
- `robot/v1/default/{robotCode}/robot/authority`
- `robot/v1/default/{robotCode}/schedule/request`
- `robot/v1/default/{robotCode}/schedule/response`
- `robot/v1/default/{robotCode}/schedule/list`
- `robot/v1/default/{robotCode}/schedule/execution`
- `robot/v1/system/alert`

## Contract rules
- All schedule operations go through one topic: `schedule/request`
- `action` must be one of `QUERY`, `CREATE`, `DELETE`, `ENABLE`, `DISABLE`
- Every request must include `requestId`
- Mini PC publishes `schedule/response` and `schedule/list`
- State and events are separated
- Telemetry uses QoS 0, schedule and state flows use QoS 1

## Broker
- Host: `mqtt.abcsolutions.com.vn`
- Port: `1883`
- Username: `abcsolution`
- Password: configured in `lib/core/app_config.dart`
