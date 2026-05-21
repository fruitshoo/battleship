#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/../.." && pwd)"
source "$script_dir/harness_log_gate.sh"
probe_scene="res://scenes/test/scene_load_probe.tscn"

declare -a targets=(
	"isolation_base|res://scripts/test/ai_ship_isolation_base.gd"
	"isolation_helpers|res://scripts/test/ai_ship_isolation_helpers.gd"
	"isolation_combined|res://scripts/test/ai_ship_isolation_combined.gd"
	"isolation_runtime_methods|res://scripts/test/ai_ship_isolation_runtime_methods.gd"
	"isolation_process_loop|res://scripts/test/ai_ship_isolation_process_loop.gd"
	"isolation_ai_core|res://scripts/test/ai_ship_isolation_ai_core.gd"
	"isolation_process_ai|res://scripts/test/ai_ship_isolation_process_ai.gd"
	"isolation_legacy_capture|res://scripts/test/ai_ship_isolation_legacy_capture.gd"
	"isolation_boarding_collision|res://scripts/test/ai_ship_isolation_boarding_collision.gd"
	"isolation_late_combined|res://scripts/test/ai_ship_isolation_late_combined.gd"
	"ai_ship|res://scripts/entities/ships/ai_ship.gd"
	"chaser_ship_alias|res://scripts/entities/ships/chaser_ship.gd"
)

run_case() {
	local label="$1"
	local target="$2"
	local log_file
	log_file="$(mktemp -t "battleship_ai_ship_script_isolation_${label}.XXXXXX.log")"
	local probe_status=0
	(
		cd "$project_root"
		env BATTLESHIP_PROBE_SCENE_PATH="$target" bash scripts/test/run_leak_probe.sh "$probe_scene"
	) >"$log_file" 2>&1 || probe_status=$?
	cat "$log_file"
	if [[ "$probe_status" -ne 0 ]]; then
		rm -f "$log_file"
		echo "[AIShipScriptIsolation] probe failed for $label with status $probe_status" >&2
		exit "$probe_status"
	fi
	if ! harness_read_leak_summary "AIShipScriptIsolation" "$log_file" "$label"; then
		rm -f "$log_file"
		exit 1
	fi
	rm -f "$log_file"
	echo "[AIShipScriptIsolation] $label rid=$HARNESS_LEAK_RID resources=$HARNESS_LEAK_RESOURCES target=$target"
}

for target_entry in "${targets[@]}"; do
	IFS='|' read -r label target <<<"$target_entry"
	run_case "$label" "$target"
done
