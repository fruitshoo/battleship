# Dev Scripts

## `refactor_audit.py`

Quick audit for refactor candidates and legacy Godot patterns.

Examples:

```bash
python3 scripts/dev/refactor_audit.py
python3 scripts/dev/refactor_audit.py --top 20
python3 scripts/dev/refactor_audit.py --json
```

The report currently highlights:

- giant `.gd` files by line count and function count
- legacy Godot 3 style patterns such as `yield()`, `funcref()`, `.instance()`, `String()`, and `bool()`
- refactor smells such as direct `.get()`, `.has_method()`, `.find_child()`, `SceneGroupCache`, and `.call_deferred()`

## `apply_safe_godot4_fixes.py`

Small codemod for the safest Godot 4 compatibility rewrites.

Examples:

```bash
python3 scripts/dev/apply_safe_godot4_fixes.py
python3 scripts/dev/apply_safe_godot4_fixes.py --write
```

Current safe rewrites:

- `String(...)` to `str(...)`
- `.instance(...)` to `.instantiate(...)`

The script avoids quoted strings and `#` comments, so it is meant for mechanical compatibility cleanup rather than structural refactors.
