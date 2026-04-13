#!/usr/bin/env bash

declare -a HARNESS_DEFAULT_BAD_PATTERNS=(
	"SCRIPT ERROR"
	"Script error"
	"Parse Error"
	"Invalid access"
	"Invalid call"
	"Nonexistent"
	"Cannot infer the type"
	"Attempt to call function"
	"Error calling"
	"call to function"
	"Lambda capture at index"
)

harness_check_log_gate() {
	local label="$1"
	local log_file="$2"
	shift 2

	local pattern
	for pattern in "${HARNESS_DEFAULT_BAD_PATTERNS[@]}" "$@"; do
		if grep -Fq "$pattern" "$log_file"; then
			echo "[$label] log gate failed: $pattern" >&2
			return 1
		fi
	done
}

harness_filter_known_exit_leaks() {
	awk '
		/RID allocations of type/ { next }
		/WARNING: ObjectDB instances leaked at exit/ { next }
		/resources still in use at exit/ { next }
		/Pages in use exist at exit in PagedAllocator/ { next }
		/^[[:space:]]+at: cleanup \(core\/object\/object\.cpp:/ { next }
		/^[[:space:]]+at: clear \(core\/io\/resource\.cpp:/ { next }
		/^[[:space:]]+at: ~PagedAllocator / { next }
		{ print }
	'
}

harness_print_filtered_log() {
	local log_file="$1"
	harness_filter_known_exit_leaks < "$log_file"
}

harness_read_leak_summary() {
	local label="$1"
	local log_file="$2"
	local case_label="${3:-}"
	local suffix=""
	if [[ -n "$case_label" ]]; then
		suffix=" for $case_label"
	fi

	HARNESS_LEAK_SUMMARY="$(grep -F "[LeakProbe] scene=" "$log_file" | tail -n 1 || true)"
	if [[ -z "$HARNESS_LEAK_SUMMARY" ]]; then
		echo "[$label] missing leak summary$suffix" >&2
		return 1
	fi
	HARNESS_LEAK_RID="$(sed -E 's/.* rid_total=([0-9]+) resources=.*/\1/' <<<"$HARNESS_LEAK_SUMMARY")"
	HARNESS_LEAK_RESOURCES="$(sed -E 's/.* resources=([0-9]+) objectdb.*/\1/' <<<"$HARNESS_LEAK_SUMMARY")"
}
