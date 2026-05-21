#!/usr/bin/env bash
set -euo pipefail

# Legacy wrapper kept for old local muscle memory and CI hooks. Prefer
# run_ai_ship_script_isolation.sh for new commands.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$script_dir/run_ai_ship_script_isolation.sh" "$@"
