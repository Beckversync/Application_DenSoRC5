from __future__ import annotations

from dataclasses import dataclass
from enum import Enum


class UartFailureKind(str, Enum):
    """UART fault categories used by reliability tests and runbook decisions."""

    OK = 'OK'
    TIMEOUT = 'TIMEOUT'
    CHECKSUM_ERROR = 'CHECKSUM_ERROR'
    MALFORMED_FRAME = 'MALFORMED_FRAME'
    WRITE_ERROR = 'WRITE_ERROR'


@dataclass
class UartReliabilityStats:
    """Track UART frame health for fault-injection and production diagnostics."""

    tx_count: int = 0
    rx_count: int = 0
    timeout_count: int = 0
    malformed_count: int = 0
    checksum_error_count: int = 0
    write_error_count: int = 0

    def record(self, failure: UartFailureKind) -> None:
        """Update counters after one UART attempt."""

        if failure == UartFailureKind.OK:
            self.rx_count += 1
        elif failure == UartFailureKind.TIMEOUT:
            self.timeout_count += 1
        elif failure == UartFailureKind.CHECKSUM_ERROR:
            self.checksum_error_count += 1
        elif failure == UartFailureKind.MALFORMED_FRAME:
            self.malformed_count += 1
        elif failure == UartFailureKind.WRITE_ERROR:
            self.write_error_count += 1

    @property
    def failure_count(self) -> int:
        return self.timeout_count + self.malformed_count + self.checksum_error_count + self.write_error_count

    @property
    def success_rate(self) -> float:
        total = self.rx_count + self.failure_count
        if total == 0:
            return 1.0
        return self.rx_count / total


def xor_checksum(payload: str) -> str:
    """Return two-character XOR checksum for ASCII payload strings."""

    value = 0
    for ch in payload.encode('utf-8'):
        value ^= ch
    return f'{value:02X}'


def verify_checksum_frame(frame: str) -> tuple[bool, str, UartFailureKind]:
    """Validate a simple `$payload*CS` UART diagnostic frame.

    The production robot still accepts the legacy CSV protocol, but this helper
    gives the thesis a clear migration path for reliable UART framing and lets
    the test suite simulate corrupted frames instead of hand-waving packet loss.
    """

    text = frame.strip()
    if not text.startswith('$') or '*' not in text:
        return False, '', UartFailureKind.MALFORMED_FRAME
    payload, checksum = text[1:].rsplit('*', 1)
    if len(checksum) != 2:
        return False, payload, UartFailureKind.MALFORMED_FRAME
    if xor_checksum(payload).upper() != checksum.upper():
        return False, payload, UartFailureKind.CHECKSUM_ERROR
    return True, payload, UartFailureKind.OK
