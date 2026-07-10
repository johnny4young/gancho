#!/usr/bin/env bash
# Verify release metadata that must move together before a tag is cut.
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

fail() {
	printf '✗ %s\n' "$1" >&2
	exit 1
}

pass() { printf '✓ %s\n' "$1"; }

marketing_version="$(sed -nE 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"?([0-9][0-9A-Za-z.-]*)"?[[:space:]]*$/\1/p' project.yml | head -n1)"
build_version="$(sed -nE 's/^[[:space:]]*CURRENT_PROJECT_VERSION:[[:space:]]*"?([0-9]+)"?[[:space:]]*$/\1/p' project.yml | head -n1)"

[ -n "$marketing_version" ] || fail "MARKETING_VERSION is missing from project.yml"
[[ "$marketing_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "MARKETING_VERSION must be x.y.z, got '$marketing_version'"
[ -n "$build_version" ] || fail "CURRENT_PROJECT_VERSION is missing from project.yml"
[[ "$build_version" =~ ^[0-9]+$ ]] || fail "CURRENT_PROJECT_VERSION must be a positive integer, got '$build_version'"
[ "$build_version" -ge 1 ] || fail "CURRENT_PROJECT_VERSION must be >= 1"

[ -f CHANGELOG.md ] || fail "CHANGELOG.md is missing"
grep -q '^## \[Unreleased\]' CHANGELOG.md || fail "CHANGELOG.md is missing a [Unreleased] section"
changelog_version="$(grep -m1 -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' CHANGELOG.md | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)"
[ -n "$changelog_version" ] || fail "CHANGELOG.md has no released '## [x.y.z]' heading"
[ "$changelog_version" = "$marketing_version" ] || fail "CHANGELOG top version ($changelog_version) != MARKETING_VERSION ($marketing_version)"

formula="scripts/homebrew/gancho.rb"
[ -f "$formula" ] || fail "$formula is missing"
formula_version="$(sed -nE 's/^[[:space:]]*version "([0-9]+\.[0-9]+\.[0-9]+)"[[:space:]]*$/\1/p' "$formula" | head -n1)"
[ -n "$formula_version" ] || fail "$formula does not declare a concrete semantic version"
[ "$formula_version" = "$marketing_version" ] || fail "$formula version ($formula_version) != MARKETING_VERSION ($marketing_version)"
grep -q 'archive/refs/tags/v#{version}.tar.gz' "$formula" || fail "$formula must build from the versioned GitHub tag tarball"

# Read a plist string value. Prefers PlistBuddy (macOS); falls back to a
# portable parser (the <string> immediately following the matching <key>) so the
# gate also runs on Linux dev boxes and minimal CI images that lack PlistBuddy.
plist_string() {
	local key="$1" file="$2"
	if [ -x /usr/libexec/PlistBuddy ]; then
		/usr/libexec/PlistBuddy -c "Print :$key" "$file" 2>/dev/null || true
		return
	fi
	awk -v key="$key" '
		match($0, "<key>" key "</key>") { getline; found = 1 }
		found {
			if (match($0, /<string>.*<\/string>/)) {
				line = $0
				sub(/.*<string>/, "", line)
				sub(/<\/string>.*/, "", line)
				print line
			}
			exit
		}
	' "$file"
}

for plist in Apps/GanchoMac/Info.plist Apps/GanchoiOS/Info.plist Apps/GanchoShare/Info.plist Apps/GanchoKeyboard/Info.plist Apps/GanchoWidgets/Info.plist; do
	[ -f "$plist" ] || fail "$plist is missing"
	short_version="$(plist_string CFBundleShortVersionString "$plist")"
	bundle_version="$(plist_string CFBundleVersion "$plist")"
	expected_marketing='$(MARKETING_VERSION)'
	expected_build='$(CURRENT_PROJECT_VERSION)'
	[ "$short_version" = "$expected_marketing" ] || fail "$plist must use \$(MARKETING_VERSION), got '$short_version'"
	[ "$bundle_version" = "$expected_build" ] || fail "$plist must use \$(CURRENT_PROJECT_VERSION), got '$bundle_version'"
done

# Keep a Changelog structure: within one version section, each '### Type'
# heading appears at most once — a second '### Added' means an entry was
# appended instead of merged into the existing section.
duplicate_heading="$(awk '
	/^## \[/ { section = $0; delete seen }
	/^### / { if (seen[$0]++) { printf "%s under %s", $0, section; exit } }
' CHANGELOG.md)"
[ -z "$duplicate_heading" ] || fail "CHANGELOG.md duplicates a heading: $duplicate_heading"

pass "project.yml MARKETING_VERSION $marketing_version and build $build_version are valid"
pass "CHANGELOG.md top release matches $marketing_version"
pass "CHANGELOG.md has no duplicate section headings"
pass "Homebrew formula template matches $marketing_version"
pass "Info.plist bundle versions expand from project.yml build settings"
