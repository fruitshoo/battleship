# Versioning

The project uses a pre-1.0 semantic version style while the game is still changing quickly.

## Source of Truth

`project.godot` `[application] config/version` is the single version source for builds.

Windows release exports should use this value automatically for both the output folder and zip file name:

```text
exports/windows-v{version}/Battleship-v{version}.exe
exports/Battleship-v{version}-windows.zip
```

Example:

```text
config/version="0.4.1-alpha"
exports/Battleship-v0.4.1-alpha-windows.zip
```

## Bump Rules

- Patch bump, e.g. `0.4.0-alpha` -> `0.4.1-alpha`:
  Balance changes, tuning, UI polish, minor content additions, bug fixes, and small feel improvements.
- Minor bump, e.g. `0.4.1-alpha` -> `0.5.0-alpha`:
  New or heavily reworked gameplay systems, major progression changes, new boss-flow structure, or large content additions.
- Keep `alpha` until the game has a stable feature set and the save/progression loop is no longer being heavily redesigned.

## Codex Build Rule

When asked to make a Windows build, Codex should:

1. Read `config/version` from `project.godot`.
2. Update `CHANGELOG.md` for the version being exported. Keep it short and
   player/tester-facing; mention if there were no user-visible changes.
3. Export the Windows preset using that exact version string.
4. Name the folder and zip with `v{version}`.
5. Mention the version, changelog summary, and output path in the final
   response.

Use `scripts/dev/export_windows_release.sh` for this workflow.
