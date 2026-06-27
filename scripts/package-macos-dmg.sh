#!/usr/bin/env bash
# Build the direct-download (non-App-Store) Gancho.app and package it as a
# signed, notarized DMG. This flavor turns on GANCHO_DIRECT_DOWNLOAD, so Pro
# comes from a Lemon Squeezy license key (not StoreKit). With no Developer ID
# identity the DMG is unsigned — a development artifact only; Gatekeeper will
# reject it on other Macs.
#
# Set GANCHO_LICENSE_SIGNING_KEY (base64 Ed25519 private key) to bake in the
# token signer for real sales; left empty, the build cannot mint licenses.
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

# The DMG IS the direct-download channel.
export GANCHO_COMPILATION_CONDITIONS="GANCHO_DIRECT_DOWNLOAD"

# Sign with the direct-download entitlements: no iCloud/Push, so manual Developer
# ID signing needs no provisioning profile. The runtime disables sync when the
# iCloud entitlement is absent. Override to a profile-backed file once the direct
# channel ships CloudKit sync.
# Absolute path: passed as a global build setting, it is resolved against each
# target's own SRCROOT, so a relative path would break the SwiftPM framework
# targets. The empty dict is a no-op for those frameworks and drops iCloud/Push
# from the app.
ENTITLEMENTS="${ENTITLEMENTS:-$repo_root/Apps/GanchoMac/Gancho-DirectDownload.entitlements}"

PROJECT="${PROJECT:-Gancho.xcodeproj}"
SCHEME="${SCHEME:-Gancho}"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA="${DERIVED_DATA:-build/release-macos-direct}"
OUTPUT_DIR="${OUTPUT_DIR:-dist}"
VERSION="${VERSION:-$(sed -nE 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"?([0-9][0-9A-Za-z.-]*)"?[[:space:]]*$/\1/p' project.yml | head -n1)}"
DMG_PATH="$OUTPUT_DIR/Gancho-$VERSION.dmg"
RESULT_BUNDLE="${RESULT_BUNDLE:-build/release-macos-direct.xcresult}"

if [ -z "$VERSION" ]; then
	echo "error: VERSION is empty and MARKETING_VERSION could not be read" >&2
	exit 1
fi

mkdir -p "$OUTPUT_DIR" build
rm -rf "$DERIVED_DATA" "$RESULT_BUNDLE" "$DMG_PATH" "$DMG_PATH.sha256"

printf '==> Fetching Sparkle.framework (auto-updater, direct-download)\n'
./scripts/fetch-sparkle.sh

printf '==> Generating Xcode project (GANCHO_DIRECT_DOWNLOAD)\n'
"${XCODEGEN:-xcodegen}" generate

build_args=(
	-project "$PROJECT"
	-scheme "$SCHEME"
	-configuration "$CONFIGURATION"
	-derivedDataPath "$DERIVED_DATA"
	-resultBundlePath "$RESULT_BUNDLE"
)

if [ -n "${CODE_SIGN_IDENTITY:-}" ]; then
	printf '==> Building signed Release app (%s)\n' "$CODE_SIGN_IDENTITY"
	build_args+=(
		CODE_SIGNING_ALLOWED=YES
		CODE_SIGN_STYLE=Manual
		"CODE_SIGN_IDENTITY=$CODE_SIGN_IDENTITY"
		"CODE_SIGN_ENTITLEMENTS=$ENTITLEMENTS"
		ENABLE_HARDENED_RUNTIME=YES
		CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
		OTHER_CODE_SIGN_FLAGS="--timestamp"
	)
	if [ -n "${MACOS_SIGN_TEAM_ID:-${DEVELOPMENT_TEAM:-}}" ]; then
		build_args+=("DEVELOPMENT_TEAM=${MACOS_SIGN_TEAM_ID:-${DEVELOPMENT_TEAM:-}}")
	fi
else
	printf '==> Building unsigned Release app (development artifact only)\n'
	build_args+=(CODE_SIGNING_ALLOWED=NO)
fi

xcodebuild "${build_args[@]}" build

APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/Gancho.app"
if [ ! -d "$APP_PATH" ]; then
	echo "error: expected app bundle not found at $APP_PATH" >&2
	exit 1
fi

# Re-sign Sparkle's nested helpers. Xcode's Embed & Sign re-signs the framework
# bundle with our identity but leaves the XPC services, Autoupdate, and
# Updater.app ad-hoc signed — notarization rejects ad-hoc nested executables.
# Sign inside-out, then re-seal the app over them. A forced re-sign drops
# entitlements, so re-apply the source ones. The app is not sandboxed, so the
# helpers need no sandbox/network entitlements.
sign_sparkle_helpers() {
	local spk="$APP_PATH/Contents/Frameworks/Sparkle.framework"
	[ -d "$spk" ] || return 0
	printf '==> Re-signing Sparkle helpers (%s)\n' "$CODE_SIGN_IDENTITY"
	local v="$spk/Versions/Current" item
	for item in \
		"$v/XPCServices/Downloader.xpc" \
		"$v/XPCServices/Installer.xpc" \
		"$v/Autoupdate" \
		"$v/Updater.app" \
		"$spk"; do
		[ -e "$item" ] && codesign --force --options runtime --timestamp \
			--sign "$CODE_SIGN_IDENTITY" "$item"
	done
	codesign --force --options runtime --timestamp \
		--entitlements "$ENTITLEMENTS" \
		--sign "$CODE_SIGN_IDENTITY" "$APP_PATH"
}

