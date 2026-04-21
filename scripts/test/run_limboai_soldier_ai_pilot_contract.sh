#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/../.." && pwd)"
source "$script_dir/harness_log_gate.sh"
godot_bin="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
extension_path="res://addons/limboai/bin/limboai.gdextension"
extension_list="$project_root/.godot/extension_list.cfg"
log_file="$(mktemp -t battleship_limboai_soldier_ai_pilot_contract.XXXXXX.log)"

cleanup() {
	rm -f "$log_file"
}
trap cleanup EXIT

mkdir -p "$project_root/.godot"
touch "$extension_list"
if ! grep -Fxq "$extension_path" "$extension_list"; then
	printf '%s\n' "$extension_path" >> "$extension_list"
fi

HOME=/tmp "$godot_bin" \
	--headless \
	--path "$project_root" \
	res://scenes/test/limboai_soldier_ai_pilot_contract.tscn 2>&1 | tee "$log_file" | harness_filter_known_exit_leaks

harness_check_log_gate "LimboAISoldierAIPilotContract" "$log_file"
if ! grep -q "\[LimboAISoldierAIPilotContract\] ok" "$log_file"; then
	echo "[LimboAISoldierAIPilotContract] missing ok marker" >&2
	exit 1
fi
