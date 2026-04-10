#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

WRITE_MODE=0
RUN_CONTRACT_SWEEP=0

for arg in "$@"; do
  case "$arg" in
    --write)
      WRITE_MODE=1
      ;;
    --contract-sweep)
      RUN_CONTRACT_SWEEP=1
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      echo "Usage: scripts/dev/run_refactor_tooling.sh [--write] [--contract-sweep]" >&2
      exit 2
      ;;
  esac
done

echo "== Refactor Audit =="
python3 scripts/dev/refactor_audit.py --top 10

echo
echo "== Safe Godot 4 Fixes =="
if [[ "$WRITE_MODE" -eq 1 ]]; then
  python3 scripts/dev/apply_safe_godot4_fixes.py --write
else
  python3 scripts/dev/apply_safe_godot4_fixes.py
fi

if [[ "$RUN_CONTRACT_SWEEP" -eq 1 ]]; then
  echo
  echo "== Contract Sweep =="
  bash scripts/test/run_project_contract_sweep.sh
fi
