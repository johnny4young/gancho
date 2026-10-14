#!/usr/bin/env bash
# Sign freshly built test applications only on a disposable hosted runner.
set -euo pipefail

[ "${GITHUB_ACTIONS:-}" = true ] && [ "${RUNNER_ENVIRONMENT:-}" = github-hosted ] \
	&& [ "$(id -un)" = runner ] || { echo "error: disposable hosted runner required" >&2; exit 1; }
: "${MACOS_CODE_SIGN_IDENTITY:?Signing identity is required}"
: "${MACOS_SIGN_TEAM_ID:?Signing team is required}"

keychain="$RUNNER_TEMP/gancho-handoff.keychain-db"
bash "$(dirname "$0")/import-hosted-signing-certificate.sh" "$keychain"

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
# Built test code runs next; it must not find an unlocked signing identity.
security delete-keychain "$keychain"
