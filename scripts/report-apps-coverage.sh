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

# Reads an xccov JSON report on stdin and prints a per-target table plus the
# app aggregate. Exits non-zero only when the REPORT is unusable — never on a
# coverage number, so a thin week never fails the workflow.
summarize() {
	# The report arrives in an env var, not on stdin: the heredoc below already
	# occupies stdin delivering this program to the interpreter.
	local app_targets="$1"
	COVERAGE_APP_TARGETS="$app_targets" python3 <<'PY'
import json
import os
import sys

app_targets = set(os.environ["COVERAGE_APP_TARGETS"].split())
try:
    report = json.loads(os.environ["COVERAGE_REPORT_JSON"])
except json.JSONDecodeError as error:
    raise SystemExit(f"coverage report is not valid JSON: {error}")

targets = report.get("targets")
if not isinstance(targets, list) or not targets:
    sys.exit("coverage report lists no targets — was -enableCodeCoverage set?")

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
}

self_test() {
	local fixture actual
	# Two app targets, one package, one dependency, and one app-shaped target
	# that is deliberately NOT on the list — the case that must be surfaced.
	fixture='{"targets":[
		{"name":"Gancho.app","executableLines":1000,"coveredLines":250},
		{"name":"GanchoMenuBarHelper","executableLines":100,"coveredLines":50},
		{"name":"GanchoAppCore","executableLines":900,"coveredLines":800},
		{"name":"KeyboardShortcuts","executableLines":500,"coveredLines":10},
		{"name":"Sneaky.appex","executableLines":40,"coveredLines":4}]}'
	actual="$(COVERAGE_REPORT_JSON="$fixture" summarize "$APP_TARGETS")"

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
	COVERAGE_REPORT_JSON='{"targets":[]}' summarize "$APP_TARGETS" >/dev/null 2>&1 \
		&& { echo "self-test: an empty report must not pass"; exit 1; }
	COVERAGE_REPORT_JSON='not json' summarize "$APP_TARGETS" >/dev/null 2>&1 \
		&& { echo "self-test: malformed JSON must not pass"; exit 1; }

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
	COVERAGE_REPORT_JSON="$(xcrun xccov view --report --json "$bundle")" \
		summarize "$APP_TARGETS"
	echo
done
