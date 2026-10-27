#!/usr/bin/env python3
"""Reproduce typed search failures without starting either app composition root."""
import argparse
import hashlib
import io
import json
import os
import pathlib
import plistlib
import shutil
import signal
import subprocess
import sys
import tarfile
import time

REPO = pathlib.Path(__file__).resolve().parents[1]
FIXTURES = REPO / "scripts/fixtures/search-outcomes"
MODULES = ("GanchoKit", "ClipboardCore", "GanchoAI", "GanchoAppCore", "GanchoDesign")
BASE_TESTS = ("PanelSearchModelTests.swift", "PanelRefreshStabilityTests.swift",
              "PanelPasteFreshnessRegressionTests.swift", "HistoryListViewModelTests.swift",
              "PanelSearchAlternativesTests.swift", "PanelSearchTokenTests.swift")
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--output", type=pathlib.Path, required=True)
parser.add_argument("--revision", help="Extract this exact local commit, e.g. the documented baseline")
parser.add_argument("--working-tree", action="store_true", help="Explicitly test current uncommitted source bytes")
parser.add_argument("--offline-cache", type=pathlib.Path, help="Copy an existing exact-pin SwiftPM scratch directory")
parser.add_argument("--snapshots", action="store_true", help="Render only the passive EN/ES notice in an owned process")
args = parser.parse_args()
if args.revision and args.working_tree:
    parser.error("Choose a revision or the working tree")
root = args.output.resolve()
if root == REPO or root.is_relative_to(REPO):
    parser.error("Evidence must be outside the checkout")
root.mkdir(mode=0o700, exist_ok=False)

def git(*argv):
    return subprocess.check_output(["/usr/bin/git", *argv], cwd=REPO)

revision = git("rev-parse", "--verify", (args.revision or "HEAD") + "^{commit}").decode().strip()

def source(path):
    if args.working_tree:
        return (REPO / path).read_bytes()
    return git("show", revision + ":" + path)

if args.working_tree:
    for name in MODULES:
        shutil.copytree(REPO / "Packages/GanchoKit/Sources" / name, root / "Sources" / name)
else:
    data = git("archive", "--format=tar", revision,
               *["Packages/GanchoKit/Sources/" + name for name in MODULES])
    prefix = "Packages/GanchoKit/Sources/"
    with tarfile.open(fileobj=io.BytesIO(data)) as archive:
        for member in archive:
            if not member.name.startswith(prefix):
                if member.isdir() and prefix.startswith(member.name.rstrip("/") + "/"):
                    continue
                raise ValueError("Unexpected archive prefix")
            relative = pathlib.Path(member.name[len(prefix):])
            if relative.is_absolute() or ".." in relative.parts:
                raise ValueError("Unsafe archive path")
            target = root / "Sources" / relative
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
            elif member.isfile():
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(archive.extractfile(member).read())
            else:
                raise ValueError("No links or special files allowed")

after = (root / "Sources/GanchoAppCore/ClipListSearchOutcome.swift").exists()
if args.snapshots and not after:
    parser.error("The baseline has no failure notice to render")
models = root / "Tests/SelectedModelTests"
models.mkdir(parents=True)
for name in BASE_TESTS + (("ClipListSearchOutcomeTests.swift", "ClipListSearchReaderTests.swift") if after else ()):
    (models / name).write_bytes(source("Packages/GanchoKit/Tests/GanchoAppCoreTests/" + name))
integration = root / "Tests/AdapterIntegrationTests"
integration.mkdir()
for name in ("AppModelShim.swift", "SearchFailureRegressionTests.swift"):
    shutil.copyfile(FIXTURES / name, integration / name)
(integration / "AppModel+PanelSearchSource.swift").write_bytes(source("Apps/GanchoMac/AppModel+PanelSearchSource.swift"))
if after:
    shutil.copyfile(FIXTURES / "AppAdapterOutcomeTests.swift", integration / "AppAdapterOutcomeTests.swift")
    shutil.copyfile(FIXTURES / "HistorySourceIntegrationTests.swift", integration / "HistorySourceIntegrationTests.swift")
    (integration / "HistoryStoreSource.swift").write_bytes(source("Apps/GanchoiOS/HistoryStoreSource.swift"))

