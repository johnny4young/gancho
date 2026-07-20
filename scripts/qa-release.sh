#!/usr/bin/env bash
# QA a Gancho release DMG, ZIP, or app bundle without depending on DerivedData.
set -euo pipefail

APP_FAILURES=0
SIGNING_FAILURES=0
WARNINGS=0
TEMP_DIR=""
MOUNT_POINT=""

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
section() { printf '\n'; bold "==> $1"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m! %s\033[0m\n' "$1"; WARNINGS=$((WARNINGS + 1)); }
fail_app() { printf '  \033[31m✗ [APP]\033[0m %s\n' "$1"; APP_FAILURES=$((APP_FAILURES + 1)); }
fail_signing() { printf '  \033[31m✗ [SIGNING]\033[0m %s\n' "$1"; SIGNING_FAILURES=$((SIGNING_FAILURES + 1)); }
note() { printf '    %s\n' "$1"; }

cleanup() {
	if [ -n "$MOUNT_POINT" ]; then
		hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
	fi
	if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
		rm -rf "$TEMP_DIR"
	fi
}
trap cleanup EXIT

artifact="${1:-}"
if [ -z "$artifact" ]; then
	newest_mtime=0
	for candidate in dist/Gancho-*.dmg dist/Gancho-*.zip; do
		[ -e "$candidate" ] || continue
		mtime="$(stat -f %m "$candidate" 2>/dev/null || echo 0)"
		if [ "$mtime" -ge "$newest_mtime" ]; then
			newest_mtime="$mtime"
			artifact="$candidate"
		fi
	done
fi

if [ -z "$artifact" ]; then
	echo "usage: $0 <Gancho-VERSION.dmg | Gancho-VERSION.zip | Gancho.app>" >&2
	exit 1
fi
[ -e "$artifact" ] || { echo "error: artifact not found: $artifact" >&2; exit 1; }

case "$artifact" in
*.dmg)
	section "Mounting DMG read-only"
	TEMP_DIR="$(mktemp -d /tmp/gancho-qa.XXXXXX)"
	attach_plist="$TEMP_DIR/attach.plist"
	if hdiutil attach -readonly -nobrowse -plist "$artifact" > "$attach_plist"; then
		pass "DMG mounted read-only"
	else
		fail_app "DMG failed to mount"
		exit 3
	fi
	for index in $(seq 0 12); do
		MOUNT_POINT="$(plutil -extract "system-entities.$index.mount-point" raw -o - \
			"$attach_plist" 2>/dev/null || true)"
		[ -z "$MOUNT_POINT" ] || break
	done
	[ -n "$MOUNT_POINT" ] || { fail_app "DMG mounted without a readable volume"; exit 3; }
	APP="$MOUNT_POINT/Gancho.app"
	[ -d "$APP" ] || { fail_app "Gancho.app was not found in the DMG"; exit 3; }
	;;
*.zip)
	section "Unpacking ZIP"
	TEMP_DIR="$(mktemp -d /tmp/gancho-qa.XXXXXX)"
	if ditto -x -k "$artifact" "$TEMP_DIR"; then
		pass "ZIP unpacked"
	else
		fail_app "ZIP failed to unpack"
		exit 3
	fi
	APP="$(find "$TEMP_DIR" -maxdepth 2 -name 'Gancho.app' -type d -print -quit)"
	[ -n "$APP" ] || { fail_app "Gancho.app was not found in the ZIP"; exit 3; }
	;;
*.app)
	APP="$artifact"
	;;
*)
	echo "error: artifact must be a .dmg, .zip, or .app: $artifact" >&2
	exit 1
	;;
esac

INFO_PLIST="$APP/Contents/Info.plist"
plist_value() { plutil -extract "$1" raw -o - "$INFO_PLIST" 2>/dev/null || true; }

APP_VERSION="$(plist_value CFBundleShortVersionString)"
BUILD_VERSION="$(plist_value CFBundleVersion)"
BUNDLE_ID="$(plist_value CFBundleIdentifier)"
LSUIELEMENT="$(plist_value LSUIElement)"
EXECUTABLE="$(plist_value CFBundleExecutable)"

SIGN_IDENTITY="$(codesign --display --verbose=2 "$APP" 2>&1 | awk -F'Authority=' '/^Authority=/ { print $2; exit }' || true)"
[ -n "$SIGN_IDENTITY" ] || SIGN_IDENTITY="(none — unsigned or ad-hoc)"

section "QA environment"
note "macOS version : $(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
note "Architecture  : $(uname -m)"
note "Artifact      : $artifact"
note "App bundle    : $APP"
note "App version   : ${APP_VERSION:-(unknown)} (build ${BUILD_VERSION:-?})"
note "Bundle id     : ${BUNDLE_ID:-(unknown)}"
note "Signing id    : $SIGN_IDENTITY"
note "Tested at     : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"

