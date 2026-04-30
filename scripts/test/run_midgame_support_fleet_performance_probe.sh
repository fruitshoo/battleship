#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/../.." && pwd)"
source "$script_dir/harness_log_gate.sh"
godot_bin="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
duration="${1:-${MIDGAME_SUPPORT_PERF_DURATION:-600}}"
sample_interval="${2:-${MIDGAME_SUPPORT_PERF_SAMPLE_INTERVAL:-20}}"
warmup="${MIDGAME_SUPPORT_PERF_WARMUP:-5}"
support_limit="${MIDGAME_SUPPORT_PERF_SUPPORT_LIMIT:-5}"
formation="${MIDGAME_SUPPORT_PERF_FORMATION:-wing}"
wave_limit="${MIDGAME_SUPPORT_PERF_WAVE_LIMIT:-8}"
wave_interval="${MIDGAME_SUPPORT_PERF_WAVE_INTERVAL:-12}"
initial_wave_delay="${MIDGAME_SUPPORT_PERF_INITIAL_WAVE_DELAY:-0.75}"
player_speed="${MIDGAME_SUPPORT_PERF_PLAYER_SPEED:-3.2}"
expected_support="${MIDGAME_SUPPORT_PERF_EXPECT_SUPPORT:-$support_limit}"
expected_panokseon_total="${MIDGAME_SUPPORT_PERF_EXPECT_PANOKSEON_TOTAL:-2}"
expected_maengseon="${MIDGAME_SUPPORT_PERF_EXPECT_MAENGSEON:-4}"
duration_floor="${duration%.*}"
warmup_floor="${warmup%.*}"
timeout_seconds="${MIDGAME_SUPPORT_PERF_TIMEOUT:-$((duration_floor + warmup_floor + 90))}"
log_file="$(mktemp -t battleship_midgame_support_perf.XXXXXX.log)"

cleanup() {
	rm -f "$log_file"
}
trap cleanup EXIT

HOME=/tmp \
BATTLESHIP_MIDGAME_AUTO_QUIT=1 \
BATTLESHIP_MIDGAME_BATTLE_MODE=stress \
BATTLESHIP_MIDGAME_SUPPORT_PROBE=1 \
BATTLESHIP_MIDGAME_SUPPORT_PROBE_DURATION="$duration" \
BATTLESHIP_MIDGAME_SUPPORT_PROBE_WARMUP="$warmup" \
BATTLESHIP_MIDGAME_SUPPORT_PROBE_SAMPLE_INTERVAL="$sample_interval" \
BATTLESHIP_MIDGAME_SUPPORT_PROBE_SUPPORT_LIMIT="$support_limit" \
BATTLESHIP_MIDGAME_SUPPORT_PROBE_FORMATION="$formation" \
BATTLESHIP_MIDGAME_SUPPORT_PROBE_PLAYER_SPEED="$player_speed" \
BATTLESHIP_MIDGAME_WAVE_LIMIT="$wave_limit" \
BATTLESHIP_MIDGAME_WAVE_INTERVAL="$wave_interval" \
BATTLESHIP_MIDGAME_INITIAL_WAVE_DELAY="$initial_wave_delay" \
BATTLESHIP_MIDGAME_AUTO_OPEN_DEBUG_PANEL=0 \
BATTLESHIP_MIDGAME_OPEN_STAT_PANEL=0 \
BATTLESHIP_SKIP_STARTUP_PREWARM=1 \
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
		echo "[MidgameSupportPerf] timed out after ${timeout_seconds}s" >>"$log_file"
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
	echo "[MidgameSupportPerf] Godot exited with status $godot_status" >&2
	exit "$godot_status"
fi

harness_check_log_gate "MidgameSupportPerf" "$log_file" "[MidgameSupportPerf] timed out"

summary_line="$(grep -F "[MidgameSupportPerf] summary" "$log_file" | tail -n 1 || true)"
if [[ -z "$summary_line" ]]; then
	echo "[MidgameSupportPerf] missing support performance summary" >&2
	exit 1
fi

fps="$(sed -E 's/.* fps=([0-9.]+) avg=.*/\1/' <<<"$summary_line")"
avg_ms="$(sed -E 's/.* avg=([0-9.]+)ms p95=.*/\1/' <<<"$summary_line")"
p95_ms="$(sed -E 's/.* p95=([0-9.]+)ms p99=.*/\1/' <<<"$summary_line")"
support="$(sed -E 's/.* support=([0-9]+) panokseon_total=.*/\1/' <<<"$summary_line")"
panokseon_total="$(sed -E 's/.* panokseon_total=([0-9]+) maengseon=.*/\1/' <<<"$summary_line")"
maengseon="$(sed -E 's/.* maengseon=([0-9]+) soldiers=.*/\1/' <<<"$summary_line")"

if [[ "$support" -ne "$expected_support" ]]; then
	echo "[MidgameSupportPerf] support count $support != expected $expected_support" >&2
	exit 1
fi

if [[ "$panokseon_total" -ne "$expected_panokseon_total" ]]; then
	echo "[MidgameSupportPerf] panokseon total $panokseon_total != expected $expected_panokseon_total" >&2
	exit 1
fi

if [[ "$maengseon" -ne "$expected_maengseon" ]]; then
	echo "[MidgameSupportPerf] maengseon count $maengseon != expected $expected_maengseon" >&2
	exit 1
fi

if [[ -n "${MIDGAME_SUPPORT_PERF_MAX_AVG_MS:-}" ]]; then
	if ! awk -v value="$avg_ms" -v max="$MIDGAME_SUPPORT_PERF_MAX_AVG_MS" 'BEGIN { exit !(value <= max) }'; then
		echo "[MidgameSupportPerf] avg ${avg_ms}ms exceeded ${MIDGAME_SUPPORT_PERF_MAX_AVG_MS}ms" >&2
		exit 1
	fi
fi

if [[ -n "${MIDGAME_SUPPORT_PERF_MAX_P95_MS:-}" ]]; then
	if ! awk -v value="$p95_ms" -v max="$MIDGAME_SUPPORT_PERF_MAX_P95_MS" 'BEGIN { exit !(value <= max) }'; then
		echo "[MidgameSupportPerf] p95 ${p95_ms}ms exceeded ${MIDGAME_SUPPORT_PERF_MAX_P95_MS}ms" >&2
		exit 1
	fi
fi

echo "[MidgameSupportPerf] ok: fps=${fps} avg=${avg_ms}ms p95=${p95_ms}ms support=${support} panokseon_total=${panokseon_total} maengseon=${maengseon}"
