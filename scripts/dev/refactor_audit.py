#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
from collections import defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SCAN_ROOTS = [
    ROOT / "scripts",
]

TEXT_EXTENSIONS = {".gd", ".tscn", ".gdshader", ".md", ".sh"}
CODE_EXTENSIONS = {".gd", ".tscn", ".gdshader", ".sh"}

LEGACY_PATTERNS = {
    "String() constructor": re.compile(r"(?<![\w.])String\s*\("),
    "bool() constructor": re.compile(r"(?<![\w.])bool\s*\("),
    "yield()": re.compile(r"(?<![\w.])yield\s*\("),
    "funcref()": re.compile(r"(?<![\w.])funcref\s*\("),
    ".instance()": re.compile(r"\.instance\s*\("),
}

SMELL_PATTERNS = {
    "direct_get_calls": re.compile(r"\.get\s*\("),
    "has_method_calls": re.compile(r"\.has_method\s*\("),
    "find_child_calls": re.compile(r"\.find_child\s*\("),
    "scene_group_cache_refs": re.compile(r"\bSceneGroupCache\b"),
    "call_deferred_calls": re.compile(r"\.call_deferred\s*\("),
}


def iter_files(scan_roots: list[Path]) -> list[Path]:
    files: list[Path] = []
    for root in scan_roots:
        if not root.exists():
            continue
        for path in root.rglob("*"):
            if not path.is_file():
                continue
            if path.suffix.lower() not in TEXT_EXTENSIONS:
                continue
            files.append(path)
    return sorted(files)


def load_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return path.read_text(errors="ignore")


def count_functions(text: str) -> int:
    return sum(
        1
        for line in text.splitlines()
        if line.startswith("func ") or line.startswith("static func ")
    )


def count_matches(text: str, pattern: re.Pattern[str]) -> int:
    return len(pattern.findall(text))


def build_report(scan_roots: list[Path], giant_line_threshold: int, giant_func_threshold: int) -> dict:
    files = iter_files(scan_roots)

    legacy_hits: dict[str, list[dict]] = defaultdict(list)
    smell_hits: dict[str, list[dict]] = defaultdict(list)
    giant_files: list[dict] = []
    summary = {
        "files_scanned": len(files),
        "legacy_total": 0,
        "smell_total": 0,
        "giant_file_total": 0,
    }

    for path in files:
        text = load_text(path)
        rel = path.relative_to(ROOT).as_posix()
        line_count = text.count("\n") + (1 if text else 0)
        func_count = count_functions(text)

        if path.suffix == ".gd" and (line_count >= giant_line_threshold or func_count >= giant_func_threshold):
            giant_files.append(
                {
                    "path": rel,
                    "lines": line_count,
                    "functions": func_count,
                }
            )

        if path.suffix in CODE_EXTENSIONS:
            for label, pattern in LEGACY_PATTERNS.items():
                count = count_matches(text, pattern)
                if count:
                    legacy_hits[label].append({"path": rel, "count": count})
                    summary["legacy_total"] += count

            for label, pattern in SMELL_PATTERNS.items():
                count = count_matches(text, pattern)
                if count:
                    smell_hits[label].append({"path": rel, "count": count})
                    summary["smell_total"] += count

    giant_files.sort(key=lambda item: (-item["lines"], -item["functions"], item["path"]))
    summary["giant_file_total"] = len(giant_files)

    for bucket in (legacy_hits, smell_hits):
        for items in bucket.values():
            items.sort(key=lambda item: (-item["count"], item["path"]))

    return {
        "summary": summary,
        "giant_files": giant_files,
        "legacy_patterns": dict(legacy_hits),
        "smell_patterns": dict(smell_hits),
    }


def print_human_report(report: dict, top_n: int) -> None:
    summary = report["summary"]
    print("Refactor Audit")
    print("files_scanned=%d legacy_hits=%d smell_hits=%d giant_files=%d" % (
        summary["files_scanned"],
        summary["legacy_total"],
        summary["smell_total"],
        summary["giant_file_total"],
    ))

    print("\nGiant Files")
    if not report["giant_files"]:
        print("- none")
    else:
        for item in report["giant_files"][:top_n]:
            print("- %s lines=%d functions=%d" % (item["path"], item["lines"], item["functions"]))

    print("\nLegacy Patterns")
    if not report["legacy_patterns"]:
        print("- none")
    else:
        for label, items in sorted(report["legacy_patterns"].items()):
            print("- %s" % label)
            for item in items[:top_n]:
                print("  %s x%d" % (item["path"], item["count"]))

    print("\nRefactor Smells")
    if not report["smell_patterns"]:
        print("- none")
    else:
        for label, items in sorted(report["smell_patterns"].items()):
            print("- %s" % label)
            for item in items[:top_n]:
                print("  %s x%d" % (item["path"], item["count"]))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Audit the project for refactor candidates and legacy Godot patterns.")
    parser.add_argument(
        "--json",
        action="store_true",
        help="Print JSON instead of a human-readable report.",
    )
    parser.add_argument(
        "--top",
        type=int,
        default=12,
        help="How many top entries to print per section in text mode.",
    )
    parser.add_argument(
        "--giant-lines",
        type=int,
        default=500,
        help="Mark .gd files at or above this line count as giant files.",
    )
    parser.add_argument(
        "--giant-functions",
        type=int,
        default=40,
        help="Mark .gd files at or above this function count as giant files.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    report = build_report(DEFAULT_SCAN_ROOTS, args.giant_lines, args.giant_functions)
    if args.json:
        print(json.dumps(report, indent=2, ensure_ascii=False))
    else:
        print_human_report(report, args.top)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
