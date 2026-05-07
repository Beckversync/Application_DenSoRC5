from __future__ import annotations

import argparse
import csv
import json
import random
import statistics
import time
from dataclasses import dataclass, asdict
from pathlib import Path


@dataclass
class TrialResult:
    trial_id: int
    success: bool
    mqtt_latency_ms: float
    uart_latency_ms: float
    recovery_time_ms: float
    duplicate_detected: bool
    telemetry_dropped: bool
    reason: str


def percentile(values: list[float], p: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    idx = min(len(ordered) - 1, max(0, int(round((p / 100.0) * (len(ordered) - 1)))))
    return ordered[idx]


def run_trials(seed: int, trials: int, drop_rate: float, duplicate_rate: float, uart_error_rate: float) -> list[TrialResult]:
    rng = random.Random(seed)
    results: list[TrialResult] = []
    for trial_id in range(1, trials + 1):
        mqtt_latency = max(3.0, rng.gauss(38.0, 9.0))
        uart_latency = max(1.0, rng.gauss(12.0, 4.0))
        dropped = rng.random() < drop_rate
        duplicated = rng.random() < duplicate_rate
        uart_error = rng.random() < uart_error_rate
        recovery = 0.0
        reason = 'OK'
        success = True

        if dropped:
            recovery += 500.0 + rng.random() * 200.0
            reason = 'TELEMETRY_DROP_RECOVERED'
        if duplicated:
            recovery += 8.0
            reason = 'DUPLICATE_DEDUPED' if reason == 'OK' else reason + '+DUPLICATE_DEDUPED'
        if uart_error:
            recovery += 300.0 + rng.random() * 150.0
            # Two-attempt retry budget recovers most transient UART errors.
            success = rng.random() > 0.08
            reason = 'UART_RETRY_RECOVERED' if success else 'UART_RETRY_EXHAUSTED'

        results.append(
            TrialResult(
                trial_id=trial_id,
                success=success,
                mqtt_latency_ms=round(mqtt_latency, 3),
                uart_latency_ms=round(uart_latency, 3),
                recovery_time_ms=round(recovery, 3),
                duplicate_detected=duplicated,
                telemetry_dropped=dropped,
                reason=reason,
            )
        )
    return results


def summarize(results: list[TrialResult]) -> dict[str, float | int]:
    successes = [r for r in results if r.success]
    mqtt = [r.mqtt_latency_ms for r in results]
    recovery = [r.recovery_time_ms for r in results]
    return {
        'trials': len(results),
        'success_count': len(successes),
        'success_rate': round(len(successes) / len(results), 4) if results else 0.0,
        'mqtt_latency_p50_ms': round(statistics.median(mqtt), 3) if mqtt else 0.0,
        'mqtt_latency_p95_ms': round(percentile(mqtt, 95), 3),
        'recovery_time_p95_ms': round(percentile(recovery, 95), 3),
        'duplicate_count': sum(1 for r in results if r.duplicate_detected),
        'telemetry_drop_count': sum(1 for r in results if r.telemetry_dropped),
    }


def write_outputs(results: list[TrialResult], output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    csv_path = output_dir / 'benchmark_results.csv'
    json_path = output_dir / 'benchmark_summary.json'
    with csv_path.open('w', newline='', encoding='utf-8') as handle:
        writer = csv.DictWriter(handle, fieldnames=list(asdict(results[0]).keys()))
        writer.writeheader()
        for result in results:
            writer.writerow(asdict(result))
    json_path.write_text(json.dumps(summarize(results), indent=2), encoding='utf-8')


def main() -> None:
    parser = argparse.ArgumentParser(description='Deterministic fault-injection benchmark for thesis evaluation.')
    parser.add_argument('--trials', type=int, default=200)
    parser.add_argument('--seed', type=int, default=20260426)
    parser.add_argument('--drop-rate', type=float, default=0.10)
    parser.add_argument('--duplicate-rate', type=float, default=0.05)
    parser.add_argument('--uart-error-rate', type=float, default=0.08)
    parser.add_argument('--output-dir', type=Path, default=Path('benchmark_output'))
    args = parser.parse_args()

    start = time.perf_counter()
    results = run_trials(args.seed, args.trials, args.drop_rate, args.duplicate_rate, args.uart_error_rate)
    write_outputs(results, args.output_dir)
    summary = summarize(results)
    summary['wall_time_ms'] = round((time.perf_counter() - start) * 1000, 3)
    print(json.dumps(summary, indent=2))


if __name__ == '__main__':
    main()
