#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/../.." && pwd)"
source "$script_dir/harness_log_gate.sh"
probe_scene="res://scenes/test/scene_load_probe.tscn"

declare -a targets=(
	"base_ship_script|res://scripts/entities/ships/base_ship.gd"
	"chaser_ship_script|res://scripts/entities/ships/chaser_ship.gd"
	"player_ship_script|res://scripts/entities/ships/player_ship.gd"
	"enemy_base_ship_scene|res://scenes/ships/enemy_base_ship.tscn"
	"enemy_runtime_ship_scene|res://scenes/ships/enemy_ship.tscn"
	"player_ship_scene|res://scenes/ships/player_ship.tscn"
	"chaser_support_helper|res://scripts/entities/ships/chaser_ship_support_helper.gd"
	"cannon_enemy_light_scene|res://scenes/entities/launchers/cannon_enemy_light.tscn"
	"sekibune_hull_scene|res://scenes/ships/hulls/sekibune_hull.tscn"
)

run_case() {
	local label="$1"
	local target="$2"
	local log_file
	log_file="$(mktemp -t "battleship_ship_load_chain_${label}.XXXXXX.log")"
	local probe_status=0
	(
		cd "$project_root"
		env BATTLESHIP_PROBE_SCENE_PATH="$target" bash scripts/test/run_leak_probe.sh "$probe_scene"
	) >"$log_file" 2>&1 || probe_status=$?
	cat "$log_file"
	if [[ "$probe_status" -ne 0 ]]; then
		rm -f "$log_file"
		echo "[ShipLoadChainBreakdown] probe failed for $label with status $probe_status" >&2
		exit "$probe_status"
	fi
	if ! harness_read_leak_summary "ShipLoadChainBreakdown" "$log_file" "$label"; then
		rm -f "$log_file"
		exit 1
	fi
	rm -f "$log_file"
	echo "[ShipLoadChainBreakdown] $label rid=$HARNESS_LEAK_RID resources=$HARNESS_LEAK_RESOURCES target=$target"
}

for target_entry in "${targets[@]}"; do
	IFS='|' read -r label target <<<"$target_entry"
	run_case "$label" "$target"
done
