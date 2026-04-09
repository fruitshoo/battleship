#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/../.." && pwd)"
normal_log="$(mktemp -t battleship_player_ship_leak_normal.XXXXXX.log)"
disabled_log="$(mktemp -t battleship_player_ship_leak_disabled.XXXXXX.log)"
scene_path="res://scenes/ships/player_ship.tscn"

cleanup() {
	rm -f "$normal_log" "$disabled_log"
}
trap cleanup EXIT

bash "$project_root/scripts/test/run_leak_probe.sh" "$scene_path" >"$normal_log" 2>&1
cat "$normal_log"

echo "[SupportFleetLeakCompare] --- autosummon disabled ---"

BATTLESHIP_DISABLE_SUPPORT_FLEET_AUTOSPAWN=1 \
bash "$project_root/scripts/test/run_leak_probe.sh" "$scene_path" >"$disabled_log" 2>&1
cat "$disabled_log"

normal_summary="$(grep -F "[LeakProbe] scene=" "$normal_log" | tail -n 1 || true)"
disabled_summary="$(grep -F "[LeakProbe] scene=" "$disabled_log" | tail -n 1 || true)"

if [[ -z "$normal_summary" || -z "$disabled_summary" ]]; then
	echo "[SupportFleetLeakCompare] missing leak summaries" >&2
	exit 1
fi

normal_rid="$(sed -E 's/.* rid_total=([0-9]+) resources=.*/\1/' <<<"$normal_summary")"
normal_resources="$(sed -E 's/.* resources=([0-9]+) objectdb.*/\1/' <<<"$normal_summary")"
disabled_rid="$(sed -E 's/.* rid_total=([0-9]+) resources=.*/\1/' <<<"$disabled_summary")"
disabled_resources="$(sed -E 's/.* resources=([0-9]+) objectdb.*/\1/' <<<"$disabled_summary")"

rid_delta=$((normal_rid - disabled_rid))
resource_delta=$((normal_resources - disabled_resources))

echo "[SupportFleetLeakCompare] normal rid=$normal_rid resources=$normal_resources"
echo "[SupportFleetLeakCompare] autosummon_off rid=$disabled_rid resources=$disabled_resources"
echo "[SupportFleetLeakCompare] delta rid=$rid_delta resources=$resource_delta"
