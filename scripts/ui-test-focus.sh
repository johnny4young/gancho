#!/usr/bin/env bash
# Validate a focused UI test request and prove every requested test really passed.
set -euo pipefail

readonly MAX_ITERATIONS=50

usage() {
	printf 'Usage: %s arguments <test-target> <tests> <iterations>\n' "$0" >&2
	printf '       %s verify <tests.json> <tests>\n       %s --self-test\n' "$0" "$0" >&2
	printf 'Tests are space-separated: ClassName or ClassName/testMethod.\n' >&2
}

reject() {
	printf '::error::%s\n' "$1"
	exit 2
}

parse_tests() {
	tokens=()
	IFS=$' \t\n' read -r -d '' -a tokens <<<"$1" || true
	((${#tokens[@]} > 0)) || reject 'Name at least one UI test class or method'
	local token
	for token in "${tokens[@]}"; do
		[[ "$token" =~ ^[A-Za-z_][A-Za-z0-9_]*(/[A-Za-z_][A-Za-z0-9_]*)?$ ]] ||
			reject 'Tests must be ClassName or ClassName/testMethod'
	done
}

print_arguments() {
	local target="$1" tests="$2" iterations="$3" token
	[[ "$target" == GanchoUITests || "$target" == GanchoiOSUITests ]] ||
		reject 'Unsupported UI test target'
	if ! [[ "$iterations" =~ ^[1-9][0-9]?$ ]] || ((iterations > MAX_ITERATIONS)); then
		reject "Iterations must be between 1 and $MAX_ITERATIONS"
	fi
	parse_tests "$tests"
	if ((iterations > 1)); then
		printf '%s\n' -test-iterations "$iterations"
	fi
	for token in "${tokens[@]}"; do
		printf '%s\n' "-only-testing:$target/$token"
	done
}

# -only-testing accepts a misspelled name and runs nothing for it, so a passing
# run alone does not show that the requested test ran.
verify_tests() {
	local tests_json="$1" tests="$2" token missing=0 identifiers
	parse_tests "$tests"
	identifiers="$(jq -r '
		def walk_nodes: ., (.children[]? | walk_nodes);
		.testNodes[]? | walk_nodes
		| select(.nodeType == "Test Case" and .result == "Passed")
		| .nodeIdentifier
	' "$tests_json")"
	for token in "${tokens[@]}"; do
		if [[ "$token" == */* ]]; then
			grep -Fxq "$token()" <<<"$identifiers" && continue
		else
			grep -Fxq "$token" <<<"$(cut -d/ -f1 <<<"$identifiers")" && continue
		fi
		printf '::error::No passing result for %s\n' "$token"
		missing=1
	done
	return "$missing"
}

self_test() {
	local fixture
	fixture="$(mktemp -t gancho-ui-focus.XXXXXX)"
	trap 'rm -f "${fixture:-}"' EXIT

	[[ "$("$0" arguments GanchoUITests 'PanelUITests A/testB' 1 | tr '\n' ' ')" == \
		'-only-testing:GanchoUITests/PanelUITests -only-testing:GanchoUITests/A/testB ' ]]
	[[ "$("$0" arguments GanchoiOSUITests A 10 | tr '\n' ' ')" == \
		'-test-iterations 10 -only-testing:GanchoiOSUITests/A ' ]]
	local rejected
	for rejected in '' ' ' 'A;touch' 'A/b/c' '-skip-testing:A' "\$(touch)" '*' $'A\n-enableCodeCoverage'; do
		if "$0" arguments GanchoUITests "$rejected" 1 >/dev/null 2>&1; then
			printf '✗ accepted tests: %s\n' "$rejected" >&2
			return 1
		fi
	done
	for rejected in 0 51 -1 1x '' '1 -skip-testing:A'; do
		if "$0" arguments GanchoUITests A "$rejected" >/dev/null 2>&1; then
			printf '✗ accepted iterations: %s\n' "$rejected" >&2
			return 1
		fi
	done

	cat >"$fixture" <<'EOF'
{"testNodes":[{"nodeType":"Test Plan","children":[{"nodeType":"Test Suite","children":[
{"nodeType":"Test Case","nodeIdentifier":"Ran/testOne()","result":"Passed"},
{"nodeType":"Test Case","nodeIdentifier":"Ran/testSkipped()","result":"Skipped"},
{"nodeType":"Test Case","nodeIdentifier":"OnlySkipped/testTwo()","result":"Skipped"}]}]}]}
EOF
	"$0" verify "$fixture" 'Ran Ran/testOne' >/dev/null
	for rejected in Ran/testSkipped OnlySkipped Missing Ra an Ran/testOn; do
		if "$0" verify "$fixture" "$rejected" >/dev/null 2>&1; then
			printf '✗ verified without a passing result: %s\n' "$rejected" >&2
			return 1
		fi
	done
	printf '✓ UI test focus self-test passed\n'
}

case "${1:-}" in
	arguments)
		(($# == 4)) || {
			usage
			exit 2
		}
		print_arguments "$2" "$3" "$4"
		;;
	verify)
		(($# == 3)) || {
			usage
			exit 2
		}
		verify_tests "$2" "$3"
		;;
	--self-test)
		self_test
		;;
	*)
		usage
		exit 2
		;;
esac
