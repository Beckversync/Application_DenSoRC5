# Mini PC UART + MQTT Production Service

Đây là bản Mini PC service theo hướng production:
- nhận request schedule qua MQTT
- lưu lịch local
- đến giờ chạy thì gửi lệnh UART thật xuống robot
- đọc feedback thật từ robot qua UART
- publish status / telemetry / fault / authority / schedule events lên MQTT

## Điểm quan trọng

Project này được viết theo hướng **pluggable protocol**. Hiện đã cấu hình mặc định theo format UART thực tế dạng:

```text
a1,a2,a3,a4,a5,a6
```

Bạn chỉ cần sửa hoặc thay protocol adapter trong:
- `app/robot/protocols/csv6_protocol.py`
- `app/robot/protocols/json_line_protocol.py`
- `app/robot/protocols/simple_text_protocol.py`

## Protocol mặc định: `csv6`

### 1. Feedback từ robot
Robot gửi mỗi frame một dòng UART gồm 6 giá trị số, ví dụ:

```text
0,10,20,30,40,50
```

Service sẽ parse frame này thành telemetry `joints[6]`.

### 2. Lệnh xuống robot
Khi có `robot/joint/request`, service sẽ lấy trực tiếp `joints[6]` từ JSON MQTT rồi gửi đúng 6 giá trị đó xuống UART. Khi schedule được kích hoạt, service ưu tiên dùng `data.joints` của schedule, nếu không có thì mới fallback sang cache joint gần nhất hoặc `uartFrame` trong `programs/program_registry.json`:

```json
{
  "programId": "P1",
  "metadata": {
    "uartFrame": [0, 10, 20, 30, 40, 50]
  }
}
```

Frame gửi đi sẽ là:

```text
0,10,20,30,40,50
```

> Lưu ý: với protocol `csv6`, mỗi program phải có `metadata.uartFrame` gồm đúng 6 giá trị.

## Các protocol mẫu khác

### `line_json`
Robot gửi mỗi frame một dòng JSON, ví dụ:
```json
{"type":"telemetry","joints":[0,10,20,30,40,50],"state":"IDLE","faultActive":false}
```

### `simple_text`
Robot gửi/nhận frame text dạng key-value, ví dụ:
```text
TEL;j1=0;j2=10;j3=20;j4=30;j5=40;j6=50;state=IDLE;fault=0
ACK;command=RUN_PROGRAM;accepted=1
DONE;programId=P1
```

## Chạy thử
```bash
python -m venv .venv
.venv\Scriptsctivate   # Windows
pip install -r requirements.txt
copy .env.example .env
python main.py
```

## Chỗ cần chỉnh khi nối robot thật

1. `.env`
- `UART_PORT`
- `UART_BAUDRATE`
- `UART_PROTOCOL=csv6`
- `MQTT_PASSWORD`

2. `programs/program_registry.json`
- map `programId` với `metadata.uartFrame`

3. Protocol adapter
- nếu robot có thêm ACK / DONE / ERROR riêng, mở rộng `app/robot/protocols/csv6_protocol.py`

## Luồng runtime

1. Mini PC connect MQTT
2. Mini PC subscribe `robot/v1/default/{robotCode}/schedule/request`
3. Mini PC mở UART
4. Khi robot gửi feedback UART → parse → cập nhật state store → publish MQTT
5. Khi app gửi `schedule/request` → lưu lịch local → APScheduler tạo job
6. Đến giờ → executor lấy `uartFrame` của `programId` → gửi UART → chờ ACK / DONE / ERROR nếu protocol hỗ trợ


## MQTT joint request

Mini PC subscribe thêm topic:

```text
robot/v1/default/{robotCode}/robot/joint/request
```

Payload được dùng trực tiếp, không hard-code `1,2,3,4,5,6` hay `0,10,20,30,40,50`:

```json
{
  "requestId": "req-123",
  "robotCode": "RB001",
  "operator": "operator",
  "role": "OPERATOR",
  "jointIndex": 0,
  "stepDeg": 1.0,
  "joints": [1, 2, 3, 4, 5, 6],
  "serialCommand": "1,2,3,4,5,6\r",
  "timestamp": "2026-04-15T00:00:00Z"
}
```

Service sẽ:
- validate `joints` có đúng 6 giá trị
- gửi đúng pose này xuống UART
- cập nhật cache pose gần nhất
- publish lại `robot/telemetry` với `retain=true`
- publish `robot/joint/response`


## Essential MQTT topics
- robot/status
- robot/telemetry
- robot/fault
- robot/authority
- robot/operation/status
- robot/mode/request, robot/mode/response
- robot/joint/request, robot/joint/response
- robot/auto-pick/request, robot/auto-pick/response
- schedule/request, schedule/response, schedule/list


## Kiến trúc sau refactor

Backend Mini PC được chia theo trách nhiệm:

- `app/mqtt/client_service.py`: kết nối MQTT, subscribe/publish JSON, replay subscription sau reconnect.
- `app/robot/uart_client.py`, `app/robot/executor.py`, `app/robot/protocols/`: giao tiếp UART và đóng gói protocol robot.
- `app/scheduler/manager.py`: adapter APScheduler cho lịch chạy robot.
- `app/coordination/operation_manager.py`: khóa vận hành để tránh manual/schedule/auto-pick tranh chấp robot.
- `app/security_access.py`: xác thực token và phân quyền ADMIN/OPERATOR/VIEWER.
- `app/validation/joints.py`: parse và validate target joint/stepDeg, có unit test riêng.
- `app/storage/`: lưu schedule, request cache, program registry, joint target cache.

## Chạy backend

```bash
cd minipc_uart
python -m venv .venv
source .venv/bin/activate  # Windows: .venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env
# sửa MQTT_HOST, MQTT_USERNAME, MQTT_PASSWORD, ALLOWED_TOKENS_JSON, UART_PORT
python main.py
```

Không commit `.env`. Chỉ commit `.env.example` với placeholder.

## Kiểm tra chất lượng code

```bash
cd minipc_uart
python -m pytest
python -m flake8 app tests --max-line-length=100
```

## Quy tắc bảo mật payload

- Mọi command MQTT phải có `requestId`, `robotCode`, `operator`, `role`, `authToken`.
- `authToken` được đọc từ `ALLOWED_TOKENS_JSON` trong biến môi trường.
- Joint manual command phải có đúng 6 giá trị số và nằm trong giới hạn cấu hình.
- Backend phản hồi lỗi rõ ràng qua MQTT response topic thay vì fail im lặng.

## Academic defense / evaluation commands

Run all unit tests:

```bash
pip install -r requirements.txt
pytest -q
```

Run deterministic fault-injection benchmark:

```bash
python tools/benchmark_simulation.py --trials 200 --output-dir benchmark_output
cat benchmark_output/benchmark_summary.json
```

The benchmark is not a replacement for hardware-in-the-loop measurement. It is a reproducible software validation harness for duplicate commands, telemetry drops, transient UART failures, and bounded recovery.

## Scheduling policy note

The current system primarily uses APScheduler one-shot jobs. For research completeness and future multi-job extension, `app/scheduler/policy.py` defines deterministic ordering:

```text
priority first, then EDF by deadline, then run_at, then job_id
```

This avoids a vague answer when asked whether the scheduler is FIFO, EDF, or undefined.

## UART reliability note

The legacy robot path still accepts CSV frames, but `app/robot/uart_reliability.py` adds checksum-frame validation utilities and reliability counters. This provides a clear migration path from simple UART strings to diagnosable framed serial communication.
