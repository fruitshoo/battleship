#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/../.." && pwd)"
source "$script_dir/harness_log_gate.sh"
godot_bin="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
log_file="$(mktemp -t battleship_soldier_balance.XXXXXX.log)"

cleanup() {
	rm -f "$log_file"
}
trap cleanup EXIT

HOME=/tmp BATTLESHIP_SOLDIER_BALANCE_AUTO_QUIT=1 BATTLESHIP_DISABLE_SUPPORT_FLEET_AUTOSPAWN=1 "$godot_bin" \
	--headless \
	--path "$project_root" \
	res://scenes/test/soldier_balance_preview.tscn 2>&1 | tee "$log_file"

harness_check_log_gate "SoldierBalance" "$log_file"

if ! grep -Fq "[SoldierBalance] summary" "$log_file"; then
	echo "[SoldierBalance] missing summary output" >&2
	exit 1
fi
