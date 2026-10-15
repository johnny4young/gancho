#!/usr/bin/env bash
# A fresh hosted simulator stalls for minutes on its first UI-test launch. Pay
# that once on an unmeasured case so the measured run starts warm. Diagnostics
# collection is off: it can hang for ten minutes after a passing warm-up.
set -euo pipefail

readonly WARM_UP_TEST="${GANCHO_WARM_UP_TEST:-GanchoiOSUITests/SourceAppFilterUITests}"
readonly APP_BUNDLES=(com.johnny4young.gancho com.johnny4young.gancho.GanchoiOSUITests.xctrunner)

usage() {
	printf 'Usage: %s warm <simulator-udid> <output-directory> [xcodebuild-option...]\n' "$0" >&2
	printf '       %s stop <simulator-udid>\n       %s --self-test\n' "$0" "$0" >&2
}

xcodebuild_tool() {
	if [[ -n "${XCODEBUILD:-}" ]]; then
		"$XCODEBUILD" "$@"
	else
		xcodebuild "$@"
	fi
}

simctl_tool() {
	if [[ -n "${SIMCTL:-}" ]]; then
		"$SIMCTL" "$@"
	else
		xcrun simctl "$@"
	fi
}

# Never fails the caller: a warm-up that never passes only warns.
warm() {
	local udid="$1" output="$2"
	shift 2
	local attempt log started
	mkdir -p "$output"
	for attempt in 1 2; do
		log="$output/ios-warm-up-$attempt.log"
		started=$SECONDS
		rm -rf "$output/ios-warm-up-$attempt.xcresult"
		xcodebuild_tool test-without-building -project Gancho.xcodeproj -scheme GanchoiOS \
			-destination "platform=iOS Simulator,id=$udid" \
			-only-testing:"$WARM_UP_TEST" \
			-parallel-testing-enabled NO \
			-test-timeouts-enabled YES \
			-default-test-execution-time-allowance 120 \
			-maximum-test-execution-time-allowance 180 \
			-collect-test-diagnostics never \
			-resultBundlePath "$output/ios-warm-up-$attempt.xcresult" \
			"$@" >"$log" 2>&1 || true
		# A passing case proves the launch warmed; zero matched tests does not.
		if grep -qE "Test Case '.*' passed \(" "$log"; then
			printf 'Warm-up attempt %s passed in %ss\n' "$attempt" "$((SECONDS - started))"
			return 0
		fi
		printf 'Warm-up attempt %s failed after %ss\n' "$attempt" "$((SECONDS - started))"
		# Only a launch stall is worth another cold start.
		grep -qE 'exceeded execution time allowance|Failed to (launch|terminate)' "$log" || break
	done
	printf '::warning::The simulator warm-up never passed; the measured run may start cold\n'
}

# A warm-up cut off by its step timeout must not leave the simulator busy.
stop() {
	local bundle
	for bundle in "${APP_BUNDLES[@]}"; do
		simctl_tool terminate "$1" "$bundle" >/dev/null 2>&1 || true
	done
}

self_test() {
	local fixture_directory fake_xcodebuild fake_simctl scenario output
	fixture_directory="$(mktemp -d -t gancho-warm-up.XXXXXX)"
	trap 'rm -rf "${fixture_directory:-}"' EXIT
	fake_xcodebuild="$fixture_directory/xcodebuild"
	fake_simctl="$fixture_directory/simctl"

	cat >"$fake_xcodebuild" <<'EOF'
#!/usr/bin/env bash
calls="$FAKE_STATE/xcodebuild-calls"
count=$(($(cat "$calls" 2>/dev/null || echo 0) + 1))
echo "$count" >"$calls"
case "$FAKE_SCENARIO" in
	passed) printf "Test Case '-[A.B testX]' passed (20.1 seconds).\n" ;;
	zero) printf 'Executed 0 tests, with 0 failures\n' ;;
	broken) printf "Test Case '-[A.B testX]' failed (3.2 seconds).\n"; exit 65 ;;
	stall)
		if [[ "$count" == 1 ]]; then
			printf "Test Case '-[A.B testX]' exceeded execution time allowance of 2 minutes.\n"
			exit 65
		fi
		printf "Test Case '-[A.B testX]' passed (20.1 seconds).\n"
		;;
	stalled) printf 'Failed to launch com.johnny4young.gancho\n'; exit 65 ;;
esac
EOF
	cat >"$fake_simctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FAKE_STATE/simctl-calls"
exit 1
EOF
	chmod +x "$fake_xcodebuild" "$fake_simctl"

	expect_warm_up() {
		local scenario="$1" calls="$2" pattern="$3" state
		state="$fixture_directory/$scenario"
		mkdir -p "$state"
		output="$(FAKE_STATE="$state" FAKE_SCENARIO="$scenario" XCODEBUILD="$fake_xcodebuild" \
			"$0" warm fixture-udid "$state/build")"
		[[ "$(cat "$state/xcodebuild-calls")" == "$calls" ]] || {
			printf '✗ %s: expected %s xcodebuild calls\n' "$scenario" "$calls" >&2
			return 1
		}
		grep -qE "$pattern" <<<"$output" || {
			printf '✗ %s: unexpected output: %s\n' "$scenario" "$output" >&2
			return 1
		}
	}

	expect_warm_up passed 1 'attempt 1 passed'
	expect_warm_up zero 1 '::warning::'
	expect_warm_up broken 1 '::warning::'
	expect_warm_up stall 2 'attempt 2 passed'
	expect_warm_up stalled 2 '::warning::'

	scenario="$fixture_directory/stop"
	mkdir -p "$scenario"
	FAKE_STATE="$scenario" SIMCTL="$fake_simctl" "$0" stop fixture-udid
	[[ "$(cat "$scenario/simctl-calls")" == "terminate fixture-udid ${APP_BUNDLES[0]}
terminate fixture-udid ${APP_BUNDLES[1]}" ]] || {
		printf '✗ stop did not terminate the app and the UI test runner\n' >&2
		return 1
	}
	printf '✓ iOS simulator warm-up self-test passed\n'
}

case "${1:-}" in
	--self-test)
		[[ "$#" -eq 1 ]] || {
			usage
			exit 2
		}
		self_test
		;;
	warm)
		[[ "$#" -ge 3 ]] || {
			usage
			exit 2
		}
		shift
		warm "$@"
		;;
	stop)
		[[ "$#" -eq 2 ]] || {
			usage
			exit 2
		}
		stop "$2"
		;;
	*)
		usage
		exit 2
		;;
esac
