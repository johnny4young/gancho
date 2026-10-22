#!/usr/bin/env python3
"""Copy `design-snapshot-<name>` attachments out of an exported xcresult."""
import json
import re
import pathlib
import shutil
import sys

PREFIX = "design-snapshot-"
exported, output = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
output.mkdir(parents=True, exist_ok=True)
count = 0
for test in json.loads((exported / "manifest.json").read_text()):
    for item in test.get("attachments", []):
        name = item.get("suggestedHumanReadableName", "")
        if not name.startswith(PREFIX):
            continue
        # xcresulttool appends "_<index>_<uuid>.<ext>" to the attachment name.
        stem = name[len(PREFIX):].rsplit("_", 2)[0]
        if not re.fullmatch(r"[A-Za-z0-9-]+", stem):
            sys.exit(f"refusing unsafe snapshot name: {stem!r}")
        shutil.copyfile(exported / item["exportedFileName"], output / f"{stem}.png")
        count += 1
print(f"✓ collected {count} design snapshot(s) into {output}")
sys.exit(0 if count else 1)
