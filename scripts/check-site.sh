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
