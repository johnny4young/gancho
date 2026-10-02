#!/usr/bin/env python3
"""Diagnostic branch only: sample a synthetic app when a phase stalls."""
import json
import re
import signal
import subprocess
import sys
import threading
from pathlib import Path

PATTERN = re.compile(r"request ([A-F0-9-]{36}) uptime [0-9.]+ phase ([a-z-]+) priority [0-9]+")


def phase_record(record):
    if not isinstance(record, dict):
        return None
    match = PATTERN.fullmatch(record.get("eventMessage", ""))
    pid = record.get("processID")
    if not match or not isinstance(pid, int) or pid <= 0:
        return None
    return match[1], match[2], pid


def main(directory):
    directory.mkdir(parents=True, exist_ok=True)
    stopped = threading.Event()
    completed = {}
    lock = threading.Lock()
    probes = []

    def sample_if_stalled(nonce, phase, pid, completion):
        if completion.wait(2) or stopped.is_set():
            return
        target = directory / f"{nonce}-{phase}.sample.txt"
        with (directory / f"{nonce}-{phase}.status.txt").open("w") as status:
            try:
                result = subprocess.run(
                    ["/usr/bin/sample", str(pid), "1", "1", "-file", str(target)],
                    stdout=status, stderr=subprocess.STDOUT, timeout=10, check=False,
                )
                status.write(f"\nexit={result.returncode}\n")
            except subprocess.TimeoutExpired:
                status.write("\nsample timed out\n")

    predicate = 'subsystem == "com.johnny4young.gancho.translation-diagnostic"'
    with (directory / "stream-errors.txt").open("w") as errors:
        stream = subprocess.Popen(
            ["/usr/bin/log", "stream", "--style", "ndjson", "--predicate", predicate],
            stdout=subprocess.PIPE, stderr=errors, text=True,
        )

        def stop(_signal, _frame):
            stopped.set()
            stream.terminate()

        signal.signal(signal.SIGTERM, stop)
        signal.signal(signal.SIGINT, stop)
        try:
            for line in stream.stdout:
                try:
                    value = json.loads(line)
                except json.JSONDecodeError:
                    continue
                record = phase_record(value)
                if record is None:
                    continue
                nonce, phase, pid = record
                with lock:
                    for start, finish in [("action-entered", "task-entered"),
                                          ("fixture-native-returned", "result-applied")]:
                        key = (nonce, start)
                        if phase == finish:
                            completed.setdefault(key, threading.Event()).set()
                        elif phase == start and len(probes) < 100:
                            event = completed.setdefault(key, threading.Event())
                            probe = threading.Thread(
                                target=sample_if_stalled,
                                args=(nonce, start, pid, event), daemon=True,
                            )
                            probes.append(probe)
                            probe.start()
        finally:
            stopped.set()
            stream.terminate()
            stream.wait(timeout=5)
            for probe in probes:
                probe.join(timeout=12)


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-test"]:
        assert phase_record({}) is None
        assert phase_record({"eventMessage": "clipboard text", "processID": 1}) is None
        sample = {"eventMessage": "request 12345678-1234-1234-1234-123456789ABC uptime 1.2 phase action-entered priority 25", "processID": 42}
        assert phase_record(sample) == ("12345678-1234-1234-1234-123456789ABC", "action-entered", 42)
        assert phase_record(dict(sample, processID="42; injection")) is None
        print("Diagnostic phase parser self-test passed")
    elif len(sys.argv) == 2:
        main(Path(sys.argv[1]))
    else:
        raise SystemExit("usage: translation-latency-probe.py OUTPUT_DIR | --self-test")
