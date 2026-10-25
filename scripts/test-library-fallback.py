#!/usr/bin/env python3
"""Reproduce Library RAM adapter behavior without starting the app composition root."""
import argparse
import hashlib
import io
import json
import os
import pathlib
import shutil
import signal
import subprocess
import sys
import tarfile
import time

REPO = pathlib.Path(__file__).resolve().parents[1]
FIXTURES = REPO / "scripts/fixtures/library-fallback"
MODULES = ("GanchoKit", "ClipboardCore", "GanchoAI", "GanchoAppCore")
MODEL_TESTS = ("LibraryClipListModelTests", "LibraryPagerTests", "LibraryProMeterTests", "BoardDropTests",
               "RetentionPassTests", "ClipListSearchReaderTests", "ClipListSearchOutcomeTests",
               "HistoryListViewModelTests", "PanelStoreChangeSelectionTests", "PanelStoreRefreshTests")
STORE_TESTS = ("LibraryBrowseTests", "RetentionEngineTests")
APP_SOURCE = "Apps/GanchoMac/AppModel+Library.swift"
LOCK = "Packages/GanchoKit/Package.resolved"
ALLOWED_FILES = {APP_SOURCE, LOCK} | {
    f"Packages/GanchoKit/Tests/{folder}/{name}.swift"
    for folder, names in (("GanchoAppCoreTests", MODEL_TESTS), ("GanchoKitTests", STORE_TESTS))
    for name in names
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--output", type=pathlib.Path, required=True)
parser.add_argument("--revision", help="Exact local commit for production inputs; fixtures stay from this script's checkout")
parser.add_argument("--working-tree", action="store_true", help="Explicitly test current uncommitted production bytes")
parser.add_argument("--offline-cache", type=pathlib.Path, help="Copy a verified exact-pin SwiftPM scratch directory")
parser.add_argument("--mode", choices=("regressions", "full"), default="full")
args = parser.parse_args()
if args.revision and args.working_tree:
    parser.error("Choose a revision or the working tree")
root = args.output.resolve()
if root == REPO or root.is_relative_to(REPO):
    parser.error("Output must be outside the source checkout")
root.mkdir(mode=0o700, exist_ok=False)


def git(*argv):
    return subprocess.check_output(["/usr/bin/git", "--no-optional-locks", *argv], cwd=REPO)


revision = git("rev-parse", "--verify", (args.revision or "HEAD") + "^{commit}").decode().strip()


def source(path):
    assert path in ALLOWED_FILES, "Only explicit safe source/test paths may be read"
    return (REPO / path).read_bytes() if args.working_tree else git("show", revision + ":" + path)


prefix = "Packages/GanchoKit/Sources/"
if args.working_tree:
    for name in MODULES:
        base = REPO / prefix / name
        for path in sorted(base.rglob("*")):
            assert not path.is_symlink(), "No source symlinks"
            if path.is_file():
                destination = root / "Sources" / name / path.relative_to(base)
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(path, destination)
else:
    data = git("archive", "--format=tar", revision, *[prefix + name for name in MODULES])
    with tarfile.open(fileobj=io.BytesIO(data)) as archive:
        for member in archive:
            if not member.name.startswith(prefix):
                assert member.isdir() and prefix.startswith(member.name.rstrip("/") + "/")
                continue
            relative = pathlib.Path(member.name[len(prefix):])
            assert not relative.is_absolute() and ".." not in relative.parts and relative.parts[0] in MODULES
            destination = root / "Sources" / relative
            if member.isdir():
                destination.mkdir(parents=True, exist_ok=True)
            else:
                assert member.isfile(), "No archive links or special files"
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(archive.extractfile(member).read())
for folder, names, target in (("GanchoAppCoreTests", MODEL_TESTS, "SafeModelTests"),
                              ("GanchoKitTests", STORE_TESTS, "SafeStoreTests")):
    for name in names:
        destination = root / "Tests" / target / (name + ".swift")
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(source(f"Packages/GanchoKit/Tests/{folder}/{name}.swift"))
adapter = root / "Tests/LibraryAdapterTests"
adapter.mkdir()
(adapter / "AppModel+Library.swift").write_bytes(source(APP_SOURCE))
for path in sorted(FIXTURES.glob("*.swift")):
    assert not path.is_symlink()
    shutil.copyfile(path, adapter / path.name)

urls = {"grdb.swift": "https://github.com/johnny4young/GRDB.swift.git",
        "sqlcipher.swift": "https://github.com/sqlcipher/SQLCipher.swift.git", "sauce": "https://github.com/Clipy/Sauce.git"}
canonical = json.loads(source(LOCK))
pins = {p["identity"]: p["state"]["revision"] for p in canonical["pins"] if p["identity"] in urls}
assert set(pins) == set(urls)
dependencies = ",\n".join(f'        .package(url: "{url}", revision: "{pins[name]}")' for name, url in urls.items())
(root / "Package.swift").write_text('''// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "LibraryFallbackRegression", platforms: [.macOS("15.4")], dependencies: [
''' + dependencies + '''
    ], targets: [
        .target(name: "GanchoKit", dependencies: [.product(name: "GRDB", package: "GRDB.swift")], swiftSettings: [.define("SQLITE_HAS_CODEC")]),
        .target(name: "ClipboardCore", dependencies: ["GanchoKit", .product(name: "Sauce", package: "Sauce")]),
        .target(name: "GanchoAI", dependencies: ["GanchoKit"]),
        .target(name: "GanchoAppCore", dependencies: ["GanchoKit", "GanchoAI", "ClipboardCore"]),
        .testTarget(name: "SafeModelTests", dependencies: ["GanchoKit", "GanchoAppCore"]),
        .testTarget(name: "SafeStoreTests", dependencies: ["GanchoKit", .product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "LibraryAdapterTests", dependencies: ["GanchoKit", "GanchoAppCore", .product(name: "GRDB", package: "GRDB.swift")])
    ])
''')
for name in ("home", "tmp", "cache", "config", "security", "build", "fixtures", "logs"):
    (root / name).mkdir()
env = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": str(root / "home"),
       "CFFIXED_USER_HOME": str(root / "home"), "TMPDIR": str(root / "tmp"),
       "DEVELOPER_DIR": os.environ.get("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer"),
       "LC_ALL": "en_US.UTF-8", "GANCHO_SAFE_FIXTURE_ROOT": str(root / "fixtures"),
       "CLANG_MODULE_CACHE_PATH": str(root / "cache/clang"), "SWIFTPM_MODULECACHE_OVERRIDE": str(root / "cache/swift"),
       "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_TERMINAL_PROMPT": "0"}
