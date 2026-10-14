#!/usr/bin/env python3
"""Generate an isolated native fixture from the canonical, unmodified dependency."""

import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import uuid


def prepare(repo, output, checkout):
    lock = json.loads((repo / "Dependencies/Package.resolved").read_text())
    pins = [pin for pin in lock["pins"] if pin["identity"] == "keyboardshortcuts"]
    if len(pins) != 1:
        raise ValueError("Expected one canonical KeyboardShortcuts pin")
    pin = pins[0]
    version = pin["state"]["version"]
    revision = pin["state"]["revision"]
    if not re.fullmatch(r"\d+\.\d+\.\d+", version) or not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError("Invalid canonical KeyboardShortcuts version or revision")
    spec = (repo / "project.yml").read_text()
    requirement = re.search(r"^  KeyboardShortcuts:\n((?:    .*\n)+)", spec, re.MULTILINE)
    if not requirement or not re.search(
        rf"^    exactVersion: [\"']?{re.escape(version)}[\"']?\s*$",
        requirement[1], re.MULTILINE
    ):
        raise ValueError("project.yml must pin the exact version in the canonical app lock")
    canary = (repo / "scripts/upstream-pins.env").read_text()
    if not re.search(rf"^KEYBOARDSHORTCUTS={re.escape(version)}$", canary, re.MULTILINE):
        raise ValueError("The upstream canary and canonical app lock disagree")

    identity = os.environ.get("SHORTCUT_MENU_SIGN_IDENTITY")
    if not identity:
        raise ValueError("Set SHORTCUT_MENU_SIGN_IDENTITY to an existing trusted signing identity")
    dependency = output / "KeyboardShortcuts"
    dependency.mkdir()
    archive = subprocess.check_output(["git", "-C", str(checkout), "archive", revision])
    subprocess.run(["tar", "-xf", "-", "-C", str(dependency)], input=archive, check=True)
    identifier = "com.johnny4young.gancho.tests.shortcut-menu." + uuid.uuid4().hex
    recorder_identifier = "com.johnny4young.gancho.tests.shortcut-recorder." + uuid.uuid4().hex
    sources = repo / "Tests/KeyboardShortcutsAcceptance"
    build_settings = {
        "SWIFT_VERSION": "6.0",
        "SWIFT_APPROACHABLE_CONCURRENCY": "YES",
        "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
        "SWIFT_STRICT_CONCURRENCY": "complete",
        "SWIFT_TREAT_WARNINGS_AS_ERRORS": "YES",
        "CODE_SIGN_STYLE": "Manual",
        "CODE_SIGN_IDENTITY": identity,
        "CODE_SIGN_INJECT_BASE_ENTITLEMENTS": "NO",
        "ENABLE_HARDENED_RUNTIME": "YES",
        "ENABLE_DEBUG_DYLIB": "NO",
    }
    project = {
        "name": "ShortcutMenuFixture",
        "settings": {"base": build_settings},
        "packages": {"KeyboardShortcuts": {"path": str(dependency)}},
        "targets": {
            "ShortcutMenuFixture": {
                "type": "application", "platform": "macOS", "deploymentTarget": "15.4",
                "sources": [
                    {"path": str(sources / "FixtureApp.swift")},
                    {"path": str(repo / "Apps/GanchoMac/GlobalShortcuts.swift")},
                ],
                "info": {"path": "FixtureInfo.plist", "properties": {
                    "NSPrincipalClass": "MenuFixtureApplication",
                    "FixtureDependencyVersion": version, "FixtureDependencyRevision": revision,
                }},
                "settings": {"base": {"PRODUCT_BUNDLE_IDENTIFIER": identifier}},
                "dependencies": [{"package": "KeyboardShortcuts"}],
            },
            "ShortcutMenuUITests": {
                "type": "bundle.ui-testing", "platform": "macOS", "deploymentTarget": "15.4",
                "sources": [{"path": str(sources / "ShortcutMenuUITests.swift")}],
                "settings": {"base": {
                    "PRODUCT_BUNDLE_IDENTIFIER": identifier + ".runner",
                    "GENERATE_INFOPLIST_FILE": "YES",
                    "SWIFT_DEFAULT_ACTOR_ISOLATION": "nonisolated",
                    "ENABLE_HARDENED_RUNTIME": "NO",
                }},
                "dependencies": [{"target": "ShortcutMenuFixture"}],
            },
            "ShortcutRecorderFixture": {
                "type": "application", "platform": "macOS", "deploymentTarget": "15.4",
                "sources": [
                    {"path": str(sources / "RecorderFixtureApp.swift")},
                    {"path": str(repo / "Apps/GanchoMac/GlobalShortcuts.swift")},
                    {"path": str(repo / "Apps/GanchoMac/ShortcutRecorder.swift")},
                    {"path": str(repo / "Packages/GanchoKit/Sources/ClipboardCore/ShortcutConflicts.swift")},
                ],
                "info": {"path": "RecorderFixtureInfo.plist", "properties": {
                    "FixtureDependencyVersion": version, "FixtureDependencyRevision": revision,
                }},
                "settings": {"base": {"PRODUCT_BUNDLE_IDENTIFIER": recorder_identifier}},
                "dependencies": [{"package": "KeyboardShortcuts"}],
            },
            "ShortcutRecorderUITests": {
                "type": "bundle.ui-testing", "platform": "macOS", "deploymentTarget": "15.4",
                "sources": [{"path": str(sources / "ShortcutRecorderUITests.swift")}],
                "settings": {"base": {
                    "PRODUCT_BUNDLE_IDENTIFIER": recorder_identifier + ".runner",
                    "GENERATE_INFOPLIST_FILE": "YES",
                    "SWIFT_DEFAULT_ACTOR_ISOLATION": "nonisolated",
                    "ENABLE_HARDENED_RUNTIME": "NO",
                }},
                "dependencies": [{"target": "ShortcutRecorderFixture"}],
            },
        },
        "schemes": {
            "ShortcutMenuFixture": {
                "build": {"targets": {"ShortcutMenuFixture": "all"}},
                "test": {"targets": ["ShortcutMenuUITests"], "gatherCoverageData": False},
            },
            "ShortcutRecorderFixture": {
                "build": {"targets": {"ShortcutRecorderFixture": "all"}},
                "test": {"targets": ["ShortcutRecorderUITests"], "gatherCoverageData": False},
            },
        },
    }
    (output / "project.json").write_text(json.dumps(project, indent=2) + "\n")
    (output / "manifest.json").write_text(json.dumps({
        "version": version, "revision": revision, "bundleIdentifier": identifier,
        "sourceCheckout": str(checkout), "sourceRequirement": "Dependencies/Package.resolved",
        "snapshotPath": str(output / "snapshot.json"),
        "recorderBundleIdentifier": recorder_identifier,
        "recorderSnapshotPath": str(output / "recorder-snapshot.json"),
        "productionSourceSHA256": {
            str(path.relative_to(repo)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in [
                repo / "Apps/GanchoMac/GlobalShortcuts.swift",
                repo / "Apps/GanchoMac/ShortcutRecorder.swift",
                repo / "Packages/GanchoKit/Sources/ClipboardCore/ShortcutConflicts.swift",
            ]
        },
        "fixtureSourceSHA256": {
            path.name: hashlib.sha256(path.read_bytes()).hexdigest()
            for path in [
                sources / "FixtureApp.swift",
                sources / "ShortcutMenuUITests.swift",
                sources / "RecorderFixtureApp.swift",
                sources / "ShortcutRecorderUITests.swift",
                sources / "prepare.py",
            ]
        },
        "scope": "native dependency menu and recorder fixtures",
    }, indent=2) + "\n")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit("Usage: prepare.py <repository> <fresh-output-directory> <dependency-git-repository>")
    prepare(*(Path(argument).resolve() for argument in sys.argv[1:]))
