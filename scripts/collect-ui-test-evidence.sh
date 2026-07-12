#!/usr/bin/env bash
# Export XCUITest evidence, publish a compact summary, and reject false-green runs.
set -euo pipefail

usage() {
	printf 'Usage: %s <result-bundle> <label> <output-directory>\n       %s --self-test\n' \
		"$0" "$0" >&2
}

xcresulttool() {
	if [[ -n "${XCRESULTTOOL:-}" ]]; then
		"$XCRESULTTOOL" "$@"
	else
		xcrun xcresulttool "$@"
	fi
}

markdown_escape() {
	printf '%s' "$1" | tr '\r\n' '  ' | sed 's/|/\\|/g'
}

collect_evidence() {
	local result_bundle="$1"
	local label="$2"
	local output_directory="$3"
	local summary_json="$output_directory/summary.json"
	local tests_json="$output_directory/tests.json"
	local summary_markdown="$output_directory/summary.md"
	local attachments_directory="$output_directory/attachments"
	local total passed failed skipped expected result environment

	[[ -d "$result_bundle" ]] || {
		printf '✗ UI test result bundle does not exist: %s\n' "$result_bundle" >&2
		return 1
	}
	mkdir -p "$output_directory"

	xcresulttool get test-results summary --path "$result_bundle" --compact >"$summary_json"
	xcresulttool get test-results tests --path "$result_bundle" --compact >"$tests_json"
	xcresulttool export attachments --path "$result_bundle" --output-path "$attachments_directory"

	total="$(jq -er '.totalTestCount' "$summary_json")"
	passed="$(jq -er '.passedTests' "$summary_json")"
	failed="$(jq -er '.failedTests' "$summary_json")"
	skipped="$(jq -er '.skippedTests' "$summary_json")"
	expected="$(jq -er '.expectedFailures' "$summary_json")"
	result="$(jq -er '.result' "$summary_json")"
	environment="$(jq -er '.environmentDescription' "$summary_json")"

	{
		printf '### %s\n\n' "$(markdown_escape "$label")"
		printf '| Result | Total | Passed | Failed | Skipped | Expected failures |\n'
		printf '| --- | ---: | ---: | ---: | ---: | ---: |\n'
		printf '| %s | %s | %s | %s | %s | %s |\n\n' \
			"$(markdown_escape "$result")" "$total" "$passed" "$failed" "$skipped" "$expected"
		printf '**Environment:** %s\n' "$(markdown_escape "$environment")"

		if ((skipped > 0)); then
			printf '\n#### Skipped tests\n'
			jq -r '
				def walk_nodes: ., (.children[]? | walk_nodes);
				.testNodes[]? | walk_nodes
				| select(.nodeType == "Test Case" and .result == "Skipped")
				| . as $test
				| [
					$test.name,
					(([$test | walk_nodes
						| select(.nodeType == "Failure Message")
						| .name] | first | sub("^Test skipped - "; ""))
						// "No skip reason recorded in the result bundle")
				]
				| @tsv
			' "$tests_json" | while IFS=$'\t' read -r test_name reason; do
				printf -- "- \`%s\` — %s\n" \
					"$(markdown_escape "$test_name")" "$(markdown_escape "$reason")"
			done
		fi
	} >"$summary_markdown"

	cat "$summary_markdown"
	if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
		cat "$summary_markdown" >>"$GITHUB_STEP_SUMMARY"
	fi

	# A suite with no passing assertion is not evidence, even when every test
	# reports Skipped. Failed tests remain non-zero here so this collector also
	# cannot accidentally turn a red xcodebuild step green.
	if ((passed == 0)); then
		printf '✗ %s produced no passing UI tests\n' "$label" >&2
		return 1
	fi
	if ((failed > 0)); then
		printf '✗ %s contains %s failed UI test(s)\n' "$label" "$failed" >&2
		return 1
	fi
	printf '✓ %s evidence collected in %s\n' "$label" "$output_directory"
}

self_test() {
	local fixture_directory fake_tool result_bundle
	fixture_directory="$(mktemp -d -t gancho-ui-evidence.XXXXXX)"
	trap 'rm -rf "${fixture_directory:-}"' EXIT
	result_bundle="$fixture_directory/fixture.xcresult"
	fake_tool="$fixture_directory/xcresulttool"
	mkdir -p "$result_bundle"

	cat >"$fake_tool" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$1 $2 $3" == "get test-results summary" ]]; then
	case "${FAKE_SCENARIO:-failed}" in
		failed)
			printf '%s\n' '{"totalTestCount":3,"passedTests":1,"failedTests":1,"skippedTests":1,"expectedFailures":0,"result":"Failed","environmentDescription":"Seeded runner"}'
			;;
		zero)
			printf '%s\n' '{"totalTestCount":2,"passedTests":0,"failedTests":0,"skippedTests":2,"expectedFailures":0,"result":"Skipped","environmentDescription":"Seeded runner"}'
			;;
		passed)
			printf '%s\n' '{"totalTestCount":1,"passedTests":1,"failedTests":0,"skippedTests":0,"expectedFailures":0,"result":"Passed","environmentDescription":"Seeded runner"}'
			;;
	esac
