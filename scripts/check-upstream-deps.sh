#!/usr/bin/env bash
# Upstream dependency canary: reports when GRDB, SQLCipher, Sparkle, Sauce, or
# KeyboardShortcuts publishes a release newer than the pins in
# scripts/upstream-pins.env — WITHOUT touching any source. Exit 1 means "an
# upstream advanced; open the runbook (docs/DEPENDENCIES.md)".
#
# Live mode (CI cron) queries the GitHub releases API. Test mode injects the
# "latest" versions from a fixture file instead, so the detection logic is
# verifiable offline:
#   check-upstream-deps.sh --latest fixture.env
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

pins_file="scripts/upstream-pins.env"
latest_file=""
while [ $# -gt 0 ]; do
	case "$1" in
	--pins)
		pins_file="$2"
		shift 2
		;;
	--latest)
		latest_file="$2"
		shift 2
		;;
	*)
		echo "usage: $0 [--pins pins.env] [--latest fixture.env]" >&2
		exit 2
		;;
	esac
done

# shellcheck disable=SC1090
source "$pins_file"

# The pins file must agree with what the repo actually builds — a pin that
# silently drifts would blind the canary.
sparkle_in_script="$(sed -n 's/^SPARKLE_VERSION="\${SPARKLE_VERSION:-\(.*\)}"$/\1/p' scripts/fetch-sparkle.sh)"
if [ "$sparkle_in_script" != "$SPARKLE" ]; then
	echo "✗ pin drift: SPARKLE pin ($SPARKLE) != fetch-sparkle.sh ($sparkle_in_script)" >&2
	exit 1
fi
# Sauce and SQLCipher.swift resolve inside the tracked package manifest;
# KeyboardShortcuts is a project-level dependency whose resolved file is
# generated (not tracked), so its pin is maintained by hand in
# upstream-pins.env alongside the update PR.
for pair in "sauce:$SAUCE" "sqlcipher.swift:$SQLCIPHER"; do
	identity="${pair%%:*}"
	pin="${pair#*:}"
	if ! grep -A5 "\"identity\" : \"$identity\"" Packages/GanchoKit/Package.resolved \
		| grep -q "\"version\" : \"$pin\""; then
		echo "✗ pin drift: $identity pin ($pin) != Packages/GanchoKit/Package.resolved" >&2
		exit 1
	fi
done

# Latest published version per upstream: fixture in test mode, GitHub
# releases/tags in live mode. Tags are normalized by stripping a leading "v".
latest_for() {
	local name="$1" repo="$2"
	if [ -n "$latest_file" ]; then
		sed -n "s/^${name}=//p" "$latest_file"
		return
	fi
	curl -fsSL --max-time 30 \
		-H "Accept: application/vnd.github+json" \
		${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} \
		"https://api.github.com/repos/${repo}/releases/latest" \
		| sed -n 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/p' | head -1
}

status=0
report() {
	local name="$1" pinned="$2" latest="$3"
	if [ -z "$latest" ]; then
		echo "? $name: could not resolve the latest upstream release (pinned $pinned)"
		return
	fi
	if [ "$latest" != "$pinned" ]; then
		echo "✗ UPSTREAM ADVANCED: $name pinned $pinned, latest $latest — see docs/DEPENDENCIES.md"
		status=1
	else
		echo "✓ $name up to date ($pinned)"
	fi
}

report "GRDB" "$GRDB" "$(latest_for GRDB groue/GRDB.swift)"
report "SQLCIPHER" "$SQLCIPHER" "$(latest_for SQLCIPHER sqlcipher/SQLCipher.swift)"
report "SPARKLE" "$SPARKLE" "$(latest_for SPARKLE sparkle-project/Sparkle)"
report "SAUCE" "$SAUCE" "$(latest_for SAUCE Clipy/Sauce)"
report "KEYBOARDSHORTCUTS" "$KEYBOARDSHORTCUTS" "$(latest_for KEYBOARDSHORTCUTS sindresorhus/KeyboardShortcuts)"

exit "$status"
