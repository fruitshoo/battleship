#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/../.." && pwd)"
source "$script_dir/harness_log_gate.sh"
godot_bin="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
log_file="$(mktemp -t battleship_contract_sweep.XXXXXX.log)"

cleanup() {
	rm -f "$log_file"
}
trap cleanup EXIT

HOME=/tmp "$godot_bin" \
	--headless \
	--path "$project_root" \
	res://scenes/test/project_contract_sweep.tscn \
	--quit 2>&1 | tee "$log_file" | harness_filter_known_exit_leaks

harness_check_log_gate "ContractSweep" "$log_file"
