#!/usr/bin/env bash
# Fetch and checksum-verify Sparkle.framework for the direct-download build's
# auto-updater. Pinned and never committed (Vendor/ is git-ignored). Sparkle is
# fetched as a release framework rather than via SPM, because the SPM binary
# artifact has been known to hang on CI.
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

SPARKLE_VERSION="${SPARKLE_VERSION:-2.9.4}"
SPARKLE_SHA256="${SPARKLE_SHA256:-ce89daf967db1e1893ed3ebd67575ed82d3902563e3191ca92aaec9164fbdef9}"
VENDOR_DIR="${VENDOR_DIR:-Vendor}"
FRAMEWORK="$VENDOR_DIR/Sparkle.framework"
TOOLS="$VENDOR_DIR/bin"

if [ -d "$FRAMEWORK" ] && [ -x "$TOOLS/sign_update" ] && [ -z "${FORCE:-}" ]; then
	printf '✓ Sparkle.framework + bin/ already present in %s/ (set FORCE=1 to refetch)\n' "$VENDOR_DIR"
	exit 0
fi

url="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
tmp="$(mktemp -d -t sparkle)"
trap 'rm -rf "$tmp"' EXIT

printf '==> Downloading Sparkle %s\n' "$SPARKLE_VERSION"
curl -fsSL "$url" -o "$tmp/sparkle.tar.xz"

printf '==> Verifying checksum\n'
actual="$(shasum -a 256 "$tmp/sparkle.tar.xz" | awk '{print $1}')"
if [ "$actual" != "$SPARKLE_SHA256" ]; then
	echo "error: Sparkle checksum mismatch" >&2
	echo "  expected $SPARKLE_SHA256" >&2
	echo "  actual   $actual" >&2
	exit 1
fi

printf '==> Extracting Sparkle.framework into %s/\n' "$VENDOR_DIR"
mkdir -p "$VENDOR_DIR"
rm -rf "$FRAMEWORK"
tar -xf "$tmp/sparkle.tar.xz" -C "$tmp"
cp -R "$tmp/Sparkle.framework" "$FRAMEWORK"
printf '✓ %s (Sparkle %s)\n' "$FRAMEWORK" "$SPARKLE_VERSION"

# The release tarball also ships the appcast tooling (sign_update,
# generate_appcast). Keep them next to the framework so `make appcast` can sign
# DMGs with the maintainer's Keychain EdDSA key at release time.
if [ -d "$tmp/bin" ]; then
	printf '==> Extracting Sparkle bin/ tools into %s/\n' "$TOOLS"
	rm -rf "$TOOLS"
	cp -R "$tmp/bin" "$TOOLS"
	printf '✓ %s (sign_update, generate_appcast, generate_keys)\n' "$TOOLS"
fi
