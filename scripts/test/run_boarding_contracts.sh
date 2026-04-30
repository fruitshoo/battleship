#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/../.." && pwd)"
source "$script_dir/harness_log_gate.sh"
probe_scene="res://scenes/test/scene_load_probe.tscn"

declare -a contract_targets=(
	"boarding_impact_contract|res://scenes/test/boarding_impact_contract.tscn|[BoardingImpactContract] ok|0.05|0"
	"ship_damage_contract|res://scenes/test/ship_damage_contract.tscn|[ShipDamageContract] ok|0.05|0"
	"boarding_navigation_contract|res://scenes/test/boarding_navigation_contract.tscn|[BoardingNavigationContract] ok|0.05|0"
	"boarding_chaos_contract|res://scenes/test/boarding_chaos_contract.tscn|[BoardingChaosContract] ok|0.05|0"
	"support_boarding_contract|res://scenes/test/support_boarding_contract.tscn|[SupportBoardingContract] ok|5.00|1"
	"auto_raid_recall_contract|res://scenes/test/auto_raid_recall_contract.tscn|[AutoRaidRecallContract] ok|0.05|0"
	"soldier_incapacitation_contract|res://scenes/test/soldier_incapacitation_contract.tscn|[SoldierIncapacitationContract] ok|0.05|0"
)

run_contract_case() {
	local label="$1"
	local target="$2"
	local success_marker="$3"
	local auto_quit_delay="${4:-0.05}"
	local wait_for_scene_quit="${5:-0}"
	local log_file
	log_file="$(mktemp -t "battleship_boarding_contract_${label}.XXXXXX.log")"
	local probe_status=0
	(
		cd "$project_root"
		BATTLESHIP_PROBE_INSTANTIATE=1 BATTLESHIP_PROBE_SCENE_PATH="$target" BATTLESHIP_PROBE_AUTO_QUIT_DELAY="$auto_quit_delay" LEAK_PROBE_WAIT_FOR_SCENE_QUIT="$wait_for_scene_quit" bash scripts/test/run_leak_probe.sh "$probe_scene"
	) >"$log_file" 2>&1 || probe_status=$?
	harness_print_filtered_log "$log_file"
	if [[ "$probe_status" -ne 0 ]]; then
		rm -f "$log_file"
		echo "[BoardingContracts] probe failed for $label with status $probe_status" >&2
		exit "$probe_status"
	fi
	if ! harness_read_leak_summary "BoardingContracts" "$log_file" "$label"; then
		rm -f "$log_file"
		exit 1
	fi
	if ! grep -Fq "$success_marker" "$log_file"; then
		rm -f "$log_file"
		echo "[BoardingContracts] contract did not report success for $label" >&2
		exit 1
	fi
	harness_check_log_gate "BoardingContracts" "$log_file"
	rm -f "$log_file"
	echo "[BoardingContracts] $label rid=$HARNESS_LEAK_RID resources=$HARNESS_LEAK_RESOURCES target=$target"
}

for target_entry in "${contract_targets[@]}"; do
	IFS='|' read -r label target success_marker auto_quit_delay wait_for_scene_quit <<<"$target_entry"
	run_contract_case "$label" "$target" "$success_marker" "$auto_quit_delay" "$wait_for_scene_quit"
done
