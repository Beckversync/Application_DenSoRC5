from __future__ import annotations

import logging
import threading
import time
from collections.abc import Callable
from typing import Optional

import serial

from app.config.settings import settings

logger = logging.getLogger(__name__)
FrameHandler = Callable[[str], None]


class UartClient:
    def __init__(self, frame_handler: FrameHandler) -> None:
        self._frame_handler = frame_handler
        self._serial: Optional[serial.Serial] = None
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._read_loop, daemon=True)
        self._write_lock = threading.Lock()

    @property
    def is_ready(self) -> bool:
        return bool(self._serial and self._serial.is_open)

    def start(self) -> None:
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        if self._serial and self._serial.is_open:
            self._serial.close()
        self._thread.join(timeout=2.0)

    def send(self, payload: bytes) -> None:
        with self._write_lock:
            if not self._serial or not self._serial.is_open:
                raise RuntimeError('UART port is not open')
            if settings.log_raw_uart:
                logger.info('UART TX raw=%r', payload)
            self._serial.write(payload)
            self._serial.flush()

    def _open(self) -> None:
        self._serial = serial.Serial(
            port=settings.uart_port,
            baudrate=settings.uart_baudrate,
            bytesize=settings.uart_bytesize,
            parity=settings.uart_parity,
            stopbits=settings.uart_stopbits,
            timeout=settings.uart_timeout_sec,
            write_timeout=settings.uart_write_timeout_sec,
        )
        logger.info('UART opened port=%s baudrate=%s', settings.uart_port, settings.uart_baudrate)

    def _read_loop(self) -> None:
        while not self._stop.is_set():
            try:
                if not self._serial or not self._serial.is_open:
                    self._open()
                raw = self._serial.readline()
                if not raw:
                    continue
                if settings.log_raw_uart:
                    logger.info('UART RX raw=%r', raw)
                line = raw.decode('utf-8', errors='replace').strip()
                if line:
                    self._frame_handler(line)
            except Exception as exc:
                logger.warning('UART read loop error: %s', exc)
                try:
                    if self._serial and self._serial.is_open:
                        self._serial.close()
                except Exception:
                    pass
                time.sleep(settings.uart_reconnect_sec)
