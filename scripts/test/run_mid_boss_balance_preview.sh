#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/../.." && pwd)"
source "$script_dir/harness_log_gate.sh"
godot_bin="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
duration="${1:-60}"
support_limit="${2:-1}"
log_file="$(mktemp -t battleship_mid_boss_balance.XXXXXX.log)"

cleanup() {
	rm -f "$log_file"
}
trap cleanup EXIT

HOME=/tmp BATTLESHIP_MID_BOSS_PREVIEW_AUTO_QUIT=1 BATTLESHIP_MID_BOSS_PREVIEW_DURATION="$duration" BATTLESHIP_MID_BOSS_SUPPORT_LIMIT="$support_limit" BATTLESHIP_DISABLE_SUPPORT_FLEET_AUTOSPAWN=1 BATTLESHIP_SKIP_STARTUP_PREWARM=1 BATTLESHIP_DISABLE_RUNTIME_REWARDS=1 BATTLESHIP_DISABLE_AUTOSAVE=1 "$godot_bin" \
	--headless \
	--path "$project_root" \
	res://scenes/test/mid_boss_balance_preview.tscn 2>&1 | tee "$log_file" | harness_filter_known_exit_leaks

harness_check_log_gate "MidBossBalance" "$log_file"

if ! grep -Fq "[MidBossBalance] summary" "$log_file"; then
	echo "[MidBossBalance] missing summary output" >&2
	exit 1
fi
