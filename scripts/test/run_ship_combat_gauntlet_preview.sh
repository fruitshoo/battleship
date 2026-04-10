#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/../.." && pwd)"
godot_bin="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
log_file="$(mktemp -t battleship_ship_gauntlet.XXXXXX.log)"
preset="${1:-}"
recovery_mode="${2:-}"

cleanup() {
	rm -f "$log_file"
}
trap cleanup EXIT

HOME=/tmp \
BATTLESHIP_SHIP_GAUNTLET_AUTO_QUIT=1 \
BATTLESHIP_GAUNTLET_UPGRADE_PRESET="$preset" \
BATTLESHIP_GAUNTLET_DISABLE_RECOVERY="$([[ "$recovery_mode" == "no_recovery" ]] && echo 1 || echo 0)" \
BATTLESHIP_DISABLE_SUPPORT_FLEET_AUTOSPAWN=1 \
BATTLESHIP_SKIP_STARTUP_PREWARM=1 \
BATTLESHIP_DISABLE_RUNTIME_REWARDS=1 \
BATTLESHIP_DISABLE_AUTOSAVE=1 \
"$godot_bin" \
	--headless \
	--path "$project_root" \
	res://scenes/test/ship_combat_gauntlet_preview.tscn 2>&1 | tee "$log_file"

bad_patterns=(
	"Parse Error"
	"Invalid call"
	"Nonexistent"
	"Cannot infer the type"
	"Attempt to call function"
	"Script error"
	"Error calling"
	"call to function"
	"Lambda capture at index"
)

for pattern in "${bad_patterns[@]}"; do
	if grep -Fq "$pattern" "$log_file"; then
		echo "[ShipGauntlet] log gate failed: $pattern" >&2
		exit 1
	fi
done

if ! grep -Fq "[ShipGauntlet] summary" "$log_file"; then
	echo "[ShipGauntlet] missing summary output" >&2
	exit 1
fi
