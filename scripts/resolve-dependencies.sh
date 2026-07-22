#!/usr/bin/env bash
# Deliberately regenerate both dependency graphs from their declared ranges.
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

package="${PACKAGE:-Packages/GanchoKit}"
project="${PROJECT:-Gancho.xcodeproj}"
scheme="${SCHEME:-Gancho}"
xcodebuild_command="${XCODEBUILD:-xcodebuild}"
swift_command="${SWIFT:-swift}"
package_lock="$package/Package.resolved"
app_lock="${GANCHO_APP_PACKAGE_LOCK:-Dependencies/Package.resolved}"
generated_lock="$project/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"

for lock in "$package_lock" "$app_lock" "$generated_lock"; do
	if [[ ! -f "$lock" ]]; then
		printf 'error: dependency lock not found: %s\n' "$lock" >&2
		exit 1
	fi
done

package_backup="$(mktemp -t gancho-package-lock.XXXXXX)"
app_backup="$(mktemp -t gancho-app-lock.XXXXXX)"
generated_backup="$(mktemp -t gancho-generated-lock.XXXXXX)"
cp "$package_lock" "$package_backup"
cp "$app_lock" "$app_backup"
cp "$generated_lock" "$generated_backup"

resolved=false
cleanup() {
	status=$?
	if [[ "$resolved" != true ]]; then
		cp "$package_backup" "$package_lock"
		cp "$app_backup" "$app_lock"
		mkdir -p "$(dirname "$generated_lock")"
		cp "$generated_backup" "$generated_lock"
		printf 'Restored dependency locks after a failed resolution.\n' >&2
	fi
	rm -f "$package_backup" "$app_backup" "$generated_backup"
	exit "$status"
}
trap cleanup EXIT

# Xcode must resolve first while neither candidate lock is present. Otherwise
# it discovers GanchoKit's narrower lock and writes the app graph into it.
rm -f "$package_lock" "$generated_lock"
"$xcodebuild_command" -resolvePackageDependencies -project "$project" -scheme "$scheme"
cp "$generated_lock" "$app_lock"

# SwiftPM now resolves only the standalone package graph.
"$swift_command" package resolve --package-path "$package"
"$swift_command" scripts/check-dependency-resolution.swift --require-generated

resolved=true
printf 'Refreshed canonical package and app dependency locks.\n'
