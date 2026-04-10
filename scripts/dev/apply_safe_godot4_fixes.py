#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SCAN_ROOT = ROOT / "scripts"


SAFE_FIX_PATTERNS = [
    (
        "String() -> str()",
        re.compile(r"(?<![\w.\"'])String\s*\("),
        "str(",
    ),
    (
        ".instance() -> .instantiate()",
        re.compile(r"\.instance\s*\("),
        ".instantiate(",
    ),
]


@dataclass
class FileFixResult:
    path: Path
    replacements: dict[str, int]


def iter_gd_files(root: Path) -> list[Path]:
    return sorted(path for path in root.rglob("*.gd") if path.is_file())


def split_code_segments(line: str) -> list[tuple[str, bool]]:
    segments: list[tuple[str, bool]] = []
    current: list[str] = []
    in_string = False
    string_delim = ""
    escape = False

    i = 0
    while i < len(line):
        ch = line[i]
        if in_string:
            current.append(ch)
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == string_delim:
                in_string = False
                segments.append(("".join(current), False))
                current = []
            i += 1
            continue

        if ch == "#":
            if current:
                segments.append(("".join(current), True))
                current = []
            segments.append((line[i:], False))
            return segments

        if ch in {"'", '"'}:
            if current:
                segments.append(("".join(current), True))
                current = []
            in_string = True
            string_delim = ch
            current.append(ch)
            i += 1
            continue

        current.append(ch)
        i += 1

    if current:
        segments.append(("".join(current), not in_string))
    return segments


def apply_safe_fixes_to_text(text: str) -> tuple[str, dict[str, int]]:
    replacement_counts = {label: 0 for label, _, _ in SAFE_FIX_PATTERNS}
    out_lines: list[str] = []

    for line in text.splitlines(keepends=True):
        rebuilt: list[str] = []
        for segment, is_code in split_code_segments(line):
            if not is_code:
                rebuilt.append(segment)
                continue
            updated = segment
            for label, pattern, replacement in SAFE_FIX_PATTERNS:
                updated, count = pattern.subn(replacement, updated)
                replacement_counts[label] += count
            rebuilt.append(updated)
        out_lines.append("".join(rebuilt))

    return "".join(out_lines), replacement_counts


def run(root: Path, write: bool) -> list[FileFixResult]:
    results: list[FileFixResult] = []
    for path in iter_gd_files(root):
        original = path.read_text(encoding="utf-8")
        updated, counts = apply_safe_fixes_to_text(original)
        total = sum(counts.values())
        if total == 0:
            continue
        if write:
            path.write_text(updated, encoding="utf-8")
        results.append(FileFixResult(path=path, replacements=counts))
    return results


def print_report(results: list[FileFixResult], write: bool) -> None:
    mode = "Applied" if write else "Dry Run"
    print(f"Safe Godot 4 Fixes ({mode})")
    if not results:
        print("- no changes")
        return
    for result in results:
        rel = result.path.relative_to(ROOT).as_posix()
        parts = [f"{label} x{count}" for label, count in result.replacements.items() if count]
        print(f"- {rel}: " + ", ".join(parts))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Apply a small set of safe Godot 4 codemods.")
    parser.add_argument(
        "--write",
        action="store_true",
        help="Write changes to disk. Defaults to dry-run output only.",
    )
    parser.add_argument(
        "--root",
        default=str(DEFAULT_SCAN_ROOT),
        help="Root directory to scan for .gd files.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = Path(args.root).resolve()
    results = run(root, write=args.write)
    print_report(results, write=args.write)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
