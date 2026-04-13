#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/../.." && pwd)"
source "$script_dir/harness_log_gate.sh"
scene_path="res://scenes/test/player_ship_component_probe.tscn"

run_case() {
	local label="$1"
	shift
	local log_file
	log_file="$(mktemp -t "battleship_player_ship_bootstrap_${label}.XXXXXX.log")"
	local probe_status=0
	(
		cd "$project_root"
		env "$@" bash scripts/test/run_leak_probe.sh "$scene_path"
	) >"$log_file" 2>&1 || probe_status=$?
	cat "$log_file" >&2
	if [[ "$probe_status" -ne 0 ]]; then
		rm -f "$log_file"
		echo "[PlayerShipBootstrapBreakdown] probe failed for $label with status $probe_status" >&2
		exit "$probe_status"
	fi
	if ! harness_read_leak_summary "PlayerShipBootstrapBreakdown" "$log_file" "$label"; then
		rm -f "$log_file"
		exit 1
	fi
	rm -f "$log_file"
	echo "[PlayerShipBootstrapBreakdown] $label rid=$HARNESS_LEAK_RID resources=$HARNESS_LEAK_RESOURCES"
}

baseline_output="$(run_case baseline)"
echo "$baseline_output"
baseline_summary="$(grep -F "[PlayerShipBootstrapBreakdown] baseline " <<<"$baseline_output" | tail -n 1 || true)"
baseline_rid="$(sed -E 's/.* rid=([0-9]+) resources=.*/\1/' <<<"$baseline_summary")"
baseline_resources="$(sed -E 's/.* resources=([0-9]+).*/\1/' <<<"$baseline_summary")"

declare -a cases=(
	"no_upgrade_bootstrap BATTLESHIP_SKIP_PLAYER_UPGRADE_BOOTSTRAP=1"
	"no_crew_sync BATTLESHIP_SKIP_PLAYER_CREW_SYNC=1"
	"no_support BATTLESHIP_DISABLE_SUPPORT_FLEET_AUTOSPAWN=1"
	"bootstrap_min BATTLESHIP_SKIP_PLAYER_UPGRADE_BOOTSTRAP=1 BATTLESHIP_SKIP_PLAYER_CREW_SYNC=1 BATTLESHIP_DISABLE_SUPPORT_FLEET_AUTOSPAWN=1"
)

for case_entry in "${cases[@]}"; do
	IFS=' ' read -r -a parts <<<"$case_entry"
	label="${parts[0]}"
	unset 'parts[0]'
	case_output="$(run_case "$label" "${parts[@]}")"
	echo "$case_output"
	case_summary="$(grep -F "[PlayerShipBootstrapBreakdown] $label " <<<"$case_output" | tail -n 1 || true)"
	case_rid="$(sed -E 's/.* rid=([0-9]+) resources=.*/\1/' <<<"$case_summary")"
	case_resources="$(sed -E 's/.* resources=([0-9]+).*/\1/' <<<"$case_summary")"
	echo "[PlayerShipBootstrapBreakdown] delta $label rid=$((baseline_rid - case_rid)) resources=$((baseline_resources - case_resources))"
done
