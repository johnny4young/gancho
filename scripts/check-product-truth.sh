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

require_literal_count() {
	local file="$1"
	local literal="$2"
	local expected="$3"
	local actual
	actual="$(grep -Fc -- "$literal" "$file" || true)"
	[[ "$actual" == "$expected" ]] \
		|| fail "$file must contain '$literal' on exactly $expected lines (found $actual)"
}

forbid_regex() {
	local file="$1"
	local pattern="$2"
	if grep -Eiq -- "$pattern" "$file"; then
		fail "$file contains a forbidden or stale claim matching: $pattern"
	fi
}

require_literal project.yml 'macOS: "15.4"'
require_literal project.yml 'iOS: "26.0"'
# Publication is independent of MARKETING_VERSION. The README names the verified
# public tag; its retained release notes define that download's supported floor.
published_version="$(sed -nE 's/^\*\*Status: public v([0-9]+\.[0-9]+\.[0-9]+);.*/\1/p' README.md)"
[[ -n "$published_version" ]] || fail "README must name the verified published version"
published_notes="docs/releases/v${published_version}.md"
[[ -f "$published_notes" ]] || fail "published release notes are missing"
published_floor="$(sed -nE 's/^Gancho requires macOS ([0-9.]+) or later.*/\1/p' "$published_notes")"
[[ -n "$published_floor" ]] || fail "published release notes must state their macOS floor"
require_literal_count site/index.html "macOS ${published_floor}+ · iOS 26+" 2
require_literal docs/PRODUCT-TRUTH.md "GitHub release \`v${published_version}\`"
published_sha="$(sed -nE 's/^SHA-256: `([a-f0-9]{64})`.*/\1/p' "$published_notes")"
[[ -n "$published_sha" ]] || fail "published release notes must state the DMG checksum"
require_literal packaging/Casks/gancho.rb "version \"${published_version}\""
require_literal packaging/Casks/gancho.rb "sha256 \"${published_sha}\""
require_literal packaging/Casks/gancho.rb 'depends_on macos: :sequoia'
require_literal packaging/Casks/gancho.rb "Gancho requires macOS ${published_floor} or later."

require_literal README.md 'eight library products + a CLI'
require_literal README.md 'disabled until explicit consent'
require_literal README.md 'short-prefix indexes'
require_literal docs/SECURITY-MODEL.md 'Telemetry is disabled until the user consents'
require_literal docs/PRODUCT-TRUTH.md '# Product truth contract'
require_literal docs/INTEGRATIONS.md '**Homebrew cask — published.**'
require_literal docs/INTEGRATIONS.md 'brew install --cask gancho'
require_literal docs/INTEGRATIONS.md '**VS Code Marketplace — not published.**'
require_literal docs/INTEGRATIONS.md '[gancho.app](https://gancho.app)'
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
release_series="${published_version%.*}"
require_literal README.md "**Source version: v${marketing_version}"
require_literal docs/PRODUCT-TRUTH.md "v${marketing_version}"
require_literal site/index.html "v${marketing_version}"
if [[ "$published_version" != "$marketing_version" ]]; then
	require_literal README.md "(unreleased)"
	require_literal "docs/releases/v${marketing_version}.md" '## Release verification'
	require_literal site/index.html "data-i18n=\"rel.kicker\">En preparación · v${marketing_version}"
	require_literal site/index.html "\"rel.kicker\": \"In preparation · v${marketing_version}\""
	forbid_regex README.md "published v${marketing_version//./\\.} DMG"
else
	forbid_regex README.md '\(unreleased\)'
	require_literal site/index.html "data-i18n=\"rel.kicker\">Disponible · v${published_version}"
	require_literal site/index.html "\"rel.kicker\": \"Available now · v${published_version}\""
fi
require_literal site/index.html "data-i18n=\"hero.badge\">Privado por diseño · versión pública ${release_series}"
require_literal site/index.html "\"hero.badge\": \"Private by design · public v${release_series}\""
require_literal site/index.html "Código abierto bajo licencia MIT · versión pública ${release_series}."
require_literal site/index.html "Open source under the MIT license · public v${release_series}."
require_literal site/index.html "data-i18n=\"pro.free\">El DMG v${published_version} "
require_literal site/index.html "\"pro.free\": \"The v${published_version} DMG "

forbid_regex README.md 'seven library products'
forbid_regex README.md 'Status:.*pre-release'
forbid_regex docs/INTEGRATIONS.md 'publisher.*placeholder|confirming/registering that domain'
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
