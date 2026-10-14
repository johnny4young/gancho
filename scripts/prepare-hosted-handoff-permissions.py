#!/usr/bin/env python3
"""Grant real event/AX access only on a disposable GitHub-hosted test VM."""

import os
from pathlib import Path
import plistlib
import sqlite3
import subprocess
import sys
import tempfile
import time


def require_disposable_host(environment):
    if not (
        environment.get("GITHUB_ACTIONS") == "true"
        and environment.get("RUNNER_ENVIRONMENT") == "github-hosted"
        and environment.get("SUDO_USER") == "runner"
        and environment.get("RUNNER_TEMP", "").startswith("/Users/runner/")
    ):
        raise RuntimeError("Permission preparation is restricted to disposable hosted runners")


def grant(connection, identifier, requirement):
    for service in ("kTCCServiceAccessibility", "kTCCServicePostEvent"):
        connection.execute(
            """INSERT OR REPLACE INTO access
               (service, client, client_type, auth_value, auth_reason, auth_version,
                csreq, indirect_object_identifier, flags, last_modified)
               VALUES (?, ?, 0, 2, 4, 1, ?, 'UNUSED', 0, ?)""",
            (service, identifier, requirement, int(time.time())),
        )


def self_test():
    hosted = {"GITHUB_ACTIONS": "true", "RUNNER_ENVIRONMENT": "github-hosted",
              "SUDO_USER": "runner", "RUNNER_TEMP": "/Users/runner/work/_temp"}
    invalid = [{}, dict(os.environ)]
    invalid[1].pop("GITHUB_ACTIONS", None)
    for key in hosted:
        environment = dict(hosted)
        environment[key] = "unexpected"
        invalid.append(environment)
    for environment in invalid:
        try:
            require_disposable_host(environment)
        except RuntimeError:
            pass
        else:
            raise AssertionError("A local host must be rejected")
    require_disposable_host(hosted)
    connection = sqlite3.connect(":memory:")
    connection.execute(
        """CREATE TABLE access (service TEXT, client TEXT, client_type INTEGER,
           auth_value INTEGER, auth_reason INTEGER, auth_version INTEGER,
           csreq BLOB, indirect_object_identifier TEXT, flags INTEGER, last_modified INTEGER,
           PRIMARY KEY (service, client, client_type, indirect_object_identifier))"""
    )
    grant(connection, "synthetic.fixture", b"synthetic-requirement")
    grant(connection, "synthetic.fixture", b"updated-requirement")
    assert connection.execute("SELECT COUNT(*) FROM access").fetchone()[0] == 2
    assert all(row == (2, b"updated-requirement") for row in connection.execute(
        "SELECT auth_value, csreq FROM access"))
    print("Hosted handoff permission preparation self-test passed")


def main():
    if sys.argv[1:] == ["--self-test"]:
        self_test()
        return
    require_disposable_host(os.environ)
    if os.geteuid() != 0 or len(sys.argv) != 3:
        raise RuntimeError("Expected root on the hosted VM and exactly two test application paths")
    applications = [Path(argument).resolve() for argument in sys.argv[1:]]
    expected = {"com.johnny4young.gancho", "com.johnny4young.gancho.GanchoSignedIntegrationUITests.xctrunner"}
    records = []
    for application in applications:
        if "/build/" not in str(application) or not str(application).startswith("/Users/runner/"):
            raise RuntimeError("Only freshly built hosted application paths are accepted")
        with (application / "Contents/Info.plist").open("rb") as handle:
            identifier = plistlib.load(handle)["CFBundleIdentifier"]
        if identifier not in expected:
            raise RuntimeError("Unexpected application identifier for permission preparation")
        subprocess.run(["codesign", "--verify", "--strict", str(application)], check=True)
        details = subprocess.check_output(
            ["codesign", "-d", "-r-", str(application)], stderr=subprocess.STDOUT, text=True
        )
        requirements = [line.removeprefix("designated => ") for line in details.splitlines()
                        if line.startswith("designated => ")]
        if len(requirements) != 1:
            raise RuntimeError("Expected one designated code requirement")
        with tempfile.TemporaryDirectory(dir=os.environ["RUNNER_TEMP"]) as temporary:
            requirement = Path(temporary) / "requirement.bin"
            subprocess.run(["csreq", "-r", "=" + requirements[0], "-b", str(requirement)], check=True)
            records.append((identifier, requirement.read_bytes()))
    if {identifier for identifier, requirement in records} != expected:
        raise RuntimeError("Both the real sender and its dedicated UI runner are required")
    database = "/Library/Application Support/com.apple.TCC/TCC.db"
    with sqlite3.connect(f"file:{database}?mode=rw", uri=True) as connection:
        for identifier, requirement in records:
            grant(connection, identifier, requirement)
    print("Prepared real Accessibility and event posting for two disposable test processes")


if __name__ == "__main__":
    main()
