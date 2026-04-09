#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/../.." && pwd)"
probe_scene="res://scenes/test/scene_load_probe.tscn"

declare -a targets=(
	"base_ship_script|res://scripts/entities/ships/base_ship.gd"
	"chaser_ship_script|res://scripts/entities/ships/chaser_ship.gd"
	"player_ship_script|res://scripts/entities/ships/player_ship.gd"
	"enemy_ship_scene|res://scenes/ships/enemy_ship.tscn"
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
	(
		cd "$project_root"
		env BATTLESHIP_PROBE_SCENE_PATH="$target" bash scripts/test/run_leak_probe.sh "$probe_scene"
	) >"$log_file" 2>&1
	cat "$log_file"
	local summary
	summary="$(grep -F "[LeakProbe] scene=" "$log_file" | tail -n 1 || true)"
	rm -f "$log_file"
	if [[ -z "$summary" ]]; then
		echo "[ShipLoadChainBreakdown] missing leak summary for $label" >&2
		exit 1
	fi
	local rid
	local resources
	rid="$(sed -E 's/.* rid_total=([0-9]+) resources=.*/\1/' <<<"$summary")"
	resources="$(sed -E 's/.* resources=([0-9]+) objectdb.*/\1/' <<<"$summary")"
	echo "[ShipLoadChainBreakdown] $label rid=$rid resources=$resources target=$target"
}

for target_entry in "${targets[@]}"; do
	IFS='|' read -r label target <<<"$target_entry"
	run_case "$label" "$target"
done
