#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/harness_log_gate.sh"
duration="${1:-60}"
log_file="$(mktemp -t battleship_mid_boss_compare.XXXXXX.log)"

if [[ "$#" -gt 1 ]]; then
	support_limits=("${@:2}")
else
	support_limits=(0 1 2)
fi

cleanup() {
	rm -f "$log_file"
}
trap cleanup EXIT

for support_limit in "${support_limits[@]}"; do
	echo "[MidBossCompare] run duration=${duration} support_limit=${support_limit}" | tee -a "$log_file"
	"$script_dir/run_mid_boss_balance_preview.sh" "$duration" "$support_limit" 2>&1 | tee -a "$log_file"
done

harness_check_log_gate "MidBossCompare" "$log_file"

summary_count="$(grep -F "[MidBossBalance] summary" "$log_file" | wc -l | tr -d ' ')"
if [[ "$summary_count" -ne "${#support_limits[@]}" ]]; then
	echo "[MidBossCompare] expected ${#support_limits[@]} summaries, found ${summary_count}" >&2
	exit 1
fi

echo "[MidBossCompare] summaries"
grep -F "[MidBossBalance] summary" "$log_file"
