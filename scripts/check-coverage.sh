#!/usr/bin/env bash
# Report first-party Swift package coverage and enforce the production-source floor.
set -euo pipefail

usage() {
	printf 'Usage: %s\n       %s --self-test\n' "$0" "$0" >&2
}

fail() {
	printf '✗ %s\n' "$1" >&2
	exit 1
}

require_command() {
	command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

calculate_metrics() {
	local coverage_json="$1"
	local package_root="${2%/}/"

	jq --arg package_root "$package_root" '
		def totals:
			reduce .[] as $file (
				{lines: 0, covered: 0};
				.lines += ($file.summary.lines.count // 0)
				| .covered += ($file.summary.lines.covered // 0)
			)
			| . + {
				percent: (
					if .lines == 0 then 0
					else (.covered * 100 / .lines)
					end
				)
			};

		.data[0].files as $files
		| ($package_root + "Sources/") as $sources_root
		| ($package_root + "Tests/") as $tests_root
		| [$files[] | select(.filename | startswith($sources_root))] as $production
		| [$files[] | select(
			(.filename | startswith($sources_root))
			or (.filename | startswith($tests_root))
		)] as $first_party
		| {
			aggregate: ($first_party | totals),
			production: ($production | totals),
			modules: (
				$production
				| sort_by(.filename | ltrimstr($sources_root) | split("/")[0])
				| group_by(.filename | ltrimstr($sources_root) | split("/")[0])
				| map({
					name: (.[0].filename | ltrimstr($sources_root) | split("/")[0]),
					metrics: (. | totals)
				})
			)
		}
	' "$coverage_json"
}

format_report() {
	local metrics_json="$1"
	local floor="$2"
	local aggregate_lines aggregate_covered aggregate_percent
	local production_lines production_covered production_percent

	aggregate_lines="$(jq -r '.aggregate.lines' <<<"$metrics_json")"
	aggregate_covered="$(jq -r '.aggregate.covered' <<<"$metrics_json")"
	aggregate_percent="$(jq -r '.aggregate.percent' <<<"$metrics_json")"
	production_lines="$(jq -r '.production.lines' <<<"$metrics_json")"
	production_covered="$(jq -r '.production.covered' <<<"$metrics_json")"
	production_percent="$(jq -r '.production.percent' <<<"$metrics_json")"

	printf '### Coverage\n\n'
	printf '| Scope | Covered / lines | Coverage |\n'
	printf '| --- | ---: | ---: |\n'
	printf '| First-party aggregate | %s / %s | %.1f%% |\n' \
		"$aggregate_covered" "$aggregate_lines" "$aggregate_percent"
	printf '| Production sources (gate: %.1f%%) | %s / %s | %.1f%% |\n' \
		"$floor" "$production_covered" "$production_lines" "$production_percent"
	printf '\n#### Production modules\n\n'
	printf '| Module | Covered / lines | Coverage |\n'
	printf '| --- | ---: | ---: |\n'
	jq -r '.modules[] | [.name, .metrics.covered, .metrics.lines, .metrics.percent] | @tsv' \
		<<<"$metrics_json" \
		| while IFS=$'\t' read -r module covered lines percent; do
			printf "| \`%s\` | %s / %s | %.1f%% |\n" "$module" "$covered" "$lines" "$percent"
		done
}

coverage_fixture_dir=""

self_test() {
	require_command jq
	require_command xcrun

	coverage_fixture_dir="$(mktemp -d -t gancho-coverage-check.XXXXXX)"
	trap 'rm -rf "${coverage_fixture_dir:-}"' EXIT

	local package_root="$coverage_fixture_dir/Packages/GanchoKit"
	local source_dir="$package_root/Sources/CoverageFixture"
	local source_file="$source_dir/CoverageFixture.swift"
	local binary="$coverage_fixture_dir/coverage-fixture"
	mkdir -p "$source_dir"
	cat >"$source_file" <<'SWIFT'
func seededBranch(_ coveredPath: Bool) -> Int {
    if coveredPath {
        return 1
    }
    return 0
}

let coveredPath = CommandLine.arguments.contains("--covered-path")
print(seededBranch(coveredPath))
SWIFT

	xcrun swiftc -profile-generate -profile-coverage-mapping "$source_file" -o "$binary"
	LLVM_PROFILE_FILE="$coverage_fixture_dir/partial.profraw" "$binary" --covered-path >/dev/null
	xcrun llvm-profdata merge -sparse "$coverage_fixture_dir/partial.profraw" \
		-o "$coverage_fixture_dir/partial.profdata"
	xcrun llvm-cov export "$binary" \
		-instr-profile "$coverage_fixture_dir/partial.profdata" \
		-summary-only >"$coverage_fixture_dir/partial.json"

	LLVM_PROFILE_FILE="$coverage_fixture_dir/full-covered.profraw" \
		"$binary" --covered-path >/dev/null
	LLVM_PROFILE_FILE="$coverage_fixture_dir/full-uncovered.profraw" "$binary" >/dev/null
	xcrun llvm-profdata merge -sparse \
		"$coverage_fixture_dir/full-covered.profraw" \
		"$coverage_fixture_dir/full-uncovered.profraw" \
		-o "$coverage_fixture_dir/full.profdata"
	xcrun llvm-cov export "$binary" \
		-instr-profile "$coverage_fixture_dir/full.profdata" \
		-summary-only >"$coverage_fixture_dir/full.json"

	local partial_metrics full_metrics partial_percent full_percent
	partial_metrics="$(calculate_metrics "$coverage_fixture_dir/partial.json" "$package_root")"
	full_metrics="$(calculate_metrics "$coverage_fixture_dir/full.json" "$package_root")"
	partial_percent="$(jq -r '.production.percent' <<<"$partial_metrics")"
	full_percent="$(jq -r '.production.percent' <<<"$full_metrics")"

	awk -v partial="$partial_percent" -v full="$full_percent" \
		'BEGIN { exit (partial < full ? 0 : 1) }' \
		|| fail "seeded uncovered production branch did not reduce source coverage"

	printf '✓ coverage classifier self-test passed (partial %.1f%% < full %.1f%%)\n' \
		"$partial_percent" "$full_percent"
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

require_command jq
require_command xcrun
require_command swift

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
package_path="${PACKAGE_PATH:-Packages/GanchoKit}"
coverage_floor="${COVERAGE_FLOOR:-80}"
package_root="$(cd "$repo_root/$package_path" && pwd)"
bin_path="$(swift build --package-path "$package_root" --show-bin-path)"
profile_data="$bin_path/codecov/default.profdata"
xctest_bundle="$(find "$bin_path" -maxdepth 1 -name '*.xctest' -print | head -1)"

[[ -f "$profile_data" ]] || fail "coverage profile not found; run swift test --enable-code-coverage first"
[[ -n "$xctest_bundle" ]] || fail "test bundle not found under $bin_path"

test_binary="$xctest_bundle/Contents/MacOS/$(basename "$xctest_bundle" .xctest)"
[[ -x "$test_binary" ]] || fail "test binary is missing or not executable: $test_binary"

coverage_json="$(mktemp -t gancho-coverage.XXXXXX)"
trap 'rm -f "${coverage_json:-}"' EXIT
xcrun llvm-cov export "$test_binary" \
	-instr-profile "$profile_data" \
	-summary-only >"$coverage_json"

metrics_json="$(calculate_metrics "$coverage_json" "$package_root")"
production_lines="$(jq -r '.production.lines' <<<"$metrics_json")"
production_percent="$(jq -r '.production.percent' <<<"$metrics_json")"
[[ "$production_lines" -gt 0 ]] || fail "coverage report contains no production source lines"

report="$(format_report "$metrics_json" "$coverage_floor")"
printf '%s\n' "$report"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
	printf '%s\n' "$report" >>"$GITHUB_STEP_SUMMARY"
fi

awk -v actual="$production_percent" -v floor="$coverage_floor" \
	'BEGIN { exit (actual >= floor ? 0 : 1) }' \
	|| fail "production-source coverage ${production_percent}% is below the ${coverage_floor}% floor"

printf '✓ production-source coverage %.1f%% meets the %.1f%% floor\n' \
	"$production_percent" "$coverage_floor"
