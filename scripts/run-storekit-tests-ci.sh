#!/usr/bin/env bash
# Run StoreKit integration tests without masking product failures when Apple's
# headless StoreKit service is unavailable on a GitHub-hosted macOS 26 runner.
set -euo pipefail

usage() {
	printf 'Usage: %s\n       %s --self-test\n' "$0" "$0" >&2
}

is_known_runner_failure() {
	local log_file="$1"
	local xcode_version="$2"

	[[ -f "$log_file" ]] || return 1
	case "$xcode_version" in
		"Xcode 26.4"* | "Xcode 26.5"* | "Xcode 26.6"*) ;;
		*) return 1 ;;
	esac

	grep -Fq \
		'Error saving configuration file: Error Domain=SKInternalErrorDomain Code=3' \
		"$log_file" &&
		grep -Fq \
		'Error Domain=ASOctaneSupportXPCService.ConfigurationError Code=0' \
		"$log_file" &&
		grep -Fq \
		'in off-device buy mode: Unable to Complete Request' \
		"$log_file"
}

self_test_fixture_dir=""

self_test() {
	self_test_fixture_dir="$(mktemp -d -t gancho-storekit-ci.XXXXXX)"
	trap 'rm -rf "${self_test_fixture_dir:-}"' EXIT

	cat >"$self_test_fixture_dir/known-runner-failure.log" <<'EOF'
[SKTestSession] Error saving configuration file: Error Domain=SKInternalErrorDomain Code=3 "(null)"
[Default] Received error that does not have a corresponding StoreKit Error: Error Domain=ASOctaneSupportXPCService.ConfigurationError Code=0 "(null)"
Failed to purchase com.johnny4young.gancho.pro.lifetime in off-device buy mode: Unable to Complete Request
EOF
	if ! is_known_runner_failure \
		"$self_test_fixture_dir/known-runner-failure.log" "Xcode 26.6"; then
		printf '✗ StoreKit CI classifier rejected the known runner failure\n' >&2
		return 1
	fi

	if is_known_runner_failure \
		"$self_test_fixture_dir/known-runner-failure.log" "Xcode 26.7"; then
		printf '✗ StoreKit CI classifier accepted an unreviewed Xcode version\n' >&2
		return 1
	fi

	cat >"$self_test_fixture_dir/product-failure.log" <<'EOF'
StoreKitPurchaseTests.swift:22: Expectation failed: purchase returned false
EOF
	if is_known_runner_failure \
		"$self_test_fixture_dir/product-failure.log" "Xcode 26.6"; then
		printf '✗ StoreKit CI classifier accepted a product failure\n' >&2
		return 1
	fi

	printf '✓ StoreKit CI infrastructure classifier self-test passed\n'
}

if [[ "${1:-}" == "--self-test" ]]; then
	[[ "$#" -eq 1 ]] || {
		usage
		exit 2
	}
	self_test
	exit
fi

[[ "$#" -eq 0 ]] || {
	usage
	exit 2
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
log_file="$repo_root/build/storekit-tests.log"
xcode_version="$(xcodebuild -version | sed -n '1p')"

set +e
make -C "$repo_root" test-storekit
test_status=$?
set -e

[[ "$test_status" -ne 0 ]] || exit 0

if [[ "${GITHUB_ACTIONS:-}" == "true" ]] &&
	is_known_runner_failure "$log_file" "$xcode_version"; then
	message="Apple's headless StoreKit service rejected the local configuration on this hosted macOS 26 runner. Product failures remain blocking; run make test-storekit on a developer Mac before release."
	printf '::warning title=StoreKitTest runner unavailable::%s\n' "$message"
	if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
		{
			printf '### StoreKit integration\n\n'
			printf '⚠️ %s\n\n' "$message"
			printf 'Toolchain: %s%s%s\n' "\`" "$xcode_version" "\`"
		} >>"$GITHUB_STEP_SUMMARY"
	fi
	exit 0
fi

printf '✗ StoreKit integration failed outside the narrow hosted-runner exception\n' >&2
exit "$test_status"
