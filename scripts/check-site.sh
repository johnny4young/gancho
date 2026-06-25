#!/usr/bin/env bash
# Lightweight structural check for the static GitHub Pages site.
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

fail() {
	printf '✗ %s\n' "$1" >&2
	exit 1
}

[ -f site/index.html ] || fail "site/index.html is missing"
[ -f site/styles.css ] || fail "site/styles.css is missing"
[ -f site/assets/gancho-mark.svg ] || fail "site/assets/gancho-mark.svg is missing"

grep -q '<html lang="en">' site/index.html || fail "site/index.html must declare lang=\"en\""
grep -q '<title>Gancho' site/index.html || fail "site/index.html must set a Gancho title"
grep -q 'Privacy-first' site/index.html || fail "site/index.html must carry the privacy-first product position"
grep -q 'CHANGELOG.md' site/index.html || fail "site/index.html must link release notes/changelog"
! grep -RIn --exclude='*.svg' 'http://' site >/dev/null || fail "site/ must not use insecure http:// URLs outside SVG namespaces"
! grep -RIn 'TODO' site >/dev/null || fail "site/ contains TODO markers"

printf '✓ site/ structural checks passed\n'
