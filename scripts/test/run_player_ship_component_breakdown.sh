#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/../.." && pwd)"
scene_path="res://scenes/test/player_ship_component_probe.tscn"

run_case() {
	local label="$1"
	shift
	local log_file
	log_file="$(mktemp -t "battleship_player_ship_component_${label}.XXXXXX.log")"
	(
		cd "$project_root"
		env "$@" bash scripts/test/run_leak_probe.sh "$scene_path"
	) >"$log_file" 2>&1
	cat "$log_file"
	local summary
	summary="$(grep -F "[LeakProbe] scene=" "$log_file" | tail -n 1 || true)"
	rm -f "$log_file"
	if [[ -z "$summary" ]]; then
		echo "[PlayerShipComponentBreakdown] missing leak summary for $label" >&2
		exit 1
	fi
	local rid
	local resources
	rid="$(sed -E 's/.* rid_total=([0-9]+) resources=.*/\1/' <<<"$summary")"
	resources="$(sed -E 's/.* resources=([0-9]+) objectdb.*/\1/' <<<"$summary")"
	echo "[PlayerShipComponentBreakdown] $label rid=$rid resources=$resources"
}

baseline_output="$(run_case baseline)"
echo "$baseline_output"
baseline_summary="$(grep -F "[PlayerShipComponentBreakdown] baseline " <<<"$baseline_output" | tail -n 1 || true)"
baseline_rid="$(sed -E 's/.* rid=([0-9]+) resources=.*/\1/' <<<"$baseline_summary")"
baseline_resources="$(sed -E 's/.* resources=([0-9]+).*/\1/' <<<"$baseline_summary")"

declare -a cases=(
	"no_support BATTLESHIP_DISABLE_SUPPORT_FLEET_AUTOSPAWN=1"
	"no_soldiers BATTLESHIP_PROBE_STRIP_SOLDIERS=1"
	"no_wake BATTLESHIP_PROBE_STRIP_WAKE=1"
	"no_hull BATTLESHIP_PROBE_STRIP_HULL=1"
	"stripped BATTLESHIP_DISABLE_SUPPORT_FLEET_AUTOSPAWN=1 BATTLESHIP_PROBE_STRIP_SOLDIERS=1 BATTLESHIP_PROBE_STRIP_WAKE=1 BATTLESHIP_PROBE_STRIP_HULL=1"
)

for case_entry in "${cases[@]}"; do
	IFS=' ' read -r -a parts <<<"$case_entry"
	label="${parts[0]}"
	unset 'parts[0]'
	case_output="$(run_case "$label" "${parts[@]}")"
	echo "$case_output"
	case_summary="$(grep -F "[PlayerShipComponentBreakdown] $label " <<<"$case_output" | tail -n 1 || true)"
	case_rid="$(sed -E 's/.* rid=([0-9]+) resources=.*/\1/' <<<"$case_summary")"
	case_resources="$(sed -E 's/.* resources=([0-9]+).*/\1/' <<<"$case_summary")"
	echo "[PlayerShipComponentBreakdown] delta $label rid=$((baseline_rid - case_rid)) resources=$((baseline_resources - case_resources))"
done
