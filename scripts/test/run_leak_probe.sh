#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/../.." && pwd)"
source "$script_dir/harness_log_gate.sh"
godot_bin="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
scene_path="${1:-${LEAK_PROBE_SCENE:-res://scenes/main.tscn}}"
max_rid_total="${LEAK_MAX_RID_TOTAL:-140}"
max_resources="${LEAK_MAX_RESOURCES:-180}"
max_objectdb_warnings="${LEAK_MAX_OBJECTDB_WARNINGS:-1}"
max_paged_allocator_warnings="${LEAK_MAX_PAGED_ALLOCATOR_WARNINGS:-1}"
log_file="$(mktemp -t battleship_leak_probe.XXXXXX.log)"
godot_args=(
	--headless
	--path "$project_root"
	"$scene_path"
)
if [[ "${LEAK_PROBE_WAIT_FOR_SCENE_QUIT:-0}" != "1" ]]; then
	godot_args+=(--quit)
fi

cleanup() {
	rm -f "$log_file"
}
trap cleanup EXIT

HOME=/tmp "$godot_bin" "${godot_args[@]}" >"$log_file" 2>&1

if [[ "${LEAK_PROBE_VERBOSE:-0}" == "1" ]]; then
	cat "$log_file"
else
	harness_print_filtered_log "$log_file"
fi

harness_check_log_gate "LeakProbe" "$log_file"

rid_total="$(awk '/RID allocations of type/ {sum += $2} END {print sum + 0}' "$log_file")"
resource_total="$(awk '/resources still in use at exit/ {value = $2} END {print value + 0}' "$log_file")"
objectdb_warning_count="$(grep -Fc "WARNING: ObjectDB instances leaked at exit" "$log_file" || true)"
paged_allocator_warning_count="$(grep -Fc "Pages in use exist at exit in PagedAllocator" "$log_file" || true)"

echo "[LeakProbe] scene=$scene_path rid_total=$rid_total resources=$resource_total objectdb_warnings=$objectdb_warning_count paged_allocator_warnings=$paged_allocator_warning_count"

if grep -Fq "RID allocations of type" "$log_file" && { [[ "${LEAK_PROBE_VERBOSE:-0}" == "1" ]] || (( rid_total > max_rid_total )); }; then
	echo "[LeakProbe] rid breakdown:"
	grep -F "RID allocations of type" "$log_file"
fi

if (( rid_total > max_rid_total )); then
	echo "[LeakProbe] rid_total $rid_total exceeded $max_rid_total" >&2
	exit 1
fi

if (( resource_total > max_resources )); then
	echo "[LeakProbe] resources $resource_total exceeded $max_resources" >&2
	exit 1
fi

if (( objectdb_warning_count > max_objectdb_warnings )); then
	echo "[LeakProbe] objectdb warnings $objectdb_warning_count exceeded $max_objectdb_warnings" >&2
	exit 1
fi

if (( paged_allocator_warning_count > max_paged_allocator_warnings )); then
	echo "[LeakProbe] paged allocator warnings $paged_allocator_warning_count exceeded $max_paged_allocator_warnings" >&2
	exit 1
fi

echo "[LeakProbe] thresholds ok"