section "Artifact structure"
if plutil -lint "$INFO_PLIST" >/dev/null 2>&1; then pass "Info.plist is valid"; else fail_app "Info.plist failed plutil -lint"; fi
[ -n "$APP_VERSION" ] && pass "CFBundleShortVersionString is present" || fail_app "CFBundleShortVersionString is missing"
[ -n "$BUILD_VERSION" ] && pass "CFBundleVersion is present" || fail_app "CFBundleVersion is missing"
[ "$BUNDLE_ID" = "com.johnny4young.gancho" ] && pass "Bundle identifier is com.johnny4young.gancho" || fail_app "unexpected bundle identifier: ${BUNDLE_ID:-missing}"
if [ "$LSUIELEMENT" = "true" ] || [ "$LSUIELEMENT" = "1" ] || [ "$LSUIELEMENT" = "YES" ]; then
	pass "LSUIElement is set for the menu-bar app"
else
	fail_app "LSUIElement is not set; the app would show a Dock icon"
fi
[ -n "$EXECUTABLE" ] && [ -x "$APP/Contents/MacOS/$EXECUTABLE" ] && pass "Main executable is present" || fail_app "main executable missing or not executable"
[ -x "$APP/Contents/MacOS/GanchoMenuBarHelper" ] && pass "Menu-bar helper is embedded" || warn "GanchoMenuBarHelper was not found as an executable in Contents/MacOS"

section "Signing and Gatekeeper"
SIGNED=0
signature_details="$(codesign --display --verbose=2 "$APP" 2>&1 || true)"
if grep -q '^Authority=Developer ID Application' <<< "$signature_details"; then
	SIGNED=1
fi

if [ "$SIGNED" -eq 1 ]; then
	if codesign --verify --deep --strict --verbose=2 "$APP" >/dev/null 2>&1; then pass "Developer ID signature verifies"; else fail_signing "codesign --verify --deep --strict failed"; fi
	if grep -q 'flags=.*runtime' <<< "$signature_details"; then pass "Hardened runtime is enabled"; else fail_signing "hardened runtime is missing"; fi
	if xcrun stapler validate "$APP" >/dev/null 2>&1; then pass "Stapled notarization ticket validates"; else fail_signing "stapled notarization ticket is missing or invalid"; fi
	if spctl -a -vv "$APP" >/dev/null 2>&1; then pass "Gatekeeper assessment passes"; else fail_signing "Gatekeeper assessment failed"; fi
	EMBEDDED_PROFILE="$APP/Contents/embedded.provisionprofile"
	if [ -f "$EMBEDDED_PROFILE" ]; then
		if ./scripts/validate-macos-release-profile.sh "$EMBEDDED_PROFILE" --app "$APP"; then
			pass "Production CloudKit/Push profile and signed entitlements match"
		else
			fail_signing "production CloudKit/Push profile validation failed"
		fi
	elif [ "${REQUIRE_SYNC_ENTITLEMENTS:-0}" = "1" ]; then
		fail_signing "sync-enabled release is missing embedded.provisionprofile"
	else
		warn "No embedded provisioning profile; cross-device CloudKit sync is unavailable"
	fi
else
	warn "Artifact is unsigned or not Developer ID-signed; this is development-only and not production-ready"
	if [ "${REQUIRE_SYNC_ENTITLEMENTS:-0}" = "1" ]; then
		fail_signing "production sync release must be Developer ID-signed"
	fi
fi

if [[ "$artifact" = *.dmg ]] && [ "$SIGNED" -eq 1 ]; then
	if codesign --verify --strict --verbose=2 "$artifact" >/dev/null 2>&1; then pass "DMG signature verifies"; else fail_signing "DMG signature verification failed"; fi
	if xcrun stapler validate "$artifact" >/dev/null 2>&1; then pass "DMG notarization ticket validates"; else fail_signing "DMG notarization ticket is missing or invalid"; fi
	if spctl -a -t open --context context:primary-signature -vv "$artifact" >/dev/null 2>&1; then pass "Gatekeeper accepts the DMG"; else fail_signing "Gatekeeper rejected the DMG"; fi
fi

section "Manual release smoke"
note "1. Launch Gancho and confirm no Dock icon appears."
note "2. Confirm the menu-bar item appears and the history panel opens with the configured shortcut."
note "3. Copy non-sensitive text and confirm it appears in history."
note "4. Copy a password-manager/sensitive item and confirm Gancho does not store it."
note "5. Paste a selected history item into a text field."
note "6. If sync is in scope, repeat capture and retention checks on a second device."

section "Summary"
if [ "$APP_FAILURES" -eq 0 ] && [ "$SIGNING_FAILURES" -eq 0 ]; then
	pass "Automated QA passed (${WARNINGS} warning(s))"
	exit 0
fi
[ "$APP_FAILURES" -gt 0 ] && note "App/artifact failures: $APP_FAILURES"
[ "$SIGNING_FAILURES" -gt 0 ] && note "Signing/notarization failures: $SIGNING_FAILURES"
if [ "$SIGNING_FAILURES" -gt 0 ]; then exit 2; fi
exit 3
