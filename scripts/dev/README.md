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
