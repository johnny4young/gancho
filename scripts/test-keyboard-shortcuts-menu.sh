#!/usr/bin/env bash
# Run a selected native dependency acceptance gate in a UUID fixture app.
set -euo pipefail

shortcut_repo="$(cd "$(dirname "$0")/.." && pwd -P)"
: "${KEYBOARDSHORTCUTS_CHECKOUT:?Set to a local Git repository containing the canonical locked revision}"
: "${SHORTCUT_MENU_SIGN_IDENTITY:?Set to an existing trusted code signing identity}"
command -v xcodegen >/dev/null
command -v python3 >/dev/null

case "${SHORTCUT_ACCEPTANCE_SCOPE:-menu}" in
menu)
	shortcut_scheme=ShortcutMenuFixture
	shortcut_testing=ShortcutMenuUITests/ShortcutMenuUITests/testConsumedMenuShortcutIsDeliveredOnceWithoutRequeue
	shortcut_result=native-menu
	shortcut_expected_tests=1
	;;
recorder)
	shortcut_scheme=ShortcutRecorderFixture
	shortcut_testing=ShortcutRecorderUITests
	shortcut_result=native-recorder
	shortcut_expected_tests=8
	;;
*)
	printf 'SHORTCUT_ACCEPTANCE_SCOPE must be menu or recorder\n' >&2
	exit 2
	;;
esac

if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p)" == /Library/Developer/CommandLineTools &&
	-d /Applications/Xcode.app ]]; then
	export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

# Preserve the tiny manifest/traces and the result bundle for review. No shared
# project, installed app or personal preferences are modified.
shortcut_output="$(mktemp -d "${TMPDIR:-/tmp}/gancho-shortcut-menu.XXXXXX")"
printf 'Native shortcut fixture evidence: %s\n' "$shortcut_output"
python3 "$shortcut_repo/Tests/KeyboardShortcutsAcceptance/prepare.py" \
	"$shortcut_repo" "$shortcut_output" "$KEYBOARDSHORTCUTS_CHECKOUT"
xcodegen generate --spec "$shortcut_output/project.json" --project "$shortcut_output"

read_manifest() {
	python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' \
		"$shortcut_output/manifest.json" "$1"
}

TEST_RUNNER_SHORTCUT_MENU_VERSION="$(read_manifest version)"
TEST_RUNNER_SHORTCUT_MENU_REVISION="$(read_manifest revision)"
TEST_RUNNER_SHORTCUT_MENU_BUNDLE_ID="$(read_manifest bundleIdentifier)"
TEST_RUNNER_SHORTCUT_MENU_SNAPSHOT="$(read_manifest snapshotPath)"
TEST_RUNNER_SHORTCUT_RECORDER_BUNDLE_ID="$(read_manifest recorderBundleIdentifier)"
TEST_RUNNER_SHORTCUT_RECORDER_SNAPSHOT="$(read_manifest recorderSnapshotPath)"
export TEST_RUNNER_SHORTCUT_MENU_VERSION TEST_RUNNER_SHORTCUT_MENU_REVISION
export TEST_RUNNER_SHORTCUT_MENU_BUNDLE_ID TEST_RUNNER_SHORTCUT_MENU_SNAPSHOT
export TEST_RUNNER_SHORTCUT_RECORDER_BUNDLE_ID TEST_RUNNER_SHORTCUT_RECORDER_SNAPSHOT

xcodebuild -project "$shortcut_output/ShortcutMenuFixture.xcodeproj" \
	-scheme "$shortcut_scheme" -configuration Debug -destination 'platform=macOS' \
	-derivedDataPath "$shortcut_output/DerivedData" -disableAutomaticPackageResolution \
	-parallel-testing-enabled NO -maximum-concurrent-test-device-destinations 1 \
	-only-testing:"$shortcut_testing" \
	-resultBundlePath "$shortcut_output/$shortcut_result.xcresult" test \
	2>&1 | tee "$shortcut_output/$shortcut_result.log"

# A successful runner command alone can hide an empty or skipped test selection.
xcrun xcresulttool get test-results summary \
	--path "$shortcut_output/$shortcut_result.xcresult" \
	>"$shortcut_output/$shortcut_result-summary.json"
python3 - "$shortcut_output/$shortcut_result-summary.json" "$shortcut_expected_tests" <<'PY'
import json
import sys

with open(sys.argv[1]) as handle:
    summary = json.load(handle)
expected = int(sys.argv[2])
if not (
    summary.get("result") == "Passed"
    and summary.get("totalTestCount") == expected
    and summary.get("passedTests") == expected
    and summary.get("failedTests") == 0
    and summary.get("skippedTests") == 0
    and summary.get("expectedFailures") == 0
):
    sys.exit(f"Native acceptance requires {expected} passing tests without skips or expected failures")
print(f"PASS: {expected} native acceptance tests, zero skips")
PY
