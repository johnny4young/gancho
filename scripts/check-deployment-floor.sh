#!/usr/bin/env bash
# Deployment-floor inventory: what would break if Gancho lowered its minimum
# macOS version from 26 to a candidate floor?
#
# Method: temporarily rewrite the package manifest's `platforms:` to the probe
# floor and build EACH target separately, so one target's failure never masks
# another's (a plain `swift build` stops at the first broken module and hides
# everything downstream). The manifest is always restored, even on interrupt.
#
# This script only REPORTS. It never edits source; use its findings to decide
# where availability gates are required before changing deployment targets.
#
#   scripts/check-deployment-floor.sh                  # default probe: macOS 15
#   scripts/check-deployment-floor.sh --macos 14
#   scripts/check-deployment-floor.sh --quiet          # summary only
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

macos_floor="15"
quiet=""
usage() {
	echo "usage: $0 [--macos 15] [--quiet]" >&2
	exit 2
}
while [ $# -gt 0 ]; do
	case "$1" in
	--macos)
		[ $# -ge 2 ] || usage
		macos_floor="$2"
		shift 2
		;;
	--quiet)
		quiet="1"
		shift
		;;
	*)
		usage
		;;
	esac
done
case "$macos_floor" in
*[!0-9]* | "") usage ;;
esac

manifest="Packages/GanchoKit/Package.swift"
backup="$(mktemp -t gancho-manifest)"
cp "$manifest" "$backup"
# The manifest MUST come back no matter how this exits — a left-over lowered
# floor would silently change what every later build checks.
restore() {
	if [ -f "$backup" ]; then
		cp "$backup" "$manifest"
		rm -f "$backup"
	fi
}
trap restore EXIT
trap 'exit 130' INT TERM

sed -i '' \
	-e "s/\.macOS(\.v26)/.macOS(.v${macos_floor})/" \
	"$manifest"
if cmp -s "$manifest" "$backup"; then
	echo "error: expected the manifest to declare .macOS(.v26)" >&2
	exit 2
fi

targets=(ClipboardCore GanchoKit GanchoSync GanchoAI GanchoAppCore GanchoDesign GanchoTelemetry)
log_dir="$(mktemp -d -t gancho-floor)"
total=0
declare -a broken=()
declare -a probe_failures=()

printf '==> Probing macOS %s package floor (target by target)\n\n' "$macos_floor"
for target in "${targets[@]}"; do
	log="$log_dir/$target.log"
	# A target that fails is the POINT of this probe, not a script error.
	status=0
	(cd Packages/GanchoKit && swift build --target "$target" >"$log" 2>&1) || status=$?
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
	elif [ "$status" -ne 0 ]; then
		probe_failures+=("$target")
		printf '! %-16s build failed for a non-availability reason\n' "$target"
		if [ -z "$quiet" ]; then
			grep -E "error:|fatal error:" "$log" | head -20 || tail -20 "$log"
		fi
	else
		printf '✓ %-16s builds at the probe floor\n' "$target"
	fi
done

printf '\n==> Summary: %s availability error(s) across %s of %s targets\n' \
	"$total" "${#broken[@]}" "${#targets[@]}"
if [ "${#probe_failures[@]}" -gt 0 ]; then
	printf '    Inconclusive targets: %s\n' "${probe_failures[*]}"
	printf '    Fix the build environment or compiler error before trusting this inventory.\n'
	exit 2
fi
if [ "${#broken[@]}" -gt 0 ]; then
	printf '    Blocking targets: %s\n' "${broken[*]}"
	printf '    Each API above needs an availability gate or a fallback before\n'
	printf '    the floor can drop (see docs/DEPLOYMENT-FLOOR.md).\n'
	exit 1
fi
printf '    Nothing blocks this floor in the package. App shells still need\n'
printf '    their own probe (project.yml deploymentTarget).\n'
