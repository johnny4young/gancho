#!/usr/bin/env bash
# Fetch and checksum-verify Sparkle.framework for the direct-download build's
# auto-updater. Pinned and never committed (Vendor/ is git-ignored). Sparkle is
# fetched as a release framework rather than via SPM, because the SPM binary
# artifact has been known to hang on CI.
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

SPARKLE_VERSION="${SPARKLE_VERSION:-2.10.0}"
SPARKLE_SHA256="${SPARKLE_SHA256:-c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c}"
VENDOR_DIR="${VENDOR_DIR:-Vendor}"
FRAMEWORK="$VENDOR_DIR/Sparkle.framework"
TOOLS="$VENDOR_DIR/bin"
RECEIPT="$VENDOR_DIR/.sparkle-receipt"
expected_receipt="$SPARKLE_VERSION $SPARKLE_SHA256"

# A cache from another pin (or before receipts existed) must not bypass the
# checksum-verified download. The receipt records provenance, not a signature
# check of mutable local files; release packaging still verifies code signing.
if [ -d "$FRAMEWORK" ] && [ -x "$TOOLS/sign_update" ] \
	&& [ -x "$TOOLS/generate_appcast" ] && [ -x "$TOOLS/generate_keys" ] \
	&& [ -f "$RECEIPT" ] && [ "$(cat "$RECEIPT")" = "$expected_receipt" ] \
	&& [ -z "${FORCE:-}" ]; then
	printf '✓ Sparkle.framework + bin/ already present in %s/ (set FORCE=1 to refetch)\n' "$VENDOR_DIR"
	exit 0
fi

url="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/sparkle.XXXXXX")"
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
tar -xf "$tmp/sparkle.tar.xz" -C "$tmp"
# Reject incomplete archives before touching the working installation.
[ -d "$tmp/Sparkle.framework" ] || { echo "error: missing Sparkle.framework" >&2; exit 1; }
for tool in sign_update generate_appcast generate_keys; do
	[ -x "$tmp/bin/$tool" ] || { echo "error: missing Sparkle tool: $tool" >&2; exit 1; }
done
mkdir -p "$VENDOR_DIR"
rm -f "$RECEIPT"
rm -rf "$FRAMEWORK"
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

# Publish only after both the framework and tools were installed successfully.
printf '%s\n' "$expected_receipt" >"$RECEIPT"
