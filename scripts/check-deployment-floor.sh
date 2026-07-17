#!/usr/bin/env bash
# Deployment-floor inventory (COMP-01): what would BREAK if Gancho lowered its
# minimum OS from macOS 26 / iOS 26 to a candidate floor?
#
# Method: temporarily rewrite the package manifest's `platforms:` to the probe
# floor and build EACH target separately, so one target's failure never masks
# another's (a plain `swift build` stops at the first broken module and hides
# everything downstream). The manifest is always restored, even on interrupt.
#
# This script only REPORTS. It never edits source, and its findings are the
# backlog for the availability-gate work.
#
#   scripts/check-deployment-floor.sh                  # default probe: macOS 15 / iOS 18
#   scripts/check-deployment-floor.sh --macos 14 --ios 17
#   scripts/check-deployment-floor.sh --quiet          # summary only
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

macos_floor="15"
ios_floor="18"
quiet=""
while [ $# -gt 0 ]; do
	case "$1" in
	--macos)
		macos_floor="$2"
		shift 2
		;;
	--ios)
		ios_floor="$2"
		shift 2
		;;
	--quiet)
		quiet="1"
		shift
		;;
	*)
		echo "usage: $0 [--macos 15] [--ios 18] [--quiet]" >&2
		exit 2
		;;
	esac
done

manifest="Packages/GanchoKit/Package.swift"
backup="$(mktemp -t gancho-manifest)"
cp "$manifest" "$backup"
# The manifest MUST come back no matter how this exits — a left-over lowered
# floor would silently change what every later build checks.
restore() { cp "$backup" "$manifest"; rm -f "$backup"; }
trap restore EXIT INT TERM

sed -i '' \
	-e "s/\.macOS(\.v26)/.macOS(.v${macos_floor})/" \
	-e "s/\.iOS(\.v26)/.iOS(.v${ios_floor})/" \
	"$manifest"

targets=(ClipboardCore GanchoKit GanchoSync GanchoAI GanchoAppCore GanchoDesign GanchoTelemetry)
log_dir="$(mktemp -d -t gancho-floor)"
total=0
declare -a broken=()

printf '==> Probing floor macOS %s / iOS %s (target by target)\n\n' "$macos_floor" "$ios_floor"
for target in "${targets[@]}"; do
	log="$log_dir/$target.log"
	# A target that fails is the POINT of this probe, not a script error.
	(cd Packages/GanchoKit && swift build --target "$target" >"$log" 2>&1) || true
	count="$(grep -Ec "is only available in|is unavailable" "$log" 2>/dev/null || true)"
	count="${count:-0}"
	if [ "$count" -gt 0 ]; then
		broken+=("$target")
		total=$((total + count))
		printf '✗ %-16s %s availability error(s)\n' "$target" "$count"
		if [ -z "$quiet" ]; then
			# One line per distinct API, with the file that uses it.
			grep -E "error: '.*' is only available|error: .* is unavailable" "$log" \
				| sed -E 's|^.*/Sources/|    Sources/|' \
				| sed -E "s/ error: /: /" \
				| sort -u | head -20
		fi
	else
		printf '✓ %-16s builds at the probe floor\n' "$target"
	fi
done

printf '\n==> Summary: %s availability error(s) across %s of %s targets\n' \
	"$total" "${#broken[@]}" "${#targets[@]}"
if [ "${#broken[@]}" -gt 0 ]; then
	printf '    Blocking targets: %s\n' "${broken[*]}"
	printf '    Each API above needs an availability gate or a fallback before\n'
	printf '    the floor can drop (see .planning notes / docs/ARCHITECTURE.md).\n'
	exit 1
fi
printf '    Nothing blocks this floor in the package. App shells still need\n'
printf '    their own probe (project.yml deploymentTarget).\n'
