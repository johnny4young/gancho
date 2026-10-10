#!/usr/bin/env bash
# Offline integration tests for fetch-sparkle.sh. Only curl is replaced; the
# production script hashes, extracts, installs, and reuses real fixture archives.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/gancho-sparkle-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/repo/scripts" "$tmp/mock" "$tmp/archive/Sparkle.framework" "$tmp/archive/bin"
git init -q "$tmp/repo"
cp "$root/scripts/fetch-sparkle.sh" "$tmp/repo/scripts/"
for tool in sign_update generate_appcast generate_keys; do
	printf '#!/bin/sh\nexit 0\n' >"$tmp/archive/bin/$tool"
	chmod +x "$tmp/archive/bin/$tool"
done
printf 'fixture framework\n' >"$tmp/archive/Sparkle.framework/Sparkle"
tar -cf "$tmp/good.tar" -C "$tmp/archive" Sparkle.framework bin
export FIXTURE_ARCHIVE="$tmp/good.tar" DOWNLOAD_LOG="$tmp/downloads"
: >"$DOWNLOAD_LOG"
cat >"$tmp/mock/curl" <<'CURL'
#!/usr/bin/env bash
set -euo pipefail
printf 'download\n' >>"$DOWNLOAD_LOG"
while [ "$#" -gt 0 ]; do
	if [ "$1" = -o ]; then cp "$FIXTURE_ARCHIVE" "$2"; exit 0; fi
	shift
done
exit 2
CURL
chmod +x "$tmp/mock/curl"
export PATH="$tmp/mock:$PATH"
export SPARKLE_VERSION="fixture-1"
export SPARKLE_SHA256="$(shasum -a 256 "$FIXTURE_ARCHIVE" | awk '{print $1}')"
export VENDOR_DIR="$tmp/repo/Vendor"
unset FORCE
cd "$tmp/repo"
fetch() { bash scripts/fetch-sparkle.sh >"$tmp/output" 2>&1; }
expect_downloads() {
	actual="$(wc -l <"$DOWNLOAD_LOG" | tr -d ' ')"
	[ "$actual" = "$1" ] || { cat "$tmp/output"; echo "expected $1 downloads, got $actual" >&2; exit 1; }
}
# An existing unmarked framework used to suppress every future version bump.
mkdir -p "$VENDOR_DIR/Sparkle.framework" "$VENDOR_DIR/bin"
printf 'old framework\n' >"$VENDOR_DIR/Sparkle.framework/Sparkle"
cp "$tmp/archive/bin/sign_update" "$VENDOR_DIR/bin/"
fetch
expect_downloads 1
cmp "$tmp/archive/Sparkle.framework/Sparkle" "$VENDOR_DIR/Sparkle.framework/Sparkle"
fetch
expect_downloads 1
# Either half of the pin changing invalidates the cache.
export SPARKLE_VERSION="fixture-2"
fetch
expect_downloads 2
printf 'replacement framework\n' >"$tmp/archive/Sparkle.framework/Sparkle"
tar -cf "$tmp/updated.tar" -C "$tmp/archive" Sparkle.framework bin
export FIXTURE_ARCHIVE="$tmp/updated.tar"
export SPARKLE_SHA256="$(shasum -a 256 "$FIXTURE_ARCHIVE" | awk '{print $1}')"
fetch
expect_downloads 3
cmp "$tmp/archive/Sparkle.framework/Sparkle" "$VENDOR_DIR/Sparkle.framework/Sparkle"
# Incomplete local tools are repaired; FORCE still deliberately refetches.
rm "$VENDOR_DIR/bin/generate_appcast"
fetch
expect_downloads 4
FORCE=1 fetch
expect_downloads 5
cp "$VENDOR_DIR/.sparkle-receipt" "$tmp/receipt"
# A bad checksum must preserve the usable installation and its receipt.
export SPARKLE_SHA256="invalid"
if fetch; then echo 'expected checksum rejection' >&2; exit 1; fi
expect_downloads 6
cmp "$tmp/receipt" "$VENDOR_DIR/.sparkle-receipt"
cmp "$tmp/archive/Sparkle.framework/Sparkle" "$VENDOR_DIR/Sparkle.framework/Sparkle"
# A checksum-valid but incomplete release must also preserve the installation.
tar -cf "$tmp/incomplete.tar" -C "$tmp/archive" Sparkle.framework
export FIXTURE_ARCHIVE="$tmp/incomplete.tar"
export SPARKLE_SHA256="$(shasum -a 256 "$FIXTURE_ARCHIVE" | awk '{print $1}')"
if fetch; then echo 'expected missing-tool rejection' >&2; exit 1; fi
expect_downloads 7
cmp "$tmp/receipt" "$VENDOR_DIR/.sparkle-receipt"
[ -x "$VENDOR_DIR/bin/generate_appcast" ]
printf 'PASS: legacy cache, matching pin, version, checksum, missing tool, FORCE, checksum failure, incomplete archive\n'
