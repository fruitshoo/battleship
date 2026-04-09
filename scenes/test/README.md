# Test Harness Notes

`scenes/test` contains lightweight preview and validation scenes used during iteration.

## Shared Base

- `preview_base.tscn`
  Minimal gameplay shell for preview scenes.
  Includes the player ship, HUD, ocean, environment, spawner, and level manager.

## Sail And Mast

- `mast_preview.tscn`
  Visual check for mast and sail presentation.
- `ship_damage_preview.tscn`
  Damage preset preview for sail wear, burn, and wreck states.
- `hybrid_sail_preview.tscn`
  Additional sail material and shape experimentation scene.

## Enemy And Boarding

- `enemy_role_preview.tscn`
  Compares melee, gunner, and firepot enemy role setups.
  Script: `scripts/test/enemy_role_preview.gd`
- `boarding_preview.tscn`
  Close-range boarding setup preview against the player ship.
  Script: `scripts/test/boarding_preview.gd`
- `boarding_navigation_preview.tscn`
  Front, port, rear, and starboard boarding approach scenarios.
  Script: `scripts/test/boarding_navigation_preview.gd`
- `firepot_preview.tscn`
  Fire pot attack gating scenarios such as no target, no tosser, and out of range.
  Script: `scripts/test/firepot_preview.gd`
- `cannon_range_preview.tscn`
  Cannon range and active-slot preview across close, ideal, edge, and out distances.
  Script: `scripts/test/cannon_range_preview.gd`
- `performance_preview.tscn`
  FPS and frame-time stress harness for ship density, boarding, projectile, and full combat loads.
  Script: `scripts/test/performance_preview.gd`
  Supports `overlay_compare` for stat panel and distance debug cost checks.
  Supports `visual_compare` for deck light and moving-ship visual cost checks.
  Supports `projectile_compare` for cannonball, arrow, and fire pot cost checks.
- `midgame_fleet_battle_preview.tscn`
  Midgame fleet battle harness that stages repeating mixed and heavy waves at a fixed combat state.
  Supports `visual_compare` to compare lean battle load against full debug/visual load.
  Prints phase summaries with average and p95 frame time.
  Script: `scripts/test/midgame_fleet_battle_preview.gd`
  Wrapper: `scripts/test/run_midgame_performance_compare.sh`
  The wrapper auto-quits after the compare report, fails on common runtime errors, and can gate deltas with `MIDGAME_MAX_DELTA_AVG_MS` and `MIDGAME_MAX_DELTA_P95_MS`.

## Sandbox

- `combat_sandbox.tscn`
  Broader combat playground for mixed-system checks.
  Script: `scripts/test/combat_sandbox.gd`
- `project_contract_sweep.tscn`
  Project-wide load sweep plus a legacy-pattern scan, save/load, HUD, support-fleet, bootstrap audio/effect, recovery-effect, and scene-wiring roundtrip smokes, and a small runtime smoke check for registry, boss, ship, launcher, and projectile contracts.
  Script: `scripts/test/project_contract_sweep.gd`
  Wrapper: `scripts/test/run_project_contract_sweep.sh`

## Helper Scripts

- `scripts/test/preview_harness_helper.gd`
  Shared preview bootstrapping and preview ship setup helpers.
- `scripts/test/preview_state_snapshot_helper.gd`
  Shared label text formatting and simple state snapshot helpers.
- `scripts/test/project_contract_sweep.gd`
  Loads scripts and scenes headless, checks for common Godot 3-era syntax leftovers, then runs a small runtime smoke check against preview base, ship spawns, launcher fires, projectile launches, and boss spawns.
- `scripts/test/run_project_contract_sweep.sh`
  Shell wrapper that runs the contract sweep and fails on common script/runtime log errors.
- `scripts/test/run_leak_probe.sh`
  Leak summary wrapper for any auto-quitting scene.
  Defaults to `res://scenes/main.tscn`, prints RID/resource/ObjectDB totals, and can gate regressions with `LEAK_MAX_RID_TOTAL`, `LEAK_MAX_RESOURCES`, `LEAK_MAX_OBJECTDB_WARNINGS`, and `LEAK_MAX_PAGED_ALLOCATOR_WARNINGS`.
