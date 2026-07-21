#!/usr/bin/env bash
# Lightweight structural check for the static Cloudflare Pages site.
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
marketing_version="$(sed -nE 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"?([^"[:space:]]+)"?.*/\1/p' project.yml | head -1)"
[ -n "$marketing_version" ] || fail "project.yml must declare MARKETING_VERSION"
release_asset="assets/v${marketing_version}-release.png"
[ -f "site/${release_asset}" ] \
	|| fail "site/${release_asset} is missing; every release needs current product evidence"

# The site is bilingual (ES default + EN toggle); it declares a lang and the
# data-lang marker that drives the in-page switcher.
grep -qE '<html lang="(es|en)"' site/index.html || fail "site/index.html must declare a lang"
grep -q 'data-lang=' site/index.html || fail "site/index.html must carry the bilingual data-lang marker"
grep -qi '<title>gancho' site/index.html || fail "site/index.html must set a gancho title"
grep -qi 'private by design' site/index.html || fail "site/index.html must carry the privacy-first product position"
grep -q 'CHANGELOG.md' site/index.html || fail "site/index.html must link release notes/changelog"
grep -q 'property="og:image"' site/index.html || fail "site/index.html must set a social preview image"
grep -q 'name="twitter:card" content="summary_large_image"' site/index.html \
	|| fail "site/index.html must opt into a large social preview"
grep -Fq "src=\"${release_asset}\"" site/index.html \
	|| fail "site/index.html must render the current release screenshot"
grep -Fq "https://gancho.app/${release_asset}" site/index.html \
	|| fail "site/index.html must use the current release screenshot in social metadata"

# Keep release storytelling scannable: the current release leads, two recent
# milestones summarize product evolution, and the full archive is progressively
# disclosed in newest-first native details elements.
latest_line="$(grep -n 'id="latest-release"' site/index.html | head -1 | cut -d: -f1 || true)"
evolution_line="$(grep -n 'id="release-evolution"' site/index.html | head -1 | cut -d: -f1 || true)"
changelog_line="$(grep -n 'id="changelog"' site/index.html | head -1 | cut -d: -f1 || true)"
[ -n "$latest_line" ] && [ -n "$evolution_line" ] && [ -n "$changelog_line" ] \
	|| fail "site/index.html must include current, recent evolution, and changelog sections"
((latest_line < evolution_line && evolution_line < changelog_line)) \
	|| fail "release story must render current, then recent evolution, then changelog"
grep -q '<details class="release-detail" id="release-0-7-0">' site/index.html \
	|| fail "the release archive must use native progressive disclosure"
! grep -q 'class="log-row"' site/index.html \
	|| fail "the release archive must not render every version expanded"

previous_line=0
for release_id in \
	release-0-7-0 release-0-6-0 release-0-5-0 release-0-4-1 release-0-4-0 \
	release-0-3-2 release-0-3-1 release-0-3-0 release-0-2-0 release-0-1-0; do
	release_line="$(grep -n "id=\"${release_id}\"" site/index.html | head -1 | cut -d: -f1 || true)"
	[ -n "$release_line" ] || fail "site/index.html is missing ${release_id}"
	((release_line > previous_line)) || fail "release archive must remain newest first"
	previous_line="$release_line"
done

# Every local image or stylesheet reference in the page must resolve inside
# site/. This catches renamed screenshots before Pages deploys a broken card.
while IFS= read -r asset; do
	[ -f "site/${asset}" ] || fail "site/index.html references missing ${asset}"
done < <(
	grep -oE '(src|href)="(assets/[^"?]+|styles\.css)"' site/index.html \
		| sed -E 's/^[^=]+="([^"]+)"$/\1/' \
		| sort -u
)
# Spanish is the default text in the HTML; every key used by that markup must
# have an English dictionary entry for the language toggle.
while IFS= read -r key; do
	grep -Fq "\"${key}\":" site/index.html \
		|| fail "site/index.html is missing the English translation for ${key}"
done < <(grep -oE 'data-i18n="[^"]+"' site/index.html \
	| sed -E 's/data-i18n="([^"]+)"/\1/' \
	| sort -u)
# The Sparkle appcast (site/appcast.xml) declares the Sparkle XML namespace,
# whose URI is http://www.andymatuschak.org/xml-namespaces/sparkle — an XML
# namespace identifier, not an insecure resource fetch. Allow it; reject any
# other http:// URL outside SVG namespaces.
if grep -RIn --exclude='*.svg' 'http://' site \
	| grep -qv 'www.andymatuschak.org/xml-namespaces/sparkle'; then
	fail "site/ must not use insecure http:// URLs (only the Sparkle XML namespace is allowed)"
fi
! grep -RIn 'TODO' site >/dev/null || fail "site/ contains TODO markers"

./scripts/check-product-truth.sh

printf '✓ site/ structural checks passed\n'
