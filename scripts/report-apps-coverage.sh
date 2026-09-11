#!/usr/bin/env bash
# Reports coverage for the APP targets — the half of production code the
# package coverage gate cannot see.
#
# `swift test --enable-code-coverage` measures `Packages/GanchoKit/Sources/`
# and nothing else, because that is all SwiftPM builds. `Apps/**` is 19,021
# lines, 46% of production code, and reaches a runtime only under XCUITest. So
# the number lives here, in the weekly UI workflow, and is REPORTED rather than
# gated: a UI suite is too environment-sensitive to fail a build on, and a
# coverage floor nobody can act on quickly becomes a floor somebody lowers.
#
# Usage:
#   scripts/report-apps-coverage.sh <result-bundle> [more bundles...]
#   scripts/report-apps-coverage.sh --self-test
set -euo pipefail

# Targets built from `Apps/**`. Anything else in a result bundle is a package
# product, a third-party dependency, or a test bundle.
APP_TARGETS='Gancho.app GanchoiOS.app GanchoMenuBarHelper GanchoShare.appex GanchoKeyboard.appex GanchoWidgets.appex'

require_command() {
	command -v "$1" >/dev/null 2>&1 || { echo "missing required command: $1" >&2; exit 2; }
}

# Reads an xccov `--only-targets` JSON report on stdin and prints a per-target
# table plus the app aggregate. Exits non-zero only when the REPORT is unusable
# — never on a coverage number, so a thin week never fails the workflow.
summarize() {
	# The report takes stdin, so the program is read into a variable and handed
	# to the interpreter as an argument. The report itself must never travel as
	# an argument or in the environment: the two share ARG_MAX (1 MiB on
	# macOS), and a report past it fails the exec with "Argument list too long"
	# before Python starts.
	local program
	# `read -d ''` never finds its delimiter, so it returns 1 at end of input.
	IFS= read -r -d '' program <<'PY' || true
import json
import sys

app_targets = set(sys.argv[1].split())
try:
    targets = json.load(sys.stdin)
except json.JSONDecodeError as error:
    raise SystemExit(f"coverage report is not valid JSON: {error}")

# `--only-targets` prints a bare array. An object is the full report: the
# same targets, each carrying every file and function in it.
if not isinstance(targets, list):
    sys.exit("coverage report is not a target list — was --only-targets passed?")
if not targets:
    sys.exit("coverage report lists no targets")

app_rows, other = [], []
for target in targets:
    name = target.get("name", "?")
    lines = target.get("executableLines", 0)
    covered = target.get("coveredLines", 0)
    (app_rows if name in app_targets else other).append((name, covered, lines))

# A NEW app target must not vanish into "other" and quietly stop being
# reported. Anything that looks like an app bundle but is not on the list is
# surfaced, loudly, instead of being dropped.
unclassified = [
    name for name, _, _ in other if name.endswith((".app", ".appex"))
]

print("| target | covered | executable | coverage |")
print("| --- | ---: | ---: | ---: |")
for name, covered, lines in sorted(app_rows):
    percent = (covered / lines * 100) if lines else 0.0
    print(f"| `{name}` | {covered} | {lines} | {percent:.1f}% |")

total_lines = sum(lines for _, _, lines in app_rows)
total_covered = sum(covered for _, covered, _ in app_rows)
if not total_lines:
    sys.exit("no app targets found in the report — the target list needs updating")
print(f"| **all app targets** | **{total_covered}** | **{total_lines}** | "
      f"**{total_covered / total_lines * 100:.1f}%** |")

if unclassified:
    print()
    print("> **Unclassified app-shaped targets**, add them to `APP_TARGETS` in")
    print("> `scripts/report-apps-coverage.sh` or they stay unreported: "
          + ", ".join(f"`{name}`" for name in sorted(unclassified)))
PY
	python3 -c "$program" "$1"
}

