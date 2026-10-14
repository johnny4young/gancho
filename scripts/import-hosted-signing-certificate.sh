#!/usr/bin/env bash
# Import the signing certificate into a temporary keychain on a disposable hosted runner.
set -euo pipefail

[ "${GITHUB_ACTIONS:-}" = true ] && [ "${RUNNER_ENVIRONMENT:-}" = github-hosted ] \
	&& [ "$(id -un)" = runner ] || { echo "error: disposable hosted runner required" >&2; exit 1; }
: "${MACOS_CERTIFICATE_P12:?Signing certificate is required}"
: "${MACOS_CERTIFICATE_PASSWORD:?Certificate password is required}"
keychain="${1:?usage: import-hosted-signing-certificate.sh <keychain-path>}"

certificate="${keychain%.keychain-db}.p12"
keychain_password="$(openssl rand -base64 24)"
echo "::add-mask::$keychain_password"
trap 'rm -f "$certificate"' EXIT
umask 077
printf '%s' "$MACOS_CERTIFICATE_P12" | base64 --decode > "$certificate"
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 3600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$certificate" -P "$MACOS_CERTIFICATE_PASSWORD" \
	-T /usr/bin/codesign -t cert -f pkcs12 -k "$keychain" >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: \
	-k "$keychain_password" "$keychain" >/dev/null
security list-keychains -d user -s "$keychain" \
	"$(security default-keychain -d user | tr -d ' \"')"