elif [[ "$1 $2 $3" == "get test-results tests" ]]; then
	printf '%s\n' '{"testNodes":[{"nodeType":"UI test bundle","name":"Fixture","children":[{"nodeType":"Test Case","name":"testSkipped","result":"Skipped","children":[{"nodeType":"Failure Message","name":"Test skipped - Seeded unavailable interaction"}]}]}]}'
elif [[ "$1 $2" == "export attachments" ]]; then
	output_path=""
	while (($# > 0)); do
		if [[ "$1" == "--output-path" ]]; then
			output_path="${2:-}"
			break
		fi
		shift
	done
	[[ -n "$output_path" ]]
	mkdir -p "$output_path"
	printf 'seeded screenshot\n' >"$output_path/failure.png"
	printf '%s\n' '{"attachments":["failure.png"]}' >"$output_path/manifest.json"
else
	printf 'unexpected fake xcresulttool arguments: %s\n' "$*" >&2
	exit 2
fi
EOF
	chmod +x "$fake_tool"

	if GITHUB_STEP_SUMMARY='' XCRESULTTOOL="$fake_tool" FAKE_SCENARIO=failed \
		"$0" "$result_bundle" "Seeded failure" "$fixture_directory/failed" >/dev/null 2>&1
	then
		printf '✗ evidence collector accepted a seeded failed run\n' >&2
		return 1
	fi
	grep -q '| Failed | 3 | 1 | 1 | 1 | 0 |' "$fixture_directory/failed/summary.md"
	grep -q 'Seeded unavailable interaction' "$fixture_directory/failed/summary.md"
	[[ -f "$fixture_directory/failed/attachments/failure.png" ]]

	if GITHUB_STEP_SUMMARY='' XCRESULTTOOL="$fake_tool" FAKE_SCENARIO=zero \
		"$0" "$result_bundle" "Seeded all-skipped run" "$fixture_directory/zero" \
		>/dev/null 2>&1
	then
		printf '✗ evidence collector accepted a run with no passing assertion\n' >&2
		return 1
	fi

	GITHUB_STEP_SUMMARY='' XCRESULTTOOL="$fake_tool" FAKE_SCENARIO=passed \
		"$0" "$result_bundle" "Seeded passing run" "$fixture_directory/passed" \
		>/dev/null
	printf '✓ UI test evidence collector self-test passed\n'
}

if [[ "${1:-}" == "--self-test" ]]; then
	[[ "$#" -eq 1 ]] || {
		usage
		exit 2
	}
	self_test
	exit
fi

[[ "$#" -eq 3 ]] || {
	usage
	exit 2
}
collect_evidence "$1" "$2" "$3"
