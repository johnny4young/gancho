#!/usr/bin/env bash
# Fetch and checksum-verify Sparkle.framework for the direct-download build's
# auto-updater. Pinned and never committed (Vendor/ is git-ignored). Sparkle is
# fetched as a release framework rather than via SPM, because the SPM binary
# artifact has been known to hang on CI.
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

SPARKLE_VERSION="${SPARKLE_VERSION:-2.9.3}"
SPARKLE_SHA256="${SPARKLE_SHA256:-74a07da821f92b79310009954c0e15f350173374a3abe39095b4fc5096916be6}"
VENDOR_DIR="${VENDOR_DIR:-Vendor}"
FRAMEWORK="$VENDOR_DIR/Sparkle.framework"

if [ -d "$FRAMEWORK" ] && [ -z "${FORCE:-}" ]; then
	printf '✓ Sparkle.framework already present in %s/ (set FORCE=1 to refetch)\n' "$VENDOR_DIR"
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
