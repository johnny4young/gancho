#!/usr/bin/env python3
"""Print the `-only-testing` arguments of one macOS UI shard.

    python3 scripts/ui_test_shard.py 2/3

Classes are read from the test sources, so a new class always lands in a shard. Measured
seconds only balance the shards; a class without a measurement counts as one minute.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "Tests" / "GanchoUITests"
CLASS = re.compile(r"^(?:final )?class (\w+)\s*:\s*\w*XCTestCase", re.M)


def classes() -> list[str]:
    found = set()
    for path in ROOT.rglob("*.swift"):
        found.update(CLASS.findall(path.read_text()))
    return sorted(found)


def shards(names: list[str], seconds: dict[str, int], count: int) -> list[list[str]]:
    buckets: list[tuple[int, list[str]]] = [(0, []) for _ in range(count)]
    for name in sorted(names, key=lambda n: (-seconds.get(n, 60), n)):
        index = min(range(count), key=lambda i: (buckets[i][0], i))
        total, members = buckets[index]
        buckets[index] = (total + seconds.get(name, 60), members + [name])
    return [members for _, members in buckets]


def main() -> None:
    index, count = (int(part) for part in sys.argv[1].split("/"))
    seconds = json.loads((ROOT / "shard-seconds.json").read_text())
    for name in sorted(shards(classes(), seconds, count)[index - 1]):
        print(f"-only-testing:GanchoUITests/{name}")


if __name__ == "__main__":
    main()
