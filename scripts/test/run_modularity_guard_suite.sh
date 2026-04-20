#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
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
  local scene_path="$1"
  echo "[ModularityGuardSuite] running $scene_path"
  HOME="$GODOT_TEST_HOME" "$GODOT_BIN" --headless --path . "$scene_path"
}

run_scene scenes/test/modularity_guard.tscn
run_scene scenes/test/scene_pool_contract.tscn
run_scene scenes/test/soldier_world_motion_contract.tscn

echo "[ModularityGuardSuite] complete"
