#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/harness_log_gate.sh"
GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
GODOT_TEST_HOME="${GODOT_TEST_HOME:-/tmp}"

if [[ ! -x "$GODOT_BIN" ]]; then
  echo "[ModularityGuardSuite] Godot binary not found or not executable: $GODOT_BIN" >&2
  echo "[ModularityGuardSuite] Set GODOT_BIN=/path/to/Godot to override." >&2
  exit 2
fi

cd "$ROOT_DIR"

echo "[ModularityGuardSuite] repo: $ROOT_DIR"

if command -v jq >/dev/null 2>&1; then
  echo "[ModularityGuardSuite] validating JSON registries"
  jq empty scripts/test/module_boundaries.json scenes/test/runtime_scenario_matrix.json
else
  echo "[ModularityGuardSuite] jq not found; skipping JSON syntax validation"
fi

run_scene() {
  local label="$1"
  local scene_path="$2"
  local success_marker="$3"
  local log_file
  log_file="$(mktemp -t "battleship_${label}.XXXXXX.log")"
  echo "[ModularityGuardSuite] running $scene_path"
  HOME="$GODOT_TEST_HOME" "$GODOT_BIN" \
    --headless \
    --path "$ROOT_DIR" \
    "$scene_path" 2>&1 | tee "$log_file" | harness_filter_known_exit_leaks
  if ! grep -Fq "$success_marker" "$log_file"; then
    rm -f "$log_file"
    echo "[ModularityGuardSuite] missing success marker for $label: $success_marker" >&2
    exit 1
  fi
  harness_check_log_gate "ModularityGuardSuite:$label" "$log_file"
  rm -f "$log_file"
}

run_scene "modularity_guard" "res://scenes/test/modularity_guard.tscn" "[ModularityGuard] ok"
run_scene "scene_pool_contract" "res://scenes/test/scene_pool_contract.tscn" "[ScenePoolContract] ok"
run_scene "soldier_world_motion_contract" "res://scenes/test/soldier_world_motion_contract.tscn" "[SoldierWorldMotionContract] ok"

echo "[ModularityGuardSuite] complete"
