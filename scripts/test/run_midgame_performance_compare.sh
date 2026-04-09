#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/../.." && pwd)"
godot_bin="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
log_file="$(mktemp -t battleship_midgame_compare.XXXXXX.log)"
timeout_seconds="${MIDGAME_COMPARE_TIMEOUT:-25}"
max_delta_avg_ms="${MIDGAME_MAX_DELTA_AVG_MS:-1.00}"
max_delta_p95_ms="${MIDGAME_MAX_DELTA_P95_MS:-3.00}"

cleanup() {
	rm -f "$log_file"
}
trap cleanup EXIT

HOME=/tmp \
BATTLESHIP_MIDGAME_AUTO_QUIT=1 \
"$godot_bin" \
	--headless \
	--path "$project_root" \
	res://scenes/test/midgame_fleet_battle_preview.tscn >"$log_file" 2>&1 &
godot_pid=$!

(
	sleep "$timeout_seconds"
	if kill -0 "$godot_pid" 2>/dev/null; then
		echo "[MidgameCompare] timed out after ${timeout_seconds}s" >>"$log_file"
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

cat "$log_file"

if [[ "$godot_status" -ne 0 ]]; then
	echo "[MidgameCompare] Godot exited with status $godot_status" >&2
	exit "$godot_status"
fi

bad_patterns=(
	"Parse Error"
	"Invalid call"
	"Nonexistent"
	"Cannot infer the type"
	"Attempt to call function"
	"Script error"
	"Error calling"
	"call to function"
	"[MidgameCompare] timed out"
)

for pattern in "${bad_patterns[@]}"; do
	if grep -Fq "$pattern" "$log_file"; then
		echo "[MidgameCompare] log gate failed: $pattern" >&2
		exit 1
	fi
done

baseline_line="$(grep -F "[MidgameBattle] compare baseline" "$log_file" | tail -n 1 || true)"
overlay_line="$(grep -F "[MidgameBattle] compare overlay" "$log_file" | tail -n 1 || true)"
delta_line="$(grep -F "[MidgameBattle] compare delta" "$log_file" | tail -n 1 || true)"

if [[ -z "$baseline_line" || -z "$overlay_line" || -z "$delta_line" ]]; then
	echo "[MidgameCompare] missing compare summary lines" >&2
	exit 1
fi

delta_avg_ms="$(sed -E 's/.*delta avg=([-0-9.]+)ms p95=.*/\1/' <<<"$delta_line")"
delta_p95_ms="$(sed -E 's/.* p95=([-0-9.]+)ms.*/\1/' <<<"$delta_line")"

if ! awk -v value="$delta_avg_ms" -v max="$max_delta_avg_ms" 'BEGIN { exit !(value <= max) }'; then
	echo "[MidgameCompare] avg delta ${delta_avg_ms}ms exceeded ${max_delta_avg_ms}ms" >&2
	exit 1
fi

if ! awk -v value="$delta_p95_ms" -v max="$max_delta_p95_ms" 'BEGIN { exit !(value <= max) }'; then
	echo "[MidgameCompare] p95 delta ${delta_p95_ms}ms exceeded ${max_delta_p95_ms}ms" >&2
	exit 1
fi

echo "[MidgameCompare] baseline ok: $baseline_line"
echo "[MidgameCompare] overlay ok: $overlay_line"
echo "[MidgameCompare] delta ok: avg=${delta_avg_ms}ms p95=${delta_p95_ms}ms"
