#!/usr/bin/env bash
# Fail when public product claims drift from source-controlled contracts.
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

fail() {
	printf '✗ %s\n' "$1" >&2
	exit 1
}

require_literal() {
	local file="$1"
	local literal="$2"
	grep -Fq -- "$literal" "$file" || fail "$file is missing required claim: $literal"
}

forbid_regex() {
	local file="$1"
	local pattern="$2"
	if grep -Eiq -- "$pattern" "$file"; then
		fail "$file contains a forbidden or stale claim matching: $pattern"
	fi
}

require_literal project.yml 'macOS: "26.0"'
require_literal project.yml 'iOS: "26.0"'
require_literal site/index.html 'macOS 26+ · iOS 26+'
require_literal README.md 'eight library products + a CLI'
require_literal README.md 'disabled until explicit consent'
require_literal README.md 'short-prefix indexes'
require_literal docs/SECURITY-MODEL.md 'Telemetry is disabled until the user consents'
require_literal docs/PRODUCT-TRUTH.md '# Product truth contract'
require_literal site/index.html 'releases/latest'
require_literal site/index.html 'Boards with their own color and emoji'

library_count="$(grep -Ec '^[[:space:]]*\.library\(name:' Packages/GanchoKit/Package.swift)"
[[ "$library_count" == 8 ]] || fail "GanchoKit must expose exactly eight library products"
executable_count="$(grep -Ec '^[[:space:]]*\.executable\(name:' Packages/GanchoKit/Package.swift)"
[[ "$executable_count" == 1 ]] || fail "GanchoKit must expose exactly one executable product"

marketing_version="$({
	grep -E '^[[:space:]]*MARKETING_VERSION:' project.yml | head -1
} | sed -E 's/.*"?([0-9]+\.[0-9]+\.[0-9]+)"?.*/\1/')"
[[ -n "$marketing_version" ]] || fail "could not read MARKETING_VERSION"
release_series="${marketing_version%.*}"
require_literal README.md "v${marketing_version} DMG"
require_literal README.md "- [What's new in ${release_series}](#whats-new-in-${release_series//./})"
require_literal README.md "## What's new in ${release_series}"
require_literal docs/PRODUCT-TRUTH.md "v${marketing_version}"
require_literal site/index.html "v${marketing_version}"
require_literal site/index.html "data-i18n=\"rel.kicker\">Nuevo en ${release_series}"
require_literal site/index.html "\"rel.kicker\": \"New in ${release_series}\""
require_literal site/index.html "data-i18n=\"pro.free\">El DMG v${release_series} "
require_literal site/index.html "\"pro.free\": \"The v${release_series} DMG "

forbid_regex README.md 'seven library products'
forbid_regex site/index.html 'macOS 14\+|iOS 17\+'
forbid_regex site/index.html 'Content never leaves your devices|El contenido nunca sale de tus dispositivos'
forbid_regex site/index.html 'floating HUD|HUD flotante|each ⌘V|cada ⌘V'
forbid_regex site/index.html 'No servers · no telemetry|Sin servidores · sin telemetría'

# Internal planning labels are private and become stale quickly. Scan every
# tracked file; git grep skips binary payloads and the regex itself contains no
# concrete identifier.
private_id_pattern='(MKT|DB|UX|TRU|DOC|QLT|BUG|PERF|REL|ARC|SYNC|DEP|SEC|A11Y|IOS|MAC|DATA|AI|SYS|HAB|TEST)-[[:digit:]]{2}'
private_id_report="$(mktemp -t gancho-private-ids.XXXXXX)"
trap 'rm -f "$private_id_report"' EXIT
if git grep -nEI "$private_id_pattern" >"$private_id_report"; then
	cat "$private_id_report" >&2
	fail "tracked project prose contains private planning identifiers"
fi

printf '✓ product truth contract passed\n'