lock = json.loads(source("Packages/GanchoKit/Package.resolved"))
urls = {"grdb.swift": "https://github.com/johnny4young/GRDB.swift.git",
        "sqlcipher.swift": "https://github.com/sqlcipher/SQLCipher.swift.git",
        "sauce": "https://github.com/Clipy/Sauce.git"}
pins = {pin["identity"]: pin["state"]["revision"] for pin in lock["pins"] if pin["identity"] in urls}
assert set(pins) == set(urls)
dependencies = ",\n".join(f'        .package(url: "{url}", revision: "{pins[name]}")' for name, url in urls.items())
snapshot_target = ""
if args.snapshots:
    folder = root / "Sources/SearchFailureSnapshots"
    folder.mkdir()
    shutil.copyfile(FIXTURES / "SearchFailureSnapshots.swift", folder / "SearchFailureSnapshots.swift")
    snapshot_target = ',\n        .executableTarget(name: "SearchFailureSnapshots", dependencies: ["GanchoDesign", "GanchoKit"])'
(root / "Package.swift").write_text('''// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "SearchOutcomeRegression", platforms: [.macOS("26.0")], dependencies: [
''' + dependencies + '''
    ], targets: [
        .target(name: "GanchoKit", dependencies: [.product(name: "GRDB", package: "GRDB.swift")], swiftSettings: [.define("SQLITE_HAS_CODEC")]),
        .target(name: "ClipboardCore", dependencies: ["GanchoKit", .product(name: "Sauce", package: "Sauce")]),
        .target(name: "GanchoAI", dependencies: ["GanchoKit"]),
        .target(name: "GanchoAppCore", dependencies: ["GanchoKit", "GanchoAI", "ClipboardCore"]),
        .target(name: "GanchoDesign", dependencies: ["GanchoKit"]),
        .testTarget(name: "SelectedModelTests", dependencies: ["GanchoKit", "GanchoAppCore"]),
        .testTarget(name: "AdapterIntegrationTests", dependencies: ["GanchoKit", "GanchoAppCore", "ClipboardCore", .product(name: "GRDB", package: "GRDB.swift")])
''' + snapshot_target + '''
    ])
''')
for name in ("home", "tmp", "cache", "config", "security", "build", "logs"):
    (root / name).mkdir()
env = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": str(root / "home"),
       "CFFIXED_USER_HOME": str(root / "home"), "TMPDIR": str(root / "tmp"),
       "DEVELOPER_DIR": os.environ.get("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer"), "LC_ALL": "en_US.UTF-8",
       "CLANG_MODULE_CACHE_PATH": str(root / "cache/clang"), "SWIFTPM_MODULECACHE_OVERRIDE": str(root / "cache/swift"),
       "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_TERMINAL_PROMPT": "0",
       "GIT_CONFIG_COUNT": "2", "GIT_CONFIG_KEY_0": "credential.helper", "GIT_CONFIG_VALUE_0": "",
       "GIT_CONFIG_KEY_1": "core.hooksPath", "GIT_CONFIG_VALUE_1": "/dev/null"}
records = []

def run(label, argv, timeout=120):
    record = {"label": label, "argv": argv, "cwd": str(root), "environment_allowlist": env,
              "timeout_seconds": timeout}
    started = time.monotonic()
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
    record.update(exit_code=code, duration_seconds=time.monotonic() - started)
    records.append(record)
    (root / "commands.json").write_text(json.dumps(records, indent=2) + "\n")
    print(json.dumps({key: record[key] for key in ("label", "exit_code", "duration_seconds")}), flush=True)
    return code

flags = ["--package-path", str(root), "--scratch-path", str(root / "build"), "--cache-path", str(root / "cache"),
         "--config-path", str(root / "config"), "--security-path", str(root / "security"),
         "--manifest-cache", "local", "--disable-dependency-cache"]