records = []


def run(label, argv, timeout=180):
    record = {"label": label, "argv": argv, "cwd": str(root), "environment_allowlist": env,
              "timeout_seconds": timeout}
    start = time.monotonic()
    with (root / "logs" / (label + ".stdout")).open("wb") as out, (root / "logs" / (label + ".stderr")).open("wb") as err:
        child = subprocess.Popen(argv, cwd=root, env=env, stdout=out, stderr=err, start_new_session=True)
        record["owned_pid"] = child.pid
        try:
            code = child.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(child.pid, signal.SIGTERM)
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(child.pid, signal.SIGKILL)
                child.wait()
            code = child.returncode
            record["timed_out"] = True
    record.update(exit_code=code, duration_seconds=time.monotonic() - start)
    records.append(record)
    (root / "commands.json").write_text(json.dumps(records, indent=2) + "\n")
    print(json.dumps({k: record[k] for k in ("label", "exit_code", "duration_seconds")}), flush=True)
    return code


flags = ["--package-path", str(root), "--scratch-path", str(root / "build"), "--cache-path", str(root / "cache"),
         "--config-path", str(root / "config"), "--security-path", str(root / "security"),
         "--manifest-cache", "local", "--disable-dependency-cache", "--jobs", "1"]
if args.offline_cache:
    cache = args.offline_cache.resolve()
    state = json.loads((cache / "workspace-state.json").read_text())
    actual = {entry["packageRef"]["identity"]: entry["state"]["checkoutState"]["revision"] for entry in state["object"]["dependencies"]}
    assert actual == pins, "Offline pins differ"
    for name in ("checkouts", "repositories", "artifacts"):
        shutil.copytree(cache / name, root / "build" / name, symlinks=True)
    (root / "build/workspace-state.json").write_text(json.dumps(state).replace(str(cache), str(root / "build")))
    shutil.copyfile(cache.parent / "Package.resolved", root / "Package.resolved")
else:
    code = run("resolve", ["/usr/bin/swift", "package", *flags, "resolve"], timeout=600)
    if code:
        sys.exit(code)
assert {p["identity"]: p["state"]["revision"] for p in json.loads((root / "Package.resolved").read_text())["pins"]} == pins
flags += ["--disable-automatic-resolution"]
hashes = {str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
          for folder in ("Sources", "Tests") for path in sorted((root / folder).rglob("*")) if path.is_file()}
(root / "fixture.json").write_text(json.dumps({"revision": revision, "working_tree": args.working_tree,
    "pins": pins, "unneeded_targets": [p["identity"] for p in canonical["pins"] if p["identity"] not in pins],
    "source_sha256": hashes, "mode": args.mode,
    "boundary": "Actual Library adapter, fields-only shell, synthetic memory/SQLite stores; no app services",
    "omitted": "Full canonical suites, preferences round trip, native UI, unrelated MCP SDK targets"}, indent=2) + "\n")
code = run("build", ["/usr/bin/swift", "test", *flags, "list"], timeout=900)
if code:
    sys.exit(code)
discovery = (root / "logs/build.stdout").read_text()
assert "LibraryFallbackRegressionTests" in discovery, "Expected regression tests were not discovered"
base_test = ["/usr/bin/swift", "test", *flags, "--skip-build", "--no-parallel"]
if args.mode == "regressions":
    sys.exit(run("tests", [*base_test, "--filter", "LibraryFallbackRegressionTests"], timeout=180))
code = run("tests-existing", [*base_test, "--skip", "policyRoundTrip", "--filter", "Safe(Model|Store)Tests"], timeout=180)
if code:
    sys.exit(code)
code = run("tests", [*base_test, "--skip", "snapshotCostObservation", "--filter", "LibraryAdapterTests"], timeout=180)
if code:
    sys.exit(code)
# A fresh process and a single selected method keep other owned tests/builds
# out of the observation window. These samples have no performance threshold.
sys.exit(run("snapshot-observation", [*base_test, "--filter", "snapshotCostObservation"], timeout=90))
