#!/usr/bin/env bash
# Sign freshly built test applications only on a disposable hosted runner.
set -euo pipefail

[ "${GITHUB_ACTIONS:-}" = true ] && [ "${RUNNER_ENVIRONMENT:-}" = github-hosted ] \
	&& [ "$(id -un)" = runner ] || { echo "error: disposable hosted runner required" >&2; exit 1; }
: "${MACOS_CERTIFICATE_P12:?Signing certificate is required}"
: "${MACOS_CERTIFICATE_PASSWORD:?Certificate password is required}"
: "${MACOS_CODE_SIGN_IDENTITY:?Signing identity is required}"
: "${MACOS_SIGN_TEAM_ID:?Signing team is required}"

keychain="$RUNNER_TEMP/gancho-handoff.keychain-db"
certificate="$RUNNER_TEMP/gancho-handoff.p12"
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
rm -f "$certificate"

products="$GITHUB_WORKSPACE/build/signed-handoff/Build/Products/Debug"
app="$products/Gancho.app"
for target in \
	"$app/Contents/Frameworks/SQLCipher.framework" \
	"$app/Contents/MacOS/GanchoMenuBarHelper" \
	"$app/Contents/MacOS/gancho-cli" \
	"$app" \
	"$products/GanchoPasteReceiver.app"; do
	codesign --force --keychain "$keychain" --sign "$MACOS_CODE_SIGN_IDENTITY" \
		--timestamp --options runtime "$target"
done
codesign --verify --deep --strict "$app"
python3 - <<'PY'
import json
import os
from pathlib import Path
import subprocess

products = Path(os.environ['GITHUB_WORKSPACE']) / 'build/signed-handoff/Build/Products/Debug'
records = []
for path in [products / 'Gancho.app', products / 'Gancho.app/Contents/MacOS/GanchoMenuBarHelper',
             products / 'GanchoPasteReceiver.app']:
    subprocess.run(['codesign', '--verify', '--strict', str(path)], check=True)
    details = subprocess.check_output(['codesign', '-dvv', str(path)], stderr=subprocess.STDOUT, text=True)
    assert 'TeamIdentifier=' + os.environ['MACOS_SIGN_TEAM_ID'] in details
    assert 'Authority=Developer ID Application:' in details or 'Authority=Apple Development:' in details
    assert 'runtime' in details
    records.append({'path': str(path), 'signature_verified': True, 'apple_identity': True,
                    'hardened_runtime': True})
Path('build/signed-handoff-signatures.json').write_text(json.dumps(records, indent=2) + '\n')
PY
