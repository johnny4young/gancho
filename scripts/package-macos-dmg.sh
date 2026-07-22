#!/usr/bin/env bash
# Build the direct-download (non-App-Store) Gancho.app and package it as a
# signed, notarized DMG. Production releases require a Developer ID profile
# that authorizes the app's CloudKit container and production push environment.
# With REQUIRE_PRODUCTION_RELEASE unset, an unsigned local development artifact
# is still possible; it must never be published.
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

# The DMG IS the direct-download channel.
export GANCHO_COMPILATION_CONDITIONS="GANCHO_DIRECT_DOWNLOAD"

# Sign with the direct-download production entitlements. These restricted
# CloudKit/Push entitlements require a matching Developer ID provisioning profile.
# The Gancho target resolves this through an app-only custom build setting;
# restricted entitlements must never leak to frameworks or helper executables.
ENTITLEMENTS="$repo_root/Apps/GanchoMac/Gancho-DirectDownload.entitlements"

PROJECT="${PROJECT:-Gancho.xcodeproj}"
SCHEME="${SCHEME:-Gancho}"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA="${DERIVED_DATA:-build/release-macos-direct}"
OUTPUT_DIR="${OUTPUT_DIR:-dist}"
VERSION="${VERSION:-$(sed -nE 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"?([0-9][0-9A-Za-z.-]*)"?[[:space:]]*$/\1/p' project.yml | head -n1)}"
DMG_PATH="$OUTPUT_DIR/Gancho-$VERSION.dmg"
RESULT_BUNDLE="${RESULT_BUNDLE:-build/release-macos-direct.xcresult}"
REQUIRE_PRODUCTION_RELEASE="${REQUIRE_PRODUCTION_RELEASE:-0}"
PROVISIONING_PROFILE="${MACOS_PROVISIONING_PROFILE:-}"
PROFILE_UUID=""

if [ -z "$VERSION" ]; then
	echo "error: VERSION is empty and MARKETING_VERSION could not be read" >&2
	exit 1
fi

if [ "$REQUIRE_PRODUCTION_RELEASE" = "1" ]; then
	[ -n "${CODE_SIGN_IDENTITY:-}" ] \
		|| { echo "error: production release requires CODE_SIGN_IDENTITY" >&2; exit 1; }
	[ -n "${MACOS_SIGN_TEAM_ID:-${DEVELOPMENT_TEAM:-}}" ] \
		|| { echo "error: production release requires MACOS_SIGN_TEAM_ID" >&2; exit 1; }
	[ -n "$PROVISIONING_PROFILE" ] \
		|| { echo "error: production release requires MACOS_PROVISIONING_PROFILE" >&2; exit 1; }
	[ -z "${GANCHO_LICENSE_SIGNING_KEY:-}" ] \
		|| { echo "error: public releases must not embed GANCHO_LICENSE_SIGNING_KEY" >&2; exit 1; }
fi

if [ -n "${CODE_SIGN_IDENTITY:-}" ] && [ "$ENTITLEMENTS" = "$repo_root/Apps/GanchoMac/Gancho-DirectDownload.entitlements" ]; then
	[ -n "$PROVISIONING_PROFILE" ] \
		|| { echo "error: CloudKit-enabled signing requires MACOS_PROVISIONING_PROFILE" >&2; exit 1; }
fi

if [ -n "$PROVISIONING_PROFILE" ]; then
	[ -f "$PROVISIONING_PROFILE" ] \
		|| { echo "error: provisioning profile not found: $PROVISIONING_PROFILE" >&2; exit 1; }
	printf '==> Validating Developer ID provisioning profile\n'
	./scripts/validate-macos-release-profile.sh "$PROVISIONING_PROFILE"
	profile_plist="$(mktemp -t gancho-profile-build.XXXXXX).plist"
	security cms -D -i "$PROVISIONING_PROFILE" > "$profile_plist" 2>/dev/null
	PROFILE_UUID="$(plutil -extract UUID raw -o - "$profile_plist")"
	rm -f "$profile_plist"
	profile_dir="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
	mkdir -p "$profile_dir"
	cp "$PROVISIONING_PROFILE" "$profile_dir/$PROFILE_UUID.provisionprofile"
