# Dev Scripts

## `refactor_audit.py`

Quick audit for refactor candidates and legacy Godot patterns.

Examples:

```bash
python3 scripts/dev/refactor_audit.py
python3 scripts/dev/refactor_audit.py --top 20
python3 scripts/dev/refactor_audit.py --json
python3 scripts/dev/refactor_audit.py --fail-on-legacy
```

The report currently highlights:

- giant `.gd` files by line count and function count
- legacy Godot 3 style patterns such as `yield()`, `funcref()`, `.instance()`, `String()`, and `bool()`
- refactor smells such as direct `.get()`, `.has_method()`, `.find_child()`, `SceneGroupCache`, and `.call_deferred()`

Optional gates:

- `--fail-on-legacy`
- `--max-giant-files N`
- `--max-smell-total N`

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

## `run_refactor_tooling.sh`

Convenience wrapper that runs the audit first and then the safe codemod.

Examples:

```bash
bash scripts/dev/run_refactor_tooling.sh
bash scripts/dev/run_refactor_tooling.sh --write
bash scripts/dev/run_refactor_tooling.sh --write --contract-sweep
bash scripts/dev/run_refactor_tooling.sh --strict
```

Use `--write` only for the safe codemod step.
Use `--contract-sweep` when you want the wrapper to finish by running the project contract harness.
Use `--strict` when you want the audit step to fail on any legacy-pattern hits.

## `soldier_balance_report.py`

Quick balance report for current soldier health, damage, defense, and rough TTK bands.

Examples:

```bash
python3 scripts/dev/soldier_balance_report.py
python3 scripts/dev/soldier_balance_report.py --meta-crew-health 3 --meta-crew-attack 2 --meta-crew-defense 2
python3 scripts/dev/soldier_balance_report.py --run-crew-attack 5 --run-crew-defense 5
```

The report mirrors the code-facing formulas and highlights when intended weapon stats and effective runtime stats can diverge.
