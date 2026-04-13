#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/../.." && pwd)"
source "$script_dir/harness_log_gate.sh"
godot_bin="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
log_file="$(mktemp -t battleship_startup_hitch_probe.XXXXXX.log)"

cleanup() {
	rm -f "$log_file"
}
trap cleanup EXIT

BATTLESHIP_DISABLE_RUNTIME_REWARDS="${BATTLESHIP_DISABLE_RUNTIME_REWARDS:-0}" \
BATTLESHIP_DISABLE_SUPPORT_FLEET_AUTOSPAWN="${BATTLESHIP_DISABLE_SUPPORT_FLEET_AUTOSPAWN:-0}" \
HOME=/tmp "$godot_bin" \
	--headless \
	--path "$project_root" \
	res://scenes/test/startup_hitch_probe.tscn >"$log_file" 2>&1

cat "$log_file"

harness_check_log_gate "StartupHitch" "$log_file"

if ! grep -Fq "[StartupHitch] summary" "$log_file"; then
	echo "[StartupHitch] missing summary" >&2
	exit 1
fi