fi
mkdir -p "$OUTPUT_DIR" build
rm -rf "$DERIVED_DATA" "$RESULT_BUNDLE" "$DMG_PATH" "$DMG_PATH.sha256"

printf '==> Fetching Sparkle.framework (auto-updater, direct-download)\n'
./scripts/fetch-sparkle.sh

printf '==> Generating Xcode project (GANCHO_DIRECT_DOWNLOAD)\n'
"${XCODEGEN:-xcodegen}" generate

build_args=(
	-disableAutomaticPackageResolution
	-project "$PROJECT"
	-scheme "$SCHEME"
	-configuration "$CONFIGURATION"
	-derivedDataPath "$DERIVED_DATA"
	-resultBundlePath "$RESULT_BUNDLE"
	"GANCHO_MAC_ENTITLEMENTS_PATH=Apps/GanchoMac/Gancho-DirectDownload.entitlements"
	"GANCHO_PROVISIONING_PROFILE_SPECIFIER=$PROFILE_UUID"
)

if [ -n "${CODE_SIGN_IDENTITY:-}" ]; then
	printf '==> Building signed Release app (%s)\n' "$CODE_SIGN_IDENTITY"
	build_args+=(
		CODE_SIGNING_ALLOWED=YES
		CODE_SIGN_STYLE=Manual
		"CODE_SIGN_IDENTITY=$CODE_SIGN_IDENTITY"
		ENABLE_HARDENED_RUNTIME=YES
		CODE_SIGN_INJECT_BASE_ENTITLEMENTS=YES
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

RESOLVED_ENTITLEMENTS="$ENTITLEMENTS"
GENERATED_ENTITLEMENTS=""
if [ -n "${CODE_SIGN_IDENTITY:-}" ] && [ -n "$PROVISIONING_PROFILE" ]; then
	# Capture the entitlements Xcode actually signed (production CloudKit/Push
	# plus the base-injected identifier/team keys) while the bundle seal is
	# still intact, then embed the profile. Copying embedded.provisionprofile
	# into the bundle first would break the seal before we read it. Fail closed
	# if extraction yields anything but a valid entitlements plist.
	GENERATED_ENTITLEMENTS="$(mktemp -t gancho-signed-entitlements.XXXXXX).plist"
	codesign --display --entitlements :- "$APP_PATH" > "$GENERATED_ENTITLEMENTS" 2>/dev/null \
		|| { echo "error: could not read signed app entitlements" >&2; exit 1; }
	plutil -lint "$GENERATED_ENTITLEMENTS" >/dev/null \
		|| { echo "error: extracted app entitlements are not a valid plist" >&2; exit 1; }
	# `xcodebuild build` injects com.apple.security.get-task-allow (a debugging
	# entitlement) that notarization rejects; drop it before the main binary is
	# re-sealed with these entitlements. plutil key paths use "." as a level
	# separator, so the dotted entitlement key must be escaped.
	plutil -remove 'com\.apple\.security\.get-task-allow' "$GENERATED_ENTITLEMENTS" \
		2>/dev/null || true
	RESOLVED_ENTITLEMENTS="$GENERATED_ENTITLEMENTS"
	cp "$PROVISIONING_PROFILE" "$APP_PATH/Contents/embedded.provisionprofile"
fi

# Strip com.apple.security.get-task-allow from an already-signed executable and
# re-sign it. `xcodebuild build` (unlike `archive`) injects that debugging
# entitlement into every executable, and notarization rejects it. Preserve any
# other entitlements the binary already carries.
strip_get_task_allow_and_resign() {
	local target="$1" ents
	ents="$(mktemp -t gancho-strip.XXXXXX).plist"
	if codesign --display --entitlements :- "$target" > "$ents" 2>/dev/null \
		&& [ -s "$ents" ] && plutil -lint "$ents" >/dev/null 2>&1; then
		# Escape the dots: plutil treats "." in a key path as a level separator.
		plutil -remove 'com\.apple\.security\.get-task-allow' "$ents" 2>/dev/null || true
		codesign --force --options runtime --timestamp \
			--entitlements "$ents" --sign "$CODE_SIGN_IDENTITY" "$target"
	else
		codesign --force --options runtime --timestamp \
			--sign "$CODE_SIGN_IDENTITY" "$target"
	fi
	rm -f "$ents"
}

# Re-sign inside-out, then re-seal the app over everything. Two notarization
# blockers are handled here: (1) the auxiliary executables in Contents/MacOS (the
# embedded CLI and the menu-bar helper) carry the build-injected get-task-allow,
# stripped and re-signed above; (2) Xcode's Embed & Sign leaves Sparkle's nested
# XPC services, Autoupdate, and Updater.app ad-hoc signed, which notarization
# also rejects. The main binary is re-sealed last with the get-task-allow-free
# entitlements. The app is not sandboxed, so the helpers need no sandbox/network
# entitlements.
finalize_app_signing() {
	local exe
	for exe in "$APP_PATH/Contents/MacOS/"*; do
		[ -f "$exe" ] || continue
		[ "$(basename "$exe")" = "Gancho" ] && continue
		printf '==> Re-signing %s (drop get-task-allow)\n' "$(basename "$exe")"
		strip_get_task_allow_and_resign "$exe"
	done
	local spk="$APP_PATH/Contents/Frameworks/Sparkle.framework"
	if [ -d "$spk" ]; then
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
	fi
	codesign --force --options runtime --timestamp \
		--entitlements "$RESOLVED_ENTITLEMENTS" \
		--sign "$CODE_SIGN_IDENTITY" "$APP_PATH"
}

if [ -n "${CODE_SIGN_IDENTITY:-}" ]; then
	finalize_app_signing
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

if [ "$REQUIRE_PRODUCTION_RELEASE" = "1" ] \
	&& [ "${#notary_args[@]}" -eq 0 ] && [ -z "$notary_profile" ]; then
	echo "error: production release requires notarization credentials" >&2
	exit 1
fi

# Submit one artifact for notarization and staple another (the app is submitted
# as a zip but stapled in place; the DMG is both submitted and stapled).
notarize() {
	local submit="$1" staple="$2"
	if [ "${#notary_args[@]}" -eq 0 ] && [ -z "$notary_profile" ]; then
		if [ "$REQUIRE_PRODUCTION_RELEASE" = "1" ]; then
			echo "error: notarization credentials are required for $staple" >&2
			exit 1
		fi
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
	if [ -n "$PROVISIONING_PROFILE" ]; then
		./scripts/validate-macos-release-profile.sh "$PROVISIONING_PROFILE" --app "$APP_PATH"
	fi
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
if [ -n "$GENERATED_ENTITLEMENTS" ]; then
	rm -f "$GENERATED_ENTITLEMENTS"
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
	if ! spctl -a -t open --context context:primary-signature -vv "$DMG_PATH"; then
		if [ "$REQUIRE_PRODUCTION_RELEASE" = "1" ]; then
			echo "error: Gatekeeper rejected the release DMG" >&2
			exit 1
		fi
		printf 'warning: Gatekeeper assessment failed for development artifact\n' >&2
	fi
fi

shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"

# Homebrew cask bump source of truth: the two lines to paste into the tap's
# Casks/gancho.rb (mirrors Vitrine's <name>-cask-update.txt). Upload this with
# the DMG so the cask sha256 always matches the published bytes.
dmg_sha="$(awk '{print $1}' "$DMG_PATH.sha256")"
cask_update="$OUTPUT_DIR/gancho-cask-update.txt"
{
	printf 'version "%s"\n' "$VERSION"
	printf 'sha256 "%s"\n' "$dmg_sha"
} > "$cask_update"

printf '==> Release artifact\n'
printf 'DMG:    %s\n' "$DMG_PATH"
printf 'SHA256: %s\n' "$dmg_sha"
printf 'Cask:   %s\n' "$cask_update"
