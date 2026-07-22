#!/usr/bin/env bash
# Restore the tracked app-wide SwiftPM lock into the generated Xcode workspace.
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

canonical_lock="${GANCHO_APP_PACKAGE_LOCK:-Dependencies/Package.resolved}"
project="${PROJECT:-Gancho.xcodeproj}"
generated_lock="$project/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"

if [[ ! -f "$canonical_lock" ]]; then
	printf 'error: canonical app dependency lock not found: %s\n' "$canonical_lock" >&2
	exit 1
fi

mkdir -p "$(dirname "$generated_lock")"
cp "$canonical_lock" "$generated_lock"
cmp -s "$canonical_lock" "$generated_lock" || {
	printf 'error: failed to install app dependency lock into %s\n' "$generated_lock" >&2
	exit 1
}

printf 'Installed app dependency lock: %s\n' "$generated_lock"