if args.offline_cache:
    cache = args.offline_cache.resolve()
    state = json.loads((cache / "workspace-state.json").read_text())
    actual = {entry["packageRef"]["identity"]: entry["state"]["checkoutState"]["revision"] for entry in state["object"]["dependencies"]}
    assert actual == pins, "Offline source pins differ"
    for name in ("checkouts", "repositories", "artifacts"):
        shutil.copytree(cache / name, root / "build" / name, symlinks=True)
    (root / "build/workspace-state.json").write_text(json.dumps(state).replace(str(cache), str(root / "build")))
    cached_lock = cache.parent / "Package.resolved"
    cached_pins = {p["identity"]: p["state"]["revision"] for p in json.loads(cached_lock.read_text())["pins"]}
    assert cached_pins == pins, "Offline fixture lock differs"
    shutil.copyfile(cached_lock, root / "Package.resolved")
else:
    code = run("resolve", ["/usr/bin/swift", "package", *flags, "resolve"], timeout=600)
    if code:
        sys.exit(code)
actual = {pin["identity"]: pin["state"]["revision"] for pin in json.loads((root / "Package.resolved").read_text())["pins"]}
assert actual == pins, "Resolved source pins differ"
source_hashes = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
                 for base in (root / "Sources", root / "Tests") for p in sorted(base.rglob("*")) if p.is_file()}
(root / "fixture.json").write_text(json.dumps({"revision": revision, "working_tree": args.working_tree,
    "pins": pins, "after": after, "source_sha256": source_hashes,
    "boundary": "Actual adapter source with minimal shell shim, temporary stores, no app roots/UI services"}, indent=2) + "\n")
code = run("build", ["/usr/bin/swift", "test", *flags, "--disable-automatic-resolution", "--jobs", "1", "list"], timeout=600)
if code:
    sys.exit(code)
code = run("tests", ["/usr/bin/swift", "test", *flags, "--disable-automatic-resolution", "--skip-build", "--no-parallel"], timeout=90)
if code or not args.snapshots:
    sys.exit(code)
code = run("snapshot-build", ["/usr/bin/swift", "build", *flags, "--disable-automatic-resolution", "--jobs", "1", "--product", "SearchFailureSnapshots"], timeout=120)
if code:
    sys.exit(code)
bin_record = run("bin-path", ["/usr/bin/swift", "build", *flags, "--show-bin-path"], timeout=30)
if bin_record:
    sys.exit(bin_record)
binary_dir = pathlib.Path((root / "logs/bin-path.stdout").read_text().strip())
app = root / "SnapshotFixture.app/Contents"
(app / "MacOS").mkdir(parents=True)
shutil.copyfile(binary_dir / "SearchFailureSnapshots", app / "MacOS/SearchFailureSnapshots")
os.chmod(app / "MacOS/SearchFailureSnapshots", 0o700)
# SwiftPM places this already-verified binary dependency next to executables.
# Preserve that loader-relative layout in the owned rendering bundle too.
framework = binary_dir / "SQLCipher.framework"
assert framework.resolve().is_relative_to(root), "Framework must belong to this output"
shutil.copytree(framework, app / "MacOS/SQLCipher.framework", symlinks=True)
(app / "Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": "SearchFailureSnapshots",
    "CFBundleIdentifier": "invalid.example.gancho.search-failure-fixture", "CFBundlePackageType": "APPL",
    "CFBundleDevelopmentRegion": "en", "CFBundleLocalizations": ["en", "es"], "LSUIElement": True}))
catalog = json.loads(source("Apps/GanchoMac/Localizable.xcstrings"))["strings"]
for language in ("en", "es"):
    localized = {}
    for key, entry in catalog.items():
        unit = entry.get("localizations", {}).get(language, {}).get("stringUnit", {})
        if unit.get("value"):
            localized[key] = unit["value"]
    folder = app / "Resources" / (language + ".lproj")
    folder.mkdir(parents=True)
    (folder / "Localizable.strings").write_bytes(plistlib.dumps(localized))
sys.exit(run("snapshots", [str(app / "MacOS/SearchFailureSnapshots"), str(root / "screenshots")], timeout=60))
