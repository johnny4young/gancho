#!/usr/bin/env bash
# Reject unexpected compiler/build warnings in captured SwiftPM and Xcode logs.
set -euo pipefail

usage() {
	printf 'Usage: %s <build-log>...\n       %s --self-test\n' "$0" "$0" >&2
}

is_warning() {
	case "$1" in
		*warning:* | *WARNING:*) return 0 ;;
		*) return 1 ;;
	esac
}

is_allowed_warning() {
	local line="$1"
	local metadata_target="$2"

	case "$line" in
		# A host that can build both Apple Silicon and Intel reports this when
		# xcodebuild is intentionally allowed to choose the native destination.
		*"xcodebuild: WARNING: Using the first of multiple matching destinations:")
			return 0
			;;
		# Xcode 26.6 schedules metadata extraction for every Swift app extension.
		# GanchoShare intentionally declares no App Intents, so the extractor
		# reports this toolchain diagnostic after successfully building the target.
		*"warning: Metadata extraction skipped. No AppIntents.framework dependency found.")
			[[ "$metadata_target" == "GanchoShare" ]]
			return
			;;
		*) return 1 ;;
	esac
}

check_log() {
	local log_file="$1"
	local line
	local metadata_target=""
	local unexpected=0

	[[ -f "$log_file" ]] || {
		printf '✗ build warning log does not exist: %s\n' "$log_file" >&2
		return 1
	}

	while IFS= read -r line || [[ -n "$line" ]]; do
		case "$line" in
			"ExtractAppIntentsMetadata (in target '"*"' from project '"*"')")
				metadata_target="${line#*target \'}"
				metadata_target="${metadata_target%%\'*}"
				;;
		esac

		if is_warning "$line" && ! is_allowed_warning "$line" "$metadata_target"; then
			printf '✗ unexpected warning in %s:\n  %s\n' "$log_file" "$line" >&2
			unexpected=1
		fi
	done <"$log_file"

	return "$unexpected"
}

warning_fixture_dir=""

self_test() {
	warning_fixture_dir="$(mktemp -d -t gancho-warning-check.XXXXXX)"
	trap 'rm -rf "${warning_fixture_dir:-}"' EXIT

	cat >"$warning_fixture_dir/allowed.log" <<'EOF'
--- xcodebuild: WARNING: Using the first of multiple matching destinations:
ExtractAppIntentsMetadata (in target 'GanchoShare' from project 'Gancho')
2026-07-11 appintentsmetadataprocessor[1:1] warning: Metadata extraction skipped. No AppIntents.framework dependency found.
EOF
	check_log "$warning_fixture_dir/allowed.log" || {
		printf '✗ warning classifier rejected its narrow toolchain allowlist\n' >&2
		return 1
	}

	cat >"$warning_fixture_dir/seeded-source-warning.log" <<'EOF'
/repo/Apps/GanchoMac/AppModel.swift:42:9: warning: seeded first-party warning
EOF
	if check_log "$warning_fixture_dir/seeded-source-warning.log" >/dev/null 2>&1; then
		printf '✗ warning classifier accepted a seeded first-party warning\n' >&2
		return 1
	fi

	cat >"$warning_fixture_dir/wrong-target.log" <<'EOF'
ExtractAppIntentsMetadata (in target 'GanchoiOS' from project 'Gancho')
2026-07-11 appintentsmetadataprocessor[1:1] warning: Metadata extraction skipped. No AppIntents.framework dependency found.
EOF
	if check_log "$warning_fixture_dir/wrong-target.log" >/dev/null 2>&1; then
		printf '✗ warning classifier allowed the App Intents diagnostic for the wrong target\n' >&2
		return 1
	fi

	printf '✓ build warning classifier self-test passed\n'
}

if [[ "${1:-}" == "--self-test" ]]; then
	[[ "$#" -eq 1 ]] || {
		usage
		exit 2
	}
	self_test
	exit
fi

[[ "$#" -gt 0 ]] || {
	usage
	exit 2
}

failed=0
for log_file in "$@"; do
	if ! check_log "$log_file"; then
		failed=1
	fi
done

[[ "$failed" -eq 0 ]] || exit 1
printf '✓ build warning check passed (%s log(s))\n' "$#"
