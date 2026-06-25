#!/usr/bin/env bash
# Build Gancho.app for macOS and package it as a release ZIP.
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

PROJECT="${PROJECT:-Gancho.xcodeproj}"
SCHEME="${SCHEME:-Gancho}"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA="${DERIVED_DATA:-build/release-macos}"
OUTPUT_DIR="${OUTPUT_DIR:-dist}"
VERSION="${VERSION:-$(sed -nE 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"?([0-9][0-9A-Za-z.-]*)"?[[:space:]]*$/\1/p' project.yml | head -n1)}"
ZIP_PATH="$OUTPUT_DIR/Gancho-$VERSION.zip"
RESULT_BUNDLE="${RESULT_BUNDLE:-build/release-macos.xcresult}"

if [ -z "$VERSION" ]; then
	echo "error: VERSION is empty and MARKETING_VERSION could not be read" >&2
	exit 1
fi

mkdir -p "$OUTPUT_DIR" build
rm -rf "$DERIVED_DATA" "$RESULT_BUNDLE" "$ZIP_PATH" "$ZIP_PATH.sha256"

printf '==> Generating Xcode project\n'
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

if [ -n "${CODE_SIGN_IDENTITY:-}" ]; then
	printf '==> Verifying code signature\n'
	codesign --verify --deep --strict --verbose=2 "$APP_PATH"
	if codesign --display --verbose=2 "$APP_PATH" 2>&1 | grep -q 'flags=.*runtime'; then
		printf '✓ Hardened runtime is enabled\n'
	else
		echo "error: signed app is missing the hardened runtime" >&2
		exit 1
	fi

	if [ "${#notary_args[@]}" -gt 0 ] || [ -n "$notary_profile" ]; then
		printf '==> Submitting app for notarization\n'
		pre_notary_zip="$(mktemp -t gancho-notary.XXXXXX).zip"
		ditto -c -k --keepParent "$APP_PATH" "$pre_notary_zip"
		notary_plist="$(mktemp -t gancho-notary-result.XXXXXX).plist"
		if [ -n "$notary_profile" ]; then
			xcrun notarytool submit "$pre_notary_zip" --keychain-profile "$notary_profile" --wait --output-format plist > "$notary_plist"
		else
			xcrun notarytool submit "$pre_notary_zip" "${notary_args[@]}" --wait --output-format plist > "$notary_plist"
		fi
		status="$(plutil -extract status raw -o - "$notary_plist" 2>/dev/null || true)"
		id="$(plutil -extract id raw -o - "$notary_plist" 2>/dev/null || true)"
		if [ "$status" != "Accepted" ]; then
			echo "error: notarization status was ${status:-unknown}" >&2
			if [ -n "$id" ]; then
				if [ -n "$notary_profile" ]; then
					xcrun notarytool log "$id" --keychain-profile "$notary_profile" || true
				else
					xcrun notarytool log "$id" "${notary_args[@]}" || true
				fi
			fi
			exit 1
		fi
		xcrun stapler staple "$APP_PATH"
		rm -f "$pre_notary_zip" "$notary_plist"
		printf '✓ Notarization accepted and stapled\n'
	else
		printf 'warning: notarization credentials are not configured; signed ZIP is not stapled\n' >&2
	fi
fi

printf '==> Creating %s\n' "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
shasum -a 256 "$ZIP_PATH" > "$ZIP_PATH.sha256"

printf '==> Release artifact\n'
printf 'ZIP:    %s\n' "$ZIP_PATH"
printf 'SHA256: %s\n' "$(awk '{print $1}' "$ZIP_PATH.sha256")"
