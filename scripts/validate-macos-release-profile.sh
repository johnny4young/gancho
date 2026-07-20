#!/usr/bin/env bash
# Validate the Developer ID provisioning profile required by Gancho's
# direct-download CloudKit build. Reads metadata only; never touches app data.
set -euo pipefail

PROFILE="${1:-}"
APP=""
if [ "${2:-}" = "--app" ]; then
	APP="${3:-}"
fi

if [ -z "$PROFILE" ] || [ ! -f "$PROFILE" ]; then
	echo "error: usage: $0 <Gancho.provisionprofile> [--app <Gancho.app>]" >&2
	exit 1
fi
if [ -n "$APP" ] && [ ! -d "$APP" ]; then
	echo "error: app bundle not found: $APP" >&2
	exit 1
fi

TEAM_ID="${MACOS_SIGN_TEAM_ID:-JGWX5ZT2N2}"
BUNDLE_ID="com.johnny4young.gancho"
APP_IDENTIFIER="$TEAM_ID.$BUNDLE_ID"
CLOUD_CONTAINER="iCloud.$BUNDLE_ID"
PROFILE_PLIST="$(mktemp -t gancho-profile.XXXXXX).plist"
APP_ENTITLEMENTS=""

cleanup() {
	rm -f "$PROFILE_PLIST"
	[ -z "$APP_ENTITLEMENTS" ] || rm -f "$APP_ENTITLEMENTS"
}
trap cleanup EXIT

fail() {
	echo "error: $*" >&2
	exit 1
}

profile_value() {
	# plutil uses KVC key paths. Callers must escape literal periods inside
	# entitlement dictionary keys (for example, `com\.apple\.…`).
	plutil -extract "$1" raw -o - "$PROFILE_PLIST" 2>/dev/null || true
}

plist_value() {
	local plist="$1" key="$2"
	plutil -extract "$key" raw -o - "$plist" 2>/dev/null || true
}

array_contains() {
	local plist="$1" key="$2" expected="$3" json
	json="$(plutil -extract "$key" json -o - "$plist" 2>/dev/null || true)"
	grep -Fq "\"$expected\"" <<< "$json"
}

# com.apple.developer.icloud-services is an explicit ["CloudKit"] array in a
# Mac App Store profile but the "*" wildcard (all iCloud services) in a
# Developer ID profile. Both authorize CloudKit; accept either shape. Use xml1,
# not json: `plutil -extract … json` cannot serialize the bare "*" scalar and
# errors out ("Invalid object in plist for JSON format").
profile_authorizes_cloudkit() {
	local plist="$1" xml
	xml="$(plutil -extract 'Entitlements.com\.apple\.developer\.icloud-services' \
		xml1 -o - "$plist" 2>/dev/null || true)"
	grep -Fq '<string>CloudKit</string>' <<< "$xml" \
		|| grep -Fq '<string>*</string>' <<< "$xml"
}

security cms -D -i "$PROFILE" > "$PROFILE_PLIST" 2>/dev/null \
	|| fail "provisioning profile is not a valid Apple CMS payload"
plutil -lint "$PROFILE_PLIST" >/dev/null \
	|| fail "decoded provisioning profile is not a valid plist"

PROFILE_NAME="$(profile_value Name)"
PROFILE_UUID="$(profile_value UUID)"
EXPIRATION="$(profile_value ExpirationDate)"
[ -n "$PROFILE_UUID" ] || fail "profile UUID is missing"
[ "$(profile_value ProvisionsAllDevices)" = "true" ] \
	|| fail "profile is not a Developer ID profile (ProvisionsAllDevices must be true)"
array_contains "$PROFILE_PLIST" Platform OSX \
	|| fail "profile does not authorize macOS"
array_contains "$PROFILE_PLIST" TeamIdentifier "$TEAM_ID" \
	|| fail "profile team does not match $TEAM_ID"
[ "$(profile_value 'Entitlements.com\.apple\.application-identifier')" = "$APP_IDENTIFIER" ] \
	|| fail "profile application identifier must be $APP_IDENTIFIER"
array_contains \
	"$PROFILE_PLIST" 'Entitlements.com\.apple\.developer\.icloud-container-identifiers' \
	"$CLOUD_CONTAINER" \
	|| fail "profile does not authorize $CLOUD_CONTAINER"
profile_authorizes_cloudkit "$PROFILE_PLIST" \
	|| fail "profile does not authorize CloudKit"
[ "$(profile_value 'Entitlements.com\.apple\.developer\.icloud-container-environment')" = "Production" ] \
	|| fail "profile CloudKit environment must be Production"
[ "$(profile_value 'Entitlements.com\.apple\.developer\.aps-environment')" = "production" ] \
	|| fail "profile push environment must be production"

[ -n "$EXPIRATION" ] || fail "profile expiration date is missing"
EXPIRATION_EPOCH="$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$EXPIRATION" '+%s' 2>/dev/null || true)"
[ -n "$EXPIRATION_EPOCH" ] || fail "profile expiration date is unreadable: $EXPIRATION"
[ "$EXPIRATION_EPOCH" -gt "$(date -u '+%s')" ] || fail "profile expired at $EXPIRATION"

if [ -n "$APP" ]; then
	EMBEDDED="$APP/Contents/embedded.provisionprofile"
	[ -f "$EMBEDDED" ] || fail "app does not embed Contents/embedded.provisionprofile"
	cmp -s "$PROFILE" "$EMBEDDED" \
		|| fail "embedded provisioning profile differs from the validated profile"

	APP_ENTITLEMENTS="$(mktemp -t gancho-entitlements.XXXXXX).plist"
	codesign --display --entitlements :- "$APP" > "$APP_ENTITLEMENTS" 2>/dev/null \
		|| fail "could not read signed app entitlements"
	plutil -lint "$APP_ENTITLEMENTS" >/dev/null \
		|| fail "signed app entitlements are not a valid plist"
	[ "$(plist_value "$APP_ENTITLEMENTS" 'com\.apple\.application-identifier')" = "$APP_IDENTIFIER" ] \
		|| fail "signed app identifier entitlement must be $APP_IDENTIFIER"
	[ "$(plist_value "$APP_ENTITLEMENTS" 'com\.apple\.developer\.team-identifier')" = "$TEAM_ID" ] \
		|| fail "signed app team entitlement must be $TEAM_ID"
	array_contains \
		"$APP_ENTITLEMENTS" 'com\.apple\.developer\.icloud-container-identifiers' \
		"$CLOUD_CONTAINER" \
		|| fail "signed app does not contain the expected iCloud container"
	array_contains "$APP_ENTITLEMENTS" 'com\.apple\.developer\.icloud-services' CloudKit \
		|| fail "signed app does not contain the CloudKit service entitlement"
	[ "$(plist_value "$APP_ENTITLEMENTS" 'com\.apple\.developer\.icloud-container-environment')" = "Production" ] \
		|| fail "signed app CloudKit environment must be Production"
	[ "$(plist_value "$APP_ENTITLEMENTS" 'com\.apple\.developer\.aps-environment')" = "production" ] \
		|| fail "signed app push environment must be production"
fi

printf '✓ Developer ID profile valid: %s (%s, expires %s)\n' \
	"${PROFILE_NAME:-unnamed}" "$PROFILE_UUID" "$EXPIRATION"
if [ -n "$APP" ]; then
	printf '✓ Embedded profile and production CloudKit/Push entitlements match the signed app\n'
fi
