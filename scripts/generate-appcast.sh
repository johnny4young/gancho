#!/usr/bin/env bash
# Generate the Sparkle appcast for the direct-download channel. Signs the DMG
# in dist/ with the maintainer's EdDSA key (read from the login Keychain — never
# a CI secret) and writes the feed to site/appcast.xml, which GitHub Pages
# serves at the app's SUFeedURL.
#
# The <enclosure> URL points at the GitHub release asset for the matching tag,
# so upload the SAME dist/*.dmg to that release: the signature is over the DMG
# bytes, and rebuilding or re-signing it would invalidate the appcast.
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

# Ensure generate_appcast (and the framework) are present.
./scripts/fetch-sparkle.sh >/dev/null

OUTPUT_DIR="${OUTPUT_DIR:-dist}"
SITE_DIR="${SITE_DIR:-site}"
VERSION="${VERSION:-$(sed -nE 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"?([0-9][0-9A-Za-z.-]*)"?[[:space:]]*$/\1/p' project.yml | head -n1)}"
DMG="$OUTPUT_DIR/Gancho-$VERSION.dmg"
TAG="${TAG:-v$VERSION}"
RELEASE_BASE="${RELEASE_BASE:-https://github.com/johnny4young/gancho/releases/download/$TAG/}"
PROJECT_LINK="${PROJECT_LINK:-https://johnny4young.github.io/gancho/}"

if [ ! -f "$DMG" ]; then
	echo "error: $DMG not found — run 'make package-dmg' first" >&2
	exit 1
fi

# generate_appcast signs every archive in the folder it scans, so stage only the
# DMG (dist/ also holds the App Store ZIP, which is not a Sparkle update).
work="$(mktemp -d -t gancho-appcast)"
trap 'rm -rf "$work"' EXIT
cp "$DMG" "$work/"

mkdir -p "$SITE_DIR"
printf '==> Generating EdDSA-signed appcast for %s\n' "$(basename "$DMG")"
Vendor/bin/generate_appcast \
	--download-url-prefix "$RELEASE_BASE" \
	--link "$PROJECT_LINK" \
	-o "$SITE_DIR/appcast.xml" \
	"$work"

printf '✓ %s/appcast.xml\n' "$SITE_DIR"
printf '  enclosure base: %s\n' "$RELEASE_BASE"
printf '  Upload %s to release %s, then commit %s/appcast.xml.\n' \
	"$DMG" "$TAG" "$SITE_DIR"
