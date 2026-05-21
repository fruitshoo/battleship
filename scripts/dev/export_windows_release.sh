#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT_FILE="$ROOT_DIR/project.godot"
PRESET_NAME="${1:-Windows Desktop}"
GODOT_BIN="${GODOT_BIN:-godot}"

VERSION="$(
	awk -F= '
		/^\[application\]/ { in_app = 1; next }
		/^\[/ { in_app = 0 }
		in_app && /^config\/version=/ {
			gsub(/"/, "", $2)
			print $2
			exit
		}
	' "$PROJECT_FILE"
)"

if [[ -z "$VERSION" ]]; then
	echo "Could not read config/version from project.godot" >&2
	exit 1
fi

VERSION_TAG="v$VERSION"
OUT_DIR="$ROOT_DIR/exports/windows-$VERSION_TAG"
EXE_NAME="Battleship-$VERSION_TAG.exe"
ZIP_PATH="$ROOT_DIR/exports/Battleship-$VERSION_TAG-windows.zip"

mkdir -p "$OUT_DIR"

"$GODOT_BIN" --headless --path "$ROOT_DIR" --export-release "$PRESET_NAME" "$OUT_DIR/$EXE_NAME"

python3 - "$OUT_DIR" "$ZIP_PATH" <<'PY'
from pathlib import Path
import sys
import zipfile

out_dir = Path(sys.argv[1])
zip_path = Path(sys.argv[2])
zip_path.parent.mkdir(parents=True, exist_ok=True)

with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
    for path in sorted(out_dir.rglob("*")):
        if path.is_file():
            zf.write(path, path.relative_to(out_dir.parent))

print(zip_path)
PY

echo "Windows export complete: $ZIP_PATH"
