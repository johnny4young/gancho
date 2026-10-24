#!/usr/bin/env python3
"""Run the synthetic panel regression without discovering OS-integration suites."""
import argparse
import io
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import tarfile
import tempfile
import time

REPO = Path(__file__).resolve().parents[1]
MODULES = ("GanchoKit", "ClipboardCore", "GanchoAI", "GanchoAppCore")
REVISIONS = {
    "grdb.swift": "https://github.com/johnny4young/GRDB.swift.git",
    "sqlcipher.swift": "https://github.com/sqlcipher/SQLCipher.swift.git",
    "sauce": "https://github.com/Clipy/Sauce.git",
}


def run(argv, root, environment, label, timeout=600):
    started = time.monotonic()
    record = {"argv": argv, "timeout_seconds": timeout}
    with (root / (label + ".stdout")).open("wb") as out, (root / (label + ".stderr")).open("wb") as err:
        child = subprocess.Popen(argv, env=environment, cwd=REPO, stdout=out, stderr=err,
                                 start_new_session=True)
        record["pid"] = child.pid
        try:
            code = child.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(child.pid, signal.SIGTERM)
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(child.pid, signal.SIGKILL)
                child.wait()
            code = 124
    record.update(exit_code=code, duration_seconds=time.monotonic() - started)
    (root / (label + ".json")).write_text(json.dumps(record, indent=2) + "\n")
    print(f"{label}: exit {code}", flush=True)
    if code:
        print((root / (label + ".stdout")).read_text(errors="replace"))
        print((root / (label + ".stderr")).read_text(errors="replace"))
    return code


def copy_baseline(ref, root):
    sha = subprocess.check_output(["git", "rev-parse", "--verify", ref + "^{commit}"],
                                  cwd=REPO, text=True).strip()
    paths = ["Packages/GanchoKit/Sources/" + name for name in MODULES]
    data = subprocess.check_output(["git", "archive", "--format=tar", sha, *paths], cwd=REPO)
    with tarfile.open(fileobj=io.BytesIO(data)) as archive:
        for member in archive:
            prefix = "Packages/GanchoKit/Sources/"
            if not member.name.startswith(prefix):
                if member.isdir() and prefix.startswith(member.name.rstrip("/") + "/"):
                    continue
                raise ValueError("Unexpected source archive prefix")
            relative = Path(member.name[len(prefix):])
            if ".." in relative.parts or relative.is_absolute():
                raise ValueError("Invalid source archive path")
            target = root / "Sources" / relative
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
            elif member.isfile():
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(archive.extractfile(member).read())
            else:
                raise ValueError("Source archive must not contain links or special files")
    lock = subprocess.check_output(["git", "show", sha + ":Packages/GanchoKit/Package.resolved"], cwd=REPO)
    return sha, json.loads(lock)


def prepare(root, baseline):
    if baseline:
        sha, lock = copy_baseline(baseline, root)
    else:
        sha = "working-tree"
        lock = json.loads((REPO / "Packages/GanchoKit/Package.resolved").read_text())
        for name in MODULES:
            shutil.copytree(REPO / "Packages/GanchoKit/Sources" / name, root / "Sources" / name)
    tests = root / "Tests/PanelStoreRefreshRegressionTests"
    tests.mkdir(parents=True)
    source = REPO / "Packages/GanchoKit/Tests/GanchoAppCoreTests"
    text = (source / "PanelStoreRefreshTests.swift").read_text()
    if baseline:
        # Reproduce the reviewed old shell callback, not an API absent at that SHA.
        needle = "        await search.refreshAfterStoreChange(preview: preview)"
        assert text.count(needle) == 1, "Review baseline adapter after test changes"
        text = text.replace(needle, """        if recentChanged {
            await search.refreshSourceApps()
            await search.refresh()
            await preview.load(
                search.selectedItem, loadMetadata: { try await store.item(id: $0) },
                loadContent: { try await store.content(for: $0) })
        }""")
        print("Baseline adapter: old recent-value callback; no native GUI execution", flush=True)
    else:
        shutil.copyfile(source / "PanelPreviewInvalidationTests.swift", tests / "PanelPreviewInvalidationTests.swift")
    (tests / "PanelStoreRefreshTests.swift").write_text(text)
    pins = {pin["identity"]: pin["state"]["revision"] for pin in lock["pins"] if pin["identity"] in REVISIONS}
    assert set(pins) == set(REVISIONS)
    assert all(re.fullmatch(r"[a-f0-9]{40}", value) for value in pins.values())
    dependencies = ",\n".join(f'        .package(url: "{url}", revision: "{pins[name]}")'
                                for name, url in REVISIONS.items())
    (root / "Package.swift").write_text('''// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "PanelStoreRefreshRegression", platforms: [.macOS("15.4")],
    dependencies: [
''' + dependencies + '''
    ], targets: [
        .target(name: "GanchoKit", dependencies: [.product(name: "GRDB", package: "GRDB.swift")], swiftSettings: [.define("SQLITE_HAS_CODEC")]),
        .target(name: "ClipboardCore", dependencies: ["GanchoKit", .product(name: "Sauce", package: "Sauce")]),
        .target(name: "GanchoAI", dependencies: ["GanchoKit"]),
        .target(name: "GanchoAppCore", dependencies: ["GanchoKit", "GanchoAI", "ClipboardCore"]),
        .testTarget(name: "PanelStoreRefreshRegressionTests", dependencies: ["GanchoKit", "GanchoAppCore"])
    ])
''')
    (root / "fixture.json").write_text(json.dumps({"source": sha, "pins": pins,
        "baseline_adapter": bool(baseline), "synthetic_clips_per_case": 51}, indent=2) + "\n")
    return pins


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", help="Existing local commit to reproduce with the old callback adapter")
    parser.add_argument("--output", type=Path, help="New owned directory to retain source copies and logs")
    args = parser.parse_args()
    if args.output:
        root = args.output.resolve()
        root.mkdir(mode=0o700, parents=False, exist_ok=False)
    else:
        root = Path(tempfile.mkdtemp(prefix="gancho-panel-refresh-"))
    pins = prepare(root, args.baseline)
    for name in ("home", "tmp", "cache", "config", "security"):
        (root / name).mkdir()
    environment = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": str(root / "home"),
        "TMPDIR": str(root / "tmp"), "CLANG_MODULE_CACHE_PATH": str(root / "cache/clang"),
        "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_TERMINAL_PROMPT": "0",
        "GIT_CONFIG_COUNT": "2", "GIT_CONFIG_KEY_0": "credential.helper", "GIT_CONFIG_VALUE_0": "",
        "GIT_CONFIG_KEY_1": "core.hooksPath", "GIT_CONFIG_VALUE_1": "/dev/null"}
    developer = os.environ.get("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
    environment["DEVELOPER_DIR"] = developer
    flags = ["--package-path", str(root), "--scratch-path", str(root / "build"),
        "--cache-path", str(root / "cache"), "--config-path", str(root / "config"),
        "--security-path", str(root / "security"), "--manifest-cache", "local", "--disable-dependency-cache"]
    code = run(["/usr/bin/swift", "package", *flags, "resolve"], root, environment, "resolve")
    if code:
        return code
    actual = {p["identity"]: p["state"]["revision"] for p in json.loads((root / "Package.resolved").read_text())["pins"]}
    assert actual == pins, "Resolved source revisions differ; do not execute tests"
    return run(["/usr/bin/swift", "test", *flags, "--disable-automatic-resolution", "--jobs", "1", "--no-parallel"],
               root, environment, "tests")


if __name__ == "__main__":
    raise SystemExit(main())
