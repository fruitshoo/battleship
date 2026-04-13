#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/../.." && pwd)"
source "$script_dir/harness_log_gate.sh"
godot_bin="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
duration="${1:-300}"
cycle_seconds="${2:-60}"
log_file="$(mktemp -t battleship_midgame_runtime.XXXXXX.log)"
timeout_seconds="${MIDGAME_RUNTIME_TIMEOUT:-$((duration + cycle_seconds + 45))}"
max_orphan_nodes="${MIDGAME_RUNTIME_MAX_ORPHAN_NODES:-0}"
max_static_mb_delta="${MIDGAME_RUNTIME_MAX_STATIC_MB_DELTA:-35.0}"

cleanup() {
	rm -f "$log_file"
}
trap cleanup EXIT

HOME=/tmp \
BATTLESHIP_MIDGAME_AUTO_QUIT=1 \
BATTLESHIP_MIDGAME_BATTLE_MODE=stress \
BATTLESHIP_MIDGAME_RUNTIME_PROBE=1 \
BATTLESHIP_MIDGAME_RUNTIME_DURATION="$duration" \
BATTLESHIP_MIDGAME_RUNTIME_CYCLE_SECONDS="$cycle_seconds" \
BATTLESHIP_DISABLE_SUPPORT_FLEET_AUTOSPAWN=1 \
BATTLESHIP_DISABLE_RUNTIME_REWARDS=1 \
BATTLESHIP_DISABLE_AUTOSAVE=1 \
"$godot_bin" \
	--headless \
	--path "$project_root" \
	res://scenes/test/midgame_fleet_battle_preview.tscn >"$log_file" 2>&1 &
godot_pid=$!

(
	sleep "$timeout_seconds"
	if kill -0 "$godot_pid" 2>/dev/null; then
		echo "[MidgameRuntime] timed out after ${timeout_seconds}s" >>"$log_file"
		kill "$godot_pid" 2>/dev/null || true
	fi
) &
watcher_pid=$!

godot_status=0
if ! wait "$godot_pid"; then
	godot_status=$?
fi
kill "$watcher_pid" 2>/dev/null || true
wait "$watcher_pid" 2>/dev/null || true

harness_print_filtered_log "$log_file"

if [[ "$godot_status" -ne 0 ]]; then
	echo "[MidgameRuntime] Godot exited with status $godot_status" >&2
	exit "$godot_status"
fi

harness_check_log_gate "MidgameRuntime" "$log_file" "[MidgameRuntime] timed out"

summary_line="$(grep -F "[MidgameRuntime] summary" "$log_file" | tail -n 1 || true)"
if [[ -z "$summary_line" ]]; then
	echo "[MidgameRuntime] missing runtime summary" >&2
	exit 1
fi

orphan_nodes_end="$(sed -E 's/.* orphan_nodes_end=([0-9]+).*/\1/' <<<"$summary_line")"
static_mb_delta="$(sed -E 's/.* static_mb_delta=([-0-9.]+) static_mb_peak=.*/\1/' <<<"$summary_line")"

if ! awk -v value="$orphan_nodes_end" -v max="$max_orphan_nodes" 'BEGIN { exit !(value <= max) }'; then
	echo "[MidgameRuntime] orphan nodes ${orphan_nodes_end} exceeded ${max_orphan_nodes}" >&2
	exit 1
fi

if ! awk -v value="$static_mb_delta" -v max="$max_static_mb_delta" 'BEGIN { exit !(value <= max) }'; then
	echo "[MidgameRuntime] static memory delta ${static_mb_delta}MB exceeded ${max_static_mb_delta}MB" >&2
	exit 1
fi

echo "[MidgameRuntime] ok: static_mb_delta=${static_mb_delta} orphan_nodes=${orphan_nodes_end}"
