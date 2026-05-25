# Agent Work Rules

This file is the short, practical checklist for AI-assisted edits in this
repository. Prefer the linked project docs for domain-specific details.

## Collaboration

- If a request is ambiguous and would change files, delete files, commit, export,
  or otherwise be costly to undo, first restate the intended action and ask for
  confirmation.
- Safe read-only investigation can proceed without confirmation.
- Keep changes narrowly scoped to the user's current request.
- Do not rewrite unrelated systems while fixing a local issue.
- Do not touch user work-in-progress unless the user explicitly asks. Existing
  uncommitted or untracked files may belong to the user.

## Repository Hygiene

- Check `git status --short` before committing or when the worktree seems dirty.
- Stage only files that belong to the requested change.
- Never revert unrelated changes.
- Avoid committing generated caches, `.DS_Store`, `.godot/`, or temporary
  workspace files.
- Use `rg` for searches.
- Use `apply_patch` for manual file edits.

## Validation

- For most gameplay, UI, scene, data, and asset-wiring changes, run:

```bash
scripts/test/run_project_contract_sweep.sh
```

- If the change is in a narrower subsystem, also consider the relevant focused
  contract under `scripts/test/`.
- Before adding or widening `export_presets.cfg` exclude filters, run
  `scripts/test/run_export_dependency_guard.sh`.
- Godot headless on macOS may print a known CA certificate warning. Treat parser,
  load, contract, or harness failures as real until explained.

## Project Map

- `scenes/`: Godot scene files and node layout.
- `scripts/`: gameplay and UI logic.
- `resources/`: shared Godot resources such as materials, environments, curves,
  item resources, and reusable `.tres` assets.
- `assets/`: source media such as audio, models, textures, fonts, shaders, and
  VFX textures.
- `data/`: JSON balance and static rule data.

See `docs/PROJECT_STRUCTURE.md` before moving behavior across folders.

## Domain Docs

- Asset import, model format, naming, compatibility texture, and cleanup rules:
  `docs/asset_pipeline.md`
- Windows build and version rules: `docs/versioning.md`
- Ship and encounter authoring rules: `docs/ship_authoring.md`
- Ship AI flow and AI-specific validation: `docs/ship_ai_flow.md`
- Soldier and weapon balance targets: `docs/soldier_balance_targets.md`
- Audio replacement and licensing notes:
  `docs/audio_replacement_plan.md`
  `docs/audio_license_inventory.md`
- Texture audit notes: `docs/TEXTURE_AUDIT.md`

## Assets

- Do not delete compatibility textures just because text search looks clean;
  imported `glb` files may still rely on them.
- Prefer export exclusion over deletion for source-like or uncertain assets.
- Keep source/generated art out of shipping builds when it is not a runtime
  resource.
- New shared-atlas props should follow the `gltf separate` rules in
  `docs/asset_pipeline.md`.

## Builds

- `project.godot` `[application] config/version` is the build version source of
  truth.
- Use `scripts/dev/export_windows_release.sh` for Windows exports.
- If the current worktree contains unrelated WIP, build from a clean temporary
  worktree at the intended commit.
- Report the output path and version after exporting. Include a checksum when
  useful.

## Commits

- Commit only after the user asks for a commit.
- Keep commits focused and explain the scope in the message.
- Before committing, verify staged files with `git diff --cached --name-status`.
- Leave unrelated dirty files in place.