if [ -n "${CODE_SIGN_IDENTITY:-}" ]; then
	sign_sparkle_helpers
fi

notary_args=()
notary_profile=""
notary_key_path="${MACOS_NOTARY_KEY_P8:-}"
if [ -n "$notary_key_path" ] && [ -f "$notary_key_path" ] && [ -n "${MACOS_NOTARY_KEY_ID:-}" ] && [ -n "${MACOS_NOTARY_KEY_ISSUER_ID:-}" ]; then
	notary_args=(--key "$notary_key_path" --key-id "$MACOS_NOTARY_KEY_ID" --issuer "$MACOS_NOTARY_KEY_ISSUER_ID")
elif [ -n "${MACOS_NOTARY_APPLE_ID:-}" ] && [ -n "${MACOS_NOTARY_PASSWORD:-}" ] && [ -n "${MACOS_NOTARY_TEAM_ID:-}" ]; then
	notary_args=(--apple-id "$MACOS_NOTARY_APPLE_ID" --password "$MACOS_NOTARY_PASSWORD" --team-id "$MACOS_NOTARY_TEAM_ID")
elif [ -n "${MACOS_NOTARY_KEYCHAIN_PROFILE:-}" ]; then
	notary_profile="$MACOS_NOTARY_KEYCHAIN_PROFILE"
fi

# Submit one artifact for notarization and staple another (the app is submitted
# as a zip but stapled in place; the DMG is both submitted and stapled).
notarize() {
	local submit="$1" staple="$2"
	if [ "${#notary_args[@]}" -eq 0 ] && [ -z "$notary_profile" ]; then
		printf 'warning: notarization credentials not configured; %s is not stapled\n' "$staple" >&2
		return 0
	fi
	printf '==> Notarizing %s\n' "$staple"
	local plist
	plist="$(mktemp -t gancho-notary.XXXXXX).plist"
	if [ -n "$notary_profile" ]; then
		xcrun notarytool submit "$submit" --keychain-profile "$notary_profile" --wait --output-format plist > "$plist"
	else
		xcrun notarytool submit "$submit" "${notary_args[@]}" --wait --output-format plist > "$plist"
	fi
	local status
	status="$(plutil -extract status raw -o - "$plist" 2>/dev/null || true)"
	if [ "$status" != "Accepted" ]; then
		echo "error: notarization status was ${status:-unknown} for $staple" >&2
		local id
		id="$(plutil -extract id raw -o - "$plist" 2>/dev/null || true)"
		if [ -n "$id" ]; then
			if [ -n "$notary_profile" ]; then
				xcrun notarytool log "$id" --keychain-profile "$notary_profile" || true
			else
				xcrun notarytool log "$id" "${notary_args[@]}" || true
			fi
		fi
		exit 1
	fi
	xcrun stapler staple "$staple"
	rm -f "$plist"
	printf '✓ Notarized and stapled %s\n' "$staple"
}

if [ -n "${CODE_SIGN_IDENTITY:-}" ]; then
	printf '==> Verifying code signature\n'
	codesign --verify --deep --strict --verbose=2 "$APP_PATH"
	# Capture first: piping codesign straight into `grep -q` lets grep exit on
	# the first match and SIGPIPE codesign, which `set -o pipefail` then reports
	# as a failed pipeline even though the runtime flag is present.
	sig_info="$(codesign --display --verbose=2 "$APP_PATH" 2>&1)"
	if printf '%s\n' "$sig_info" | grep -q 'flags=.*runtime'; then
		printf '✓ Hardened runtime is enabled\n'
	else
		echo "error: signed app is missing the hardened runtime" >&2
		exit 1
	fi
	app_zip="$(mktemp -t gancho-app.XXXXXX).zip"
	ditto -c -k --keepParent "$APP_PATH" "$app_zip"
	notarize "$app_zip" "$APP_PATH"
	rm -f "$app_zip"
fi

printf '==> Creating %s\n' "$DMG_PATH"
staging="$(mktemp -d -t gancho-dmg)"
cp -R "$APP_PATH" "$staging/"
ln -s /Applications "$staging/Applications"
hdiutil create -volname "Gancho" -srcfolder "$staging" -ov -format UDZO "$DMG_PATH" >/dev/null
rm -rf "$staging"

if [ -n "${CODE_SIGN_IDENTITY:-}" ]; then
	printf '==> Signing the DMG\n'
	codesign --force --sign "$CODE_SIGN_IDENTITY" --timestamp "$DMG_PATH"
	notarize "$DMG_PATH" "$DMG_PATH"
	printf '==> Gatekeeper assessment\n'
	spctl -a -t open --context context:primary-signature -vv "$DMG_PATH" || true
fi

shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"

printf '==> Release artifact\n'
printf 'DMG:    %s\n' "$DMG_PATH"
printf 'SHA256: %s\n' "$(awk '{print $1}' "$DMG_PATH.sha256")"
