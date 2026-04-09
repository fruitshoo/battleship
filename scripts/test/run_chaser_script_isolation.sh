#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/../.." && pwd)"
probe_scene="res://scenes/test/scene_load_probe.tscn"

declare -a targets=(
	"isolation_base|res://scripts/test/chaser_isolation_base.gd"
	"isolation_helpers|res://scripts/test/chaser_isolation_helpers.gd"
	"isolation_combined|res://scripts/test/chaser_isolation_combined.gd"
	"isolation_runtime_methods|res://scripts/test/chaser_isolation_runtime_methods.gd"
	"chaser_ship|res://scripts/entities/ships/chaser_ship.gd"
)

run_case() {
	local label="$1"
	local target="$2"
	local log_file
	log_file="$(mktemp -t "battleship_chaser_script_isolation_${label}.XXXXXX.log")"
	(
		cd "$project_root"
		env BATTLESHIP_PROBE_SCENE_PATH="$target" bash scripts/test/run_leak_probe.sh "$probe_scene"
	) >"$log_file" 2>&1
	cat "$log_file"
	local summary
	summary="$(grep -F "[LeakProbe] scene=" "$log_file" | tail -n 1 || true)"
	rm -f "$log_file"
	if [[ -z "$summary" ]]; then
		echo "[ChaserScriptIsolation] missing leak summary for $label" >&2
		exit 1
	fi
	local rid
	local resources
	rid="$(sed -E 's/.* rid_total=([0-9]+) resources=.*/\1/' <<<"$summary")"
	resources="$(sed -E 's/.* resources=([0-9]+) objectdb.*/\1/' <<<"$summary")"
	echo "[ChaserScriptIsolation] $label rid=$rid resources=$resources target=$target"
}

for target_entry in "${targets[@]}"; do
	IFS='|' read -r label target <<<"$target_entry"
	run_case "$label" "$target"
done
