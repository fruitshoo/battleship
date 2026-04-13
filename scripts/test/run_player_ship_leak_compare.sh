#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/../.." && pwd)"
source "$script_dir/harness_log_gate.sh"
normal_log="$(mktemp -t battleship_player_ship_leak_normal.XXXXXX.log)"
disabled_log="$(mktemp -t battleship_player_ship_leak_disabled.XXXXXX.log)"
scene_path="res://scenes/ships/player_ship.tscn"

cleanup() {
	rm -f "$normal_log" "$disabled_log"
}
trap cleanup EXIT

normal_status=0
bash "$project_root/scripts/test/run_leak_probe.sh" "$scene_path" >"$normal_log" 2>&1 || normal_status=$?
cat "$normal_log"
if [[ "$normal_status" -ne 0 ]]; then
	echo "[SupportFleetLeakCompare] normal probe failed with status $normal_status" >&2
	exit "$normal_status"
fi

echo "[SupportFleetLeakCompare] --- autosummon disabled ---"

disabled_status=0
BATTLESHIP_DISABLE_SUPPORT_FLEET_AUTOSPAWN=1 \
bash "$project_root/scripts/test/run_leak_probe.sh" "$scene_path" >"$disabled_log" 2>&1 || disabled_status=$?
cat "$disabled_log"
if [[ "$disabled_status" -ne 0 ]]; then
	echo "[SupportFleetLeakCompare] autosummon disabled probe failed with status $disabled_status" >&2
	exit "$disabled_status"
fi

if ! harness_read_leak_summary "SupportFleetLeakCompare" "$normal_log" "normal"; then
	exit 1
fi
normal_rid="$HARNESS_LEAK_RID"
normal_resources="$HARNESS_LEAK_RESOURCES"
if ! harness_read_leak_summary "SupportFleetLeakCompare" "$disabled_log" "autosummon disabled"; then
	exit 1
fi
disabled_rid="$HARNESS_LEAK_RID"
disabled_resources="$HARNESS_LEAK_RESOURCES"

rid_delta=$((normal_rid - disabled_rid))
resource_delta=$((normal_resources - disabled_resources))

echo "[SupportFleetLeakCompare] normal rid=$normal_rid resources=$normal_resources"
echo "[SupportFleetLeakCompare] autosummon_off rid=$disabled_rid resources=$disabled_resources"
echo "[SupportFleetLeakCompare] delta rid=$rid_delta resources=$resource_delta"
