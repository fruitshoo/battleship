#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/../.." && pwd)"
source "$script_dir/harness_log_gate.sh"
godot_bin="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
log_file="$(mktemp -t battleship_sea_site_preview.XXXXXX.log)"

cleanup() {
	rm -f "$log_file"
}
trap cleanup EXIT

HOME=/tmp BATTLESHIP_SEA_SITE_PREVIEW_AUTO_QUIT=1 "$godot_bin" \
	--headless \
	--path "$project_root" \
	res://scenes/test/sea_site_preview.tscn \
	--quit 2>&1 | tee "$log_file" | harness_filter_known_exit_leaks

harness_check_log_gate "SeaSitePreview" "$log_file"
if ! grep -q "\[SeaSitePreview\] ok" "$log_file"; then
	echo "[SeaSitePreview] missing ok marker" >&2
	exit 1
fi