# About 2 MB of JSON in the `--only-targets` shape, well past ARG_MAX: filler
# dependency targets with an app target at each end.
large_report_fixture() {
	local index products='/Users/runner/Library/Developer/Xcode/DerivedData/Gancho/Build/Products/Debug'
	printf '[{"name":"GanchoiOS.app","executableLines":10,"coveredLines":3},'
	for ((index = 0; index < 10000; index++)); do
		printf '{"name":"Dependency%d","buildProductPath":"%s/Dependency%d.framework/Dependency%d","executableLines":100,"coveredLines":10},' \
			"$index" "$products" "$index" "$index"
	done
	printf '{"name":"GanchoWidgets.appex","executableLines":10,"coveredLines":7}]'
}

self_test() {
	local fixture actual large_report
	# Two app targets, one package, one dependency, and one app-shaped target
	# that is deliberately NOT on the list — the case that must be surfaced.
	fixture='[
		{"name":"Gancho.app","executableLines":1000,"coveredLines":250},
		{"name":"GanchoMenuBarHelper","executableLines":100,"coveredLines":50},
		{"name":"GanchoAppCore","executableLines":900,"coveredLines":800},
		{"name":"KeyboardShortcuts","executableLines":500,"coveredLines":10},
		{"name":"Sneaky.appex","executableLines":40,"coveredLines":4}]'
	actual="$(summarize "$APP_TARGETS" <<<"$fixture")"

	# shellcheck disable=SC2016  # the backticks are literal markdown, not a
	# command substitution — single quotes are exactly what this pattern needs.
	grep -q '| `Gancho.app` | 250 | 1000 | 25.0% |' <<<"$actual" \
		|| { echo "self-test: app row wrong"; echo "$actual"; exit 1; }
	# 300/1100 — the package and the dependency must NOT dilute it.
	grep -q '\*\*27.3%\*\*' <<<"$actual" \
		|| { echo "self-test: aggregate must cover app targets only"; echo "$actual"; exit 1; }
	grep -q 'GanchoAppCore' <<<"$actual" \
		&& { echo "self-test: a package target leaked into the report"; exit 1; }
	grep -q 'Sneaky.appex' <<<"$actual" \
		|| { echo "self-test: an unlisted app-shaped target was dropped silently"; exit 1; }

	# An empty or malformed report must fail rather than print a clean zero.
	summarize "$APP_TARGETS" <<<'[]' >/dev/null 2>&1 \
		&& { echo "self-test: an empty report must not pass"; exit 1; }
	summarize "$APP_TARGETS" <<<'not json' >/dev/null 2>&1 \
		&& { echo "self-test: malformed JSON must not pass"; exit 1; }
	# So must the full report, which wraps the same targets in an object.
	summarize "$APP_TARGETS" <<<"{\"targets\":$fixture}" >/dev/null 2>&1 \
		&& { echo "self-test: a full report must not pass as a target list"; exit 1; }

	# A report no argument or environment variable could carry. The last app
	# target follows the filler, so its row proves the whole report was read,
	# not merely that the interpreter started.
	large_report="$(large_report_fixture)"
	((${#large_report} > $(getconf ARG_MAX))) \
		|| { echo "self-test: the large fixture must exceed ARG_MAX to prove anything"; exit 1; }
	actual="$(summarize "$APP_TARGETS" <<<"$large_report")" \
		|| { echo "self-test: a report larger than ARG_MAX must be summarized"; exit 1; }
	# shellcheck disable=SC2016  # literal markdown backticks, as above.
	grep -q '| `GanchoWidgets.appex` | 7 | 10 | 70.0% |' <<<"$actual" \
		|| { echo "self-test: the large report was not read to its end"; echo "$actual"; exit 1; }

	echo "✓ apps coverage report self-test passed"
}

require_command python3

if [ "${1:-}" = "--self-test" ]; then
	self_test
	exit 0
fi

[ $# -ge 1 ] || { echo "usage: $0 <result-bundle> [more bundles...]" >&2; exit 2; }
require_command xcrun

for bundle in "$@"; do
	[ -e "$bundle" ] || { echo "no such result bundle: $bundle" >&2; exit 2; }
	echo "### App-target coverage — $(basename "$bundle")"
	echo
	# Target totals are all the parser reads; the full report adds every file
	# and function under them. Captured before parsing, so a failing xccov
	# stops the script with its own error instead of arriving as empty JSON.
	report="$(xcrun xccov view --report --only-targets --json "$bundle")"
	summarize "$APP_TARGETS" <<<"$report"
	echo
done
