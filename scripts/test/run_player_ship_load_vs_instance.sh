#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/../.." && pwd)"
probe_scene="res://scenes/test/scene_load_probe.tscn"
target_scene="${1:-res://scenes/ships/player_ship.tscn}"

run_case() {
	local label="$1"
	shift
	local log_file
	log_file="$(mktemp -t "battleship_scene_load_probe_${label}.XXXXXX.log")"
	(
		cd "$project_root"
		env BATTLESHIP_PROBE_SCENE_PATH="$target_scene" "$@" bash scripts/test/run_leak_probe.sh "$probe_scene"
	) >"$log_file" 2>&1
	cat "$log_file"
	local summary
	summary="$(grep -F "[LeakProbe] scene=" "$log_file" | tail -n 1 || true)"
	rm -f "$log_file"
	if [[ -z "$summary" ]]; then
		echo "[SceneLoadVsInstance] missing leak summary for $label" >&2
		exit 1
	fi
	local rid
	local resources
	rid="$(sed -E 's/.* rid_total=([0-9]+) resources=.*/\1/' <<<"$summary")"
	resources="$(sed -E 's/.* resources=([0-9]+) objectdb.*/\1/' <<<"$summary")"
	echo "[SceneLoadVsInstance] $label rid=$rid resources=$resources"
}

load_output="$(run_case load_only)"
echo "$load_output"
instantiate_output="$(run_case instantiate BATTLESHIP_PROBE_INSTANTIATE=1)"
echo "$instantiate_output"

load_summary="$(grep -F "[SceneLoadVsInstance] load_only " <<<"$load_output" | tail -n 1 || true)"
instantiate_summary="$(grep -F "[SceneLoadVsInstance] instantiate " <<<"$instantiate_output" | tail -n 1 || true)"
load_rid="$(sed -E 's/.* rid=([0-9]+) resources=.*/\1/' <<<"$load_summary")"
load_resources="$(sed -E 's/.* resources=([0-9]+).*/\1/' <<<"$load_summary")"
instantiate_rid="$(sed -E 's/.* rid=([0-9]+) resources=.*/\1/' <<<"$instantiate_summary")"
instantiate_resources="$(sed -E 's/.* resources=([0-9]+).*/\1/' <<<"$instantiate_summary")"

echo "[SceneLoadVsInstance] delta instantiate rid=$((instantiate_rid - load_rid)) resources=$((instantiate_resources - load_resources))"
