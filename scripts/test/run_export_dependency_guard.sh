#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/../.." && pwd)"

python3 "$project_root/scripts/dev/export_dependency_guard.py" \
	--project-root "$project_root" \
	--preset "Windows Desktop"
