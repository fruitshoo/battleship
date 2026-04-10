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
- `soldier_balance_preview.tscn`
  Sequential soldier combat harness for mirror, counter, repeater-volley, and mixed boarding scenarios.
  Prints per-scenario winners, survivor counts, and remaining HP totals.
  Script: `scripts/test/soldier_balance_preview.gd`
  Wrapper: `scripts/test/run_soldier_balance_preview.sh`
- `ship_combat_balance_preview.tscn`
  Sequential ship combat harness for gunner, melee, firepot, and mixed pressure scenarios.
  Prints per-scenario winners, hull totals, crew counts, boarding state, and derelict transitions.
  Script: `scripts/test/ship_combat_balance_preview.gd`
  Wrapper: `scripts/test/run_ship_combat_balance_preview.sh`
  The wrapper disables startup prewarm, runtime rewards, and autosave so the log stays focused on combat behavior instead of bootstrap or progression noise.
- `ship_combat_gauntlet_preview.tscn`
  Persistent-player gauntlet harness for chained ship fights and cumulative attrition checks.
  Prints per-encounter and final `hull / crew` loss across multiple enemy archetypes.
  Script: `scripts/test/ship_combat_gauntlet_preview.gd`
  Wrapper: `scripts/test/run_ship_combat_gauntlet_preview.sh`
  Pass `crew_sustain` as the first wrapper argument to inject the crew sustain upgrade preset and compare long-run attrition.
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
  Orchestrates the contract sweep by delegating scans and runtime smoke groups to focused helper scripts.
- `scripts/test/project_contract_scan_helper.gd`
  Headless script/scene load sweep plus legacy syntax scans for `yield()`, `funcref()`, `.instance()`, `String()`, and `bool()`.
- `scripts/test/project_contract_runtime_helper.gd`
  Runtime smoke helper for boss, enemy ship, launcher, projectile, and registry contracts.
- `scripts/test/project_contract_save_helper.gd`
  Save/load roundtrip smoke for `SaveManager` state and config files.
- `scripts/test/project_contract_hud_helper.gd`
  HUD state smoke for boarding, capture, stat panel, and ship debug UI states.
- `scripts/test/project_contract_support_helper.gd`
  Support-fleet lifecycle smoke for summon, registry, targeting, and repair paths.
- `scripts/test/project_contract_bootstrap_helper.gd`
  Startup audio mute/prewarm and effect prewarm smoke.
- `scripts/test/project_contract_recovery_helper.gd`
  Floating loot, survivor, and treasure chest collection smoke.
- `scripts/test/project_contract_scene_wiring_helper.gd`
  Scene wiring smoke for player, enemy, boss, and firepot ship scene contracts.
- `scripts/test/run_project_contract_sweep.sh`
  Shell wrapper that runs the contract sweep and fails on common script/runtime log errors.
- `scripts/test/run_soldier_balance_preview.sh`
  Headless wrapper for the soldier balance harness.
  Auto-quits after the summary report and fails on common runtime log errors or missing summary output.
- `scripts/test/run_ship_combat_balance_preview.sh`
  Headless wrapper for the ship combat balance harness.
  Auto-quits after the summary report, skips startup prewarm, disables runtime rewards/autosave for cleaner combat-only runs, and fails on common runtime log errors or missing summary output.
- `scripts/test/run_ship_combat_gauntlet_preview.sh`
  Headless wrapper for the cumulative ship combat gauntlet harness.
  Auto-quits after the summary report, skips startup prewarm, disables runtime rewards/autosave, and fails on common runtime log errors or missing summary output.
  Accepts an optional first argument such as `crew_sustain` to apply a gauntlet upgrade preset before the encounter chain begins.
- `scripts/test/run_leak_probe.sh`
  Leak summary wrapper for any auto-quitting scene.
  Defaults to `res://scenes/main.tscn`, prints RID/resource/ObjectDB totals, and can gate regressions with `LEAK_MAX_RID_TOTAL`, `LEAK_MAX_RESOURCES`, `LEAK_MAX_OBJECTDB_WARNINGS`, and `LEAK_MAX_PAGED_ALLOCATOR_WARNINGS`.
- `scripts/test/run_player_ship_leak_compare.sh`
  Compares `player_ship.tscn` leak totals with normal startup and with support-fleet autosummon disabled via probe-only env flag.
  Useful for checking how much of the bootstrap leak budget comes from support fleet initialization.
- `scenes/test/player_ship_component_probe.tscn`
  Auto-quitting probe scene that instantiates `player_ship.tscn` and can strip `Soldiers`, `WakeTrail`, or hull children via env flags before the ship enters the tree.
  Script: `scripts/test/player_ship_component_probe.gd`
- `scripts/test/run_player_ship_component_breakdown.sh`
  Runs the component probe as baseline, then compares `no_support`, `no_soldiers`, `no_wake`, `no_hull`, and fully stripped variants.
  Useful for narrowing which `player_ship` subsystems contribute most to leak totals.
- `scripts/test/run_player_ship_bootstrap_breakdown.sh`
  Reuses the component probe to compare `player_ship` bootstrap flags such as `no_upgrade_bootstrap`, `no_crew_sync`, and `bootstrap_min`.
  Useful for checking whether `_sync_player_crew_roster()` or deferred upgrade bootstrap calls contribute meaningfully to leak totals.
- `scenes/test/scene_load_probe.tscn`
  Generic auto-quitting load probe that can either just `load()` a target scene or also instantiate it via env flags.
  Script: `scripts/test/scene_load_probe.gd`
- `scripts/test/run_player_ship_load_vs_instance.sh`
  Uses the generic scene load probe to compare `player_ship.tscn` load-only versus instantiate leak totals.
  Useful for separating scene resource leak from runtime bootstrap leak.
- `scripts/test/run_ship_load_chain_breakdown.sh`
  Uses the generic load probe to compare ship script/scene resources such as `base_ship.gd`, `chaser_ship.gd`, `player_ship.gd`, and a few preload candidates.
  Useful for spotting whether leak budget is coming from a script preload chain or from an individual referenced scene.
- `scripts/test/run_chaser_script_isolation.sh`
  Compares lightweight `extends base_ship` isolation scripts against the real `chaser_ship.gd`.
  Also includes `process_loop`, `ai_core`, `process_ai`, `capture_minion`, `boarding_collision`, and `late_combined` buckets for narrowing the leak to specific late-method clusters.
  Useful for checking whether the leak comes from helper preloads, top-level declarations, or a specific method family inside the full chaser script.
