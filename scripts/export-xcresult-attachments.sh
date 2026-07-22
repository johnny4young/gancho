#!/bin/bash
# Export screenshots and other kept attachments from an Xcode result bundle.
set -euo pipefail

result_bundle="${1:-build/macos-ui-tests.xcresult}"
output_directory="${2:-build/ui-test-evidence}"

if [[ ! -d "$result_bundle" ]]; then
	echo "error: result bundle not found: $result_bundle" >&2
	exit 1
fi

case "$output_directory" in
"" | "/" | "." | "..")
	echo "error: unsafe evidence output directory: $output_directory" >&2
	exit 1
	;;
esac

rm -rf "$output_directory"
mkdir -p "$(dirname "$output_directory")"

xcrun xcresulttool export attachments \
	--path "$result_bundle" \
	--output-path "$output_directory"

attachment_count="$(find "$output_directory" -type f ! -name manifest.json | wc -l | tr -d ' ')"
echo "✓ exported $attachment_count UI attachment(s) to $output_directory"
