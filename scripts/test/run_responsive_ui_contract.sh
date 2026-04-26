#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/../.." && pwd)"
source "$script_dir/harness_log_gate.sh"
godot_bin="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
log_file="$(mktemp -t battleship_responsive_ui_contract.XXXXXX.log)"

cleanup() {
	rm -f "$log_file"
}
trap cleanup EXIT

HOME=/tmp "$godot_bin" \
	--headless \
	--path "$project_root" \
	res://scenes/test/responsive_ui_contract.tscn 2>&1 | tee "$log_file" | harness_filter_known_exit_leaks

harness_check_log_gate "ResponsiveUiContract" "$log_file"
