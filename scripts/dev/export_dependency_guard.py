#!/usr/bin/env python3
"""Fail when export exclude filters hide files still referenced by runtime assets."""

from __future__ import annotations

import argparse
import json
import fnmatch
import os
from pathlib import Path
import struct
import sys


DEFAULT_PRESETS = ("Windows Desktop",)
IGNORED_DIRS = {
    ".git",
    ".godot",
    "__pycache__",
    "docs",
    "exports",
}
REFERENCE_SUFFIXES = {
    ".cfg",
    ".gd",
    ".gdextension",
    ".gdshader",
    ".glb",
    ".gltf",
    ".godot",
    ".import",
    ".json",
    ".material",
    ".res",
    ".scn",
    ".tscn",
    ".tres",
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--project-root",
        default=".",
        help="Godot project root. Defaults to the current directory.",
    )
    parser.add_argument(
        "--preset",
        action="append",
        help="Preset name to check. May be passed more than once. Defaults to Windows Desktop.",
    )
    parser.add_argument(
        "--extra-exclude",
        action="append",
        default=[],
        help="Additional exclude pattern to check. Useful for testing proposed filters.",
    )
    args = parser.parse_args()

    project_root = Path(args.project_root).resolve()
    preset_names = tuple(args.preset or DEFAULT_PRESETS)
    preset_filters = _read_export_exclude_filters(project_root / "export_presets.cfg", preset_names)
    if args.extra_exclude:
        for preset_name in preset_names:
            preset_filters.setdefault(preset_name, []).extend(args.extra_exclude)

    failures: list[tuple[str, str, str, list[str]]] = []
    for preset_name, patterns in preset_filters.items():
        for path, pattern in _iter_excluded_files(project_root, patterns):
            references = _find_references(project_root, path)
            if references:
                failures.append((preset_name, path, pattern, references))

    if failures:
        print("[ExportDependencyGuard] excluded files are still referenced:", file=sys.stderr)
        for preset_name, path, pattern, references in failures:
            print(f"- preset={preset_name} pattern={pattern} file={path}", file=sys.stderr)
            for ref in references[:8]:
                print(f"  referenced by {ref}", file=sys.stderr)
            if len(references) > 8:
                print(f"  ... and {len(references) - 8} more", file=sys.stderr)
        return 1

    checked = sum(len(patterns) for patterns in preset_filters.values())
    print(f"[ExportDependencyGuard] ok presets={','.join(preset_filters.keys())} patterns={checked}")
    return 0


def _read_export_exclude_filters(path: Path, preset_names: tuple[str, ...]) -> dict[str, list[str]]:
    if not path.exists():
        raise FileNotFoundError(path)

    presets: dict[str, dict[str, str]] = {}
    current_id = ""
    in_preset_header = False
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith(";"):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1]
            in_preset_header = section.startswith("preset.") and ".options" not in section
            current_id = section if in_preset_header else ""
            if in_preset_header:
                presets.setdefault(current_id, {})
            continue
        if not in_preset_header or "=" not in line:
            continue
        key, value = line.split("=", 1)
        presets[current_id][key.strip()] = _unquote(value.strip())

    filters_by_name: dict[str, list[str]] = {}
    missing = set(preset_names)
    for values in presets.values():
        name = values.get("name", "")
        if name not in preset_names:
            continue
        missing.discard(name)
        filters_by_name[name] = _split_filter_patterns(values.get("exclude_filter", ""))

    if missing:
        raise ValueError("export preset not found: %s" % ", ".join(sorted(missing)))
    return filters_by_name


def _unquote(value: str) -> str:
    if len(value) >= 2 and value[0] == '"' and value[-1] == '"':
        return value[1:-1]
    return value


def _split_filter_patterns(value: str) -> list[str]:
    return [part.strip() for part in value.split(",") if part.strip()]


def _iter_excluded_files(project_root: Path, patterns: list[str]):
    for file_path in _iter_project_files(project_root):
        rel_path = _to_posix(file_path.relative_to(project_root))
        for pattern in patterns:
            if fnmatch.fnmatchcase(rel_path, pattern):
                yield rel_path, pattern
                break


def _find_references(project_root: Path, excluded_rel_path: str) -> list[str]:
    needle = ("res://" + excluded_rel_path).encode("utf-8")
    ignored_import = excluded_rel_path + ".import"
    references: list[str] = []
    for file_path in _iter_project_files(project_root):
        rel_path = _to_posix(file_path.relative_to(project_root))
        if rel_path == excluded_rel_path or rel_path == ignored_import:
            continue
        if not _can_hold_resource_reference(file_path):
            continue
        try:
            payload = file_path.read_bytes()
        except OSError:
            continue
        if needle in payload:
            references.append(rel_path)
    references.extend(_find_model_sidecar_references(project_root, excluded_rel_path, references))
    return references


def _find_model_sidecar_references(
    project_root: Path,
    excluded_rel_path: str,
    existing_references: list[str],
) -> list[str]:
    excluded_path = project_root / excluded_rel_path
    if excluded_path.suffix.lower() not in {".png", ".jpg", ".jpeg", ".webp"}:
        return []

    references: list[str] = []
    seen = set(existing_references)
    for model_path in excluded_path.parent.glob("*"):
        if model_path.suffix.lower() not in {".glb", ".gltf"}:
            continue
        rel_model_path = _to_posix(model_path.relative_to(project_root))
        if rel_model_path in seen:
            continue
        if excluded_path.name in _get_model_sidecar_image_names(model_path):
            references.append(rel_model_path)
            seen.add(rel_model_path)
    return references


def _get_model_sidecar_image_names(model_path: Path) -> set[str]:
    document = _read_gltf_document(model_path)
    if not isinstance(document, dict):
        return set()
    names: set[str] = set()
    model_stem = model_path.stem
    for image in document.get("images", []):
        if not isinstance(image, dict):
            continue
        uri = str(image.get("uri", "")).strip()
        if uri and not uri.startswith("data:"):
            names.add(Path(uri).name)
            continue
        image_name = str(image.get("name", "")).strip()
        extension = _image_extension(str(image.get("mimeType", "")).strip())
        if image_name and extension:
            names.add(f"{model_stem}_{image_name}{extension}")
    return names


def _read_gltf_document(model_path: Path):
    try:
        payload = model_path.read_bytes()
    except OSError:
        return None

    if model_path.suffix.lower() == ".gltf":
        try:
            return json.loads(payload.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            return None

    if len(payload) < 20 or payload[:4] != b"glTF":
        return None
    chunk_length, chunk_type = struct.unpack_from("<II", payload, 12)
    if chunk_type != 0x4E4F534A:
        return None
    chunk_end = 20 + chunk_length
    if chunk_end > len(payload):
        return None
    try:
        return json.loads(payload[20:chunk_end].decode("utf-8").rstrip(" \x00"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return None


def _image_extension(mime_type: str) -> str:
    if mime_type == "image/png":
        return ".png"
    if mime_type == "image/jpeg":
        return ".jpg"
    if mime_type == "image/webp":
        return ".webp"
    return ""


def _iter_project_files(project_root: Path):
    for root, dirs, files in os.walk(project_root):
        dirs[:] = [name for name in dirs if name not in IGNORED_DIRS]
        root_path = Path(root)
        for file_name in files:
            yield root_path / file_name


def _can_hold_resource_reference(path: Path) -> bool:
    if path.name in {"project.godot", "export_presets.cfg"}:
        return True
    return path.suffix in REFERENCE_SUFFIXES


def _to_posix(path: Path) -> str:
    return path.as_posix()


if __name__ == "__main__":
    raise SystemExit(main())
