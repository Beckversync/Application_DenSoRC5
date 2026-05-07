from app.robot.uart_reliability import UartFailureKind, UartReliabilityStats, verify_checksum_frame, xor_checksum


def test_checksum_frame_accepts_valid_payload():
    payload = '10,20,30,40,50,60'
    frame = f'${payload}*{xor_checksum(payload)}'

    ok, parsed, failure = verify_checksum_frame(frame)

    assert ok
    assert parsed == payload
    assert failure == UartFailureKind.OK


def test_checksum_frame_rejects_corruption():
    ok, parsed, failure = verify_checksum_frame('$10,20,30*FF')

    assert not ok
    assert parsed == '10,20,30'
    assert failure == UartFailureKind.CHECKSUM_ERROR


def test_reliability_stats_success_rate():
    stats = UartReliabilityStats()
    stats.record(UartFailureKind.OK)
    stats.record(UartFailureKind.TIMEOUT)
    stats.record(UartFailureKind.MALFORMED_FRAME)

    assert stats.failure_count == 2
    assert round(stats.success_rate, 2) == 0.33
