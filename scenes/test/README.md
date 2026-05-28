# Test Harness Notes

`scenes/test` contains lightweight preview and validation scenes used during iteration.

## Harness Map

Use the harnesses in four layers:

- Contract harnesses are for small deterministic regressions.
  Use these when a rule should never break again, such as boarding impact gating, rope pull lifetime, support rescue behavior, soldier incapacitation, HUD state, upgrade data, recovery pickups, or scene wiring.
- Preview harnesses are for feel and balance checks.
  Use these when the answer depends on watching motion, scale, sound, formation behavior, battle pacing, or encounter outcomes.
- Performance probes are for frame-time and runtime growth.
  Use these when the issue is a hitch, expensive visual option, projectile load, midgame stress, or leak-like long-run drift.
- Isolation probes are for narrowing a load or shutdown leak budget.
  Use these when a headless leak summary points at a broad scene/script chain and the next step is finding the subsystem bucket.

Default quick checks:

- `scripts/test/run_project_contract_sweep.sh`
  Broad smoke for scripts, scenes, save/load, HUD, support fleet, bootstrap, recovery effects, upgrades, scene wiring, and runtime spawning.
- `scripts/test/run_boarding_contracts.sh`
  Focused combat regression suite for boarding impact, navigation, chaos, support rescue, auto-raid recall, ship damage, and soldier incapacitation/weapon-state behavior.
  Runs each scene through the load probe with a boarding-suite leak budget, so contract behavior and shutdown growth stay checked together.
- `scripts/test/run_modularity_guard_suite.sh`
  Architecture guard suite for helper ownership, runtime scenario registry paths, pooling ownership, and world-space soldier motion.
- `scripts/test/run_ship_combat_balance_preview.sh`
  Short encounter feel check for ship combat balance.
- `scripts/test/run_midgame_performance_compare.sh`
  Compare harness for midgame frame-time cost.

Recent regression coverage to keep together:

- Scene contract encapsulation keeps ship-internal node names behind `BaseShip` and `NodeContractHelper` accessors.
  Production code should not call `get_node("Soldiers")`, `get_node_or_null("HitArea")`, `get_node_or_null("ProximityArea")`, `get_node_or_null("Cannons")`, upgrade-mount child names, or soldier body-part child names directly outside those owners; the modularity guard enforces this.
- Rope pull must require an active rope visual, so a cleared hook graphic cannot keep dragging ships.
- Support free-combat assist must recall near the player and keep rowing/wind compensation so it does not feel abandoned in free engagement mode.
- Enemy boarders on the player deck may speak, but ordinary enemy soldiers on their own ship should not spam speech labels.
- Cross-ship contact should avoid rail melee and prefer bow fire until boarding moves soldiers onto the same deck.
- Sail and rudder field repair should be scheduled by real rigging damage, wait before starting, recover only to emergency function, and pause while burning.
- Survivors, floating loot, static sea sites, sea decor, compass markers, and overcap crew recovery live under the project recovery contract helper rather than a separate ad hoc scene.
- Support squadron coverage keeps the active Panokseon artillery unlock, disabled Geobukseon support fallback, heavy-support role labels, and support-limit reconciliation in the same profile/upgrade smoke loop.
- Helper public-surface growth is intentional only when `module_boundaries.json` gets a matching baseline and exception/debt rationale; otherwise the modularity guard should fail loudly.

Current harness gaps:

- Rope and rock occlusion/transparency issues still need visual preview or screenshot-style checks; headless contract tests can only check state, not whether the player actually sees the mesh.
- Formation and support combat feel still needs preview/balance harness runs because small AI constant changes can be technically valid but feel too passive or too slippery.
- Sea decor pop-in/pop-out should be checked with a visibility/distance preview if it regresses again, since the current recovery contract mostly verifies spawn shape and collision semantics.
- Audio mix changes should be checked in-game or with a dedicated audio bus/sample report; the current sweep only catches wiring/runtime errors, not loudness feel.

When adding a new harness:

- Prefer a focused contract when the bug can be represented with a few mock nodes and a precise assertion.
- Prefer a preview when the bug is mostly visual, audio, balance, or pathing feel.
- Prefer a probe when the bug depends on time, density, memory, ObjectDB/RID summaries, or startup cost.
- Add the wrapper command here when it becomes part of the normal debugging loop.

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
- `transparent_vfx_render_harness.tscn`
  Visual check for transparent VFX render priority over ocean, deck, and sail-overlap backgrounds.
  Script: `scripts/test/transparent_vfx_render_harness.gd`

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
- `boarding_impact_contract.tscn`, `boarding_navigation_contract.tscn`, `boarding_chaos_contract.tscn`, `support_boarding_contract.tscn`, `auto_raid_recall_contract.tscn`, `soldier_incapacitation_contract.tscn`, `ship_damage_contract.tscn`
  Focused combat contract scenes for impact gating, approach geometry, cleanup/chaos handling, support boarding, raid recall, incapacitation behavior, and rigging field repair.
  Wrapper: `scripts/test/run_boarding_contracts.sh`
- `support_fleet_profile_preview.tscn`
  Support-fleet squadron slot assertions for Maengseon screens, Panokseon artillery leads, disabled Geobukseon fallback, and support-limit reconciliation.
  Script: `scripts/test/support_fleet_profile_preview.gd`
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
  Includes an `Atakebune Boarding` scenario that disables boss guns and forces close side-approach boarding so large-ship deck fighting can be verified directly.
  Prints per-scenario winners, hull totals, crew counts, boarding state, and derelict transitions.
  Script: `scripts/test/ship_combat_balance_preview.gd`
  Wrapper: `scripts/test/run_ship_combat_balance_preview.sh`
  The wrapper disables startup prewarm, runtime rewards, and autosave so the log stays focused on combat behavior instead of bootstrap or progression noise.
- `ship_combat_gauntlet_preview.tscn`
  Persistent-player gauntlet harness for chained ship fights and cumulative attrition checks.
  Prints per-encounter and final `hull / crew` loss across multiple enemy archetypes.
  Script: `scripts/test/ship_combat_gauntlet_preview.gd`
  Wrapper: `scripts/test/run_ship_combat_gauntlet_preview.sh`
  Pass `crew_sustain`, `cannon_pressure`, `crew_sustain_cannon`, `fleet_screen`, or `crew_sustain_fleet` as the first wrapper argument to inject an upgrade preset and compare long-run attrition.
- `mid_boss_balance_preview.tscn`
  Single-run mid-boss encounter harness with the player ship, support fleet, mid-boss, and escorts.
  Prints outcome, hull loss, crew loss, boarding, support, and escort survival metrics.
  Script: `scripts/test/mid_boss_balance_preview.gd`
  Wrapper: `scripts/test/run_mid_boss_balance_preview.sh`
- `upgrade_choice_preview.tscn`
  Early upgrade draft harness that simulates the first six ship/crew picks across repeated trials.
  Prints per-round offer and pick counts so core upgrades can be checked without a full run.
  Script: `scripts/test/upgrade_choice_preview.gd`
  Wrapper: `scripts/test/run_upgrade_choice_preview.sh`
- `performance_preview.tscn`
  FPS and frame-time stress harness for ship density, boarding, projectile, and full combat loads.
  Script: `scripts/test/performance_preview.gd`
  Supports `overlay_compare` for stat panel and distance debug cost checks.
  Supports `visual_compare` for deck light and moving-ship visual cost checks.
  Supports `projectile_compare` for cannonball, arrow, and fire pot cost checks.
- `midgame_fleet_battle_preview.tscn`
  Midgame fleet battle harness that stages repeating mixed and heavy waves at a fixed combat state.
  Supports `visual_compare` to compare lean battle load against full debug/visual load.
  Supports runtime leak probing in stress mode with periodic combat-load cleanup cycles.
  Prints phase summaries with average and p95 frame time, or runtime monitor summaries with memory, object, resource, node, and orphan-node counts.
  Script: `scripts/test/midgame_fleet_battle_preview.gd`
  Wrappers: `scripts/test/run_midgame_performance_compare.sh`, `scripts/test/run_midgame_runtime_leak_probe.sh`
  The compare wrapper auto-quits after the compare report, fails on common runtime errors, and can gate deltas with `MIDGAME_MAX_DELTA_AVG_MS` and `MIDGAME_MAX_DELTA_P95_MS`.
  The runtime leak wrapper defaults to a 300s run with 60s cleanup cycles and can gate orphan nodes and static-memory delta with `MIDGAME_RUNTIME_MAX_ORPHAN_NODES` and `MIDGAME_RUNTIME_MAX_STATIC_MB_DELTA`.
- `startup_hitch_probe.tscn`
  Startup frame-time probe for warmup and early cannon-fire hitch checks.
  Script: `scripts/test/startup_hitch_probe.gd`
  Wrapper: `scripts/test/run_startup_hitch_probe.sh`
- `sea_site_preview.tscn`
  Visual preview for static sea site scale, waterline height, labels, and compass marker direction.
  Script: `scripts/test/sea_site_preview.gd`
  Wrapper: `scripts/test/run_sea_site_preview.sh`

## Sandbox

- `combat_sandbox.tscn`
  Broader combat playground for mixed-system checks.
  Script: `scripts/test/combat_sandbox.gd`
- `project_contract_sweep.tscn`
  Project-wide load sweep plus a legacy-pattern scan, save/load, HUD, support-fleet, bootstrap audio/effect, recovery-effect, scene-wiring, typography, responsive UI, and screen-edge FX roundtrip smokes, and a small runtime smoke check for registry, boss, ship, launcher, and projectile contracts.
  Script: `scripts/test/project_contract_sweep.gd`
  Wrapper: `scripts/test/run_project_contract_sweep.sh`
- `typography_contract.tscn`
  Focused typography smoke for semantic menu labels, HUD timer styling, preview billboard labels, and soldier speech labels.
  Script: `scripts/test/typography_contract.gd`
  Wrapper: `scripts/test/run_typography_contract.sh`
- `screen_edge_fx_contract.tscn`
  Focused gameplay screen-edge FX smoke for vignette and motion blur intensity.
  Script: `scripts/test/screen_edge_fx_contract.gd`
  Wrapper: `scripts/test/run_screen_edge_fx_contract.sh`
- `responsive_ui_contract.tscn`
  Focused responsive UI smoke for main menu, pause, options, upgrade, meta-upgrade, and ship-control layout fit across compact, HD, and ultrawide viewport sizes.
  Script: `scripts/test/responsive_ui_contract.gd`
  Wrapper: `scripts/test/run_responsive_ui_contract.sh`
- `modularity_guard.tscn`
  Static architecture guard for helper registry coverage, runtime scenario matrix validity, helper public-surface drift, dependency boundaries, and coordinate/pooling hazards.
  Script: `scripts/test/modularity_guard.gd`
  Registry: `scripts/test/module_boundaries.json`
  Wrapper: `scripts/test/run_modularity_guard_suite.sh`
- `ship_ai_perception_helper_contract.tscn`
  Focused contract for LimboAI ship perception reads: team, role, boarding capability, hull ratio, engagement ranges, speed, distance, and target lead sampling.
  Script: `scripts/test/ship_ai_perception_helper_contract.gd`
  Wrapper: `scripts/test/run_ship_ai_perception_helper_contract.sh`
- `ship_ai_intent_helper_contract.tscn`
  Focused contract for converting fresh LimboAI ship metadata into execution-layer intent dictionaries without direct gameplay meta reads.
  Script: `scripts/test/ship_ai_intent_helper_contract.gd`
  Wrapper: `scripts/test/run_ship_ai_intent_helper_contract.sh`

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
- `scripts/test/project_contract_upgrade_helper.gd`
  Upgrade data and upgrade manager smoke for required fields, offer pools, and shared cannon/crew progression contracts.
- `scripts/test/project_contract_bootstrap_helper.gd`
  Startup audio mute/prewarm and effect prewarm smoke.
- `scripts/test/project_contract_recovery_helper.gd`
  Floating loot, survivor, and treasure chest collection smoke.
- `scripts/test/project_contract_scene_wiring_helper.gd`
  Scene wiring smoke for player, enemy, boss, and firepot ship scene contracts.
- `scripts/test/project_contract_typography_helper.gd`
  Typography smoke for menu display labels, HUD timer presets, preview billboard labels, and runtime soldier speech labels.
- `scripts/test/screen_edge_fx_contract_logic.gd`
  Shared smoke logic for the gameplay screen-edge vignette and motion blur overlay.
- `scripts/test/responsive_ui_contract_logic.gd`
  Shared smoke logic that resizes the viewport and verifies core modal and HUD-adjacent panels stay inside compact and wide resolutions.
- `scripts/test/run_project_contract_sweep.sh`
  Shell wrapper that runs the contract sweep and fails on common script/runtime log errors.
- `scripts/test/run_typography_contract.sh`
  Shell wrapper for the focused typography smoke harness.
- `scripts/test/run_screen_edge_fx_contract.sh`
  Shell wrapper for the focused gameplay screen-edge FX harness.
- `scripts/test/run_responsive_ui_contract.sh`
  Shell wrapper for the focused responsive UI layout harness.
- `scripts/test/run_boarding_contracts.sh`
  Shell wrapper for focused combat contracts covering impact gating, ship damage, navigation, chaos, support boarding, auto-raid recall, and soldier incapacitation.
  Runs each contract through the generic scene load probe and fails on common script/runtime log errors.
  Uses a suite-specific instantiated-scene leak budget of `LEAK_MAX_RID_TOTAL=320`, `LEAK_MAX_RESOURCES=520`, and `LEAK_MAX_PAGED_ALLOCATOR_WARNINGS=2`.
- `scripts/test/harness_log_gate.sh`
  Shared shell helper for common Godot script/runtime log error gates used by headless test wrappers.
- `scripts/test/run_modularity_guard_suite.sh`
  Shell wrapper that runs the modularity guard plus scene pool and soldier world-motion contracts.
- `scripts/test/run_soldier_balance_preview.sh`
  Headless wrapper for the soldier balance harness.
  Auto-quits after the summary report and fails on common runtime log errors or missing summary output.
- `scripts/test/run_ship_combat_balance_preview.sh`
  Headless wrapper for the ship combat balance harness.
  Auto-quits after the summary report, skips startup prewarm, disables runtime rewards/autosave for cleaner combat-only runs, and fails on common runtime log errors or missing summary output.
- `scripts/test/run_ship_combat_gauntlet_preview.sh`
  Headless wrapper for the cumulative ship combat gauntlet harness.
  Auto-quits after the summary report, skips startup prewarm, disables runtime rewards/autosave, and fails on common runtime log errors or missing summary output.
  Accepts an optional first argument such as `crew_sustain`, `cannon_pressure`, `crew_sustain_cannon`, `fleet_screen`, or `crew_sustain_fleet` to apply a gauntlet upgrade preset before the encounter chain begins.
  Accepts an optional second argument `no_recovery` to disable survivor, floating loot, and treasure recovery pickups during the gauntlet.
- `scripts/test/run_mid_boss_balance_preview.sh`
  Headless wrapper for the mid-boss balance harness.
  Defaults to a 60 second run with one support ship; pass duration and support limit as optional arguments.
- `scripts/test/run_mid_boss_balance_compare.sh`
  Runs the mid-boss balance harness across support-fleet limits.
  Defaults to a 60 second run with support limits 0, 1, and 2; pass duration first and optional support limits after it.
- `scripts/test/run_upgrade_choice_preview.sh`
  Headless wrapper for the upgrade choice draft harness.
  Auto-quits after the summary report and fails on common runtime log errors or missing summary output.
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
  Uses the generic load probe to compare ship script/scene resources such as `base_ship.gd`, `ai_ship.gd`, `player_ship.gd`, and a few preload candidates.
  Useful for spotting whether leak budget is coming from a script preload chain or from an individual referenced scene.
- `scripts/test/run_ai_ship_script_isolation.sh`
  Compares lightweight `extends base_ship` isolation scripts against the real `ai_ship.gd` runtime script.
  Also includes `process_loop`, `ai_core`, `process_ai`, `legacy_capture`, `boarding_collision`, and `late_combined` buckets for narrowing the leak to specific late-method clusters.
  Useful for checking whether the leak comes from helper preloads, top-level declarations, or a specific method family inside the full AI ship script.

- `cannon_crew_reload_contract.tscn`
  Script: `scripts/test/cannon_crew_reload_contract.gd`
  Wrapper: `scripts/test/run_cannon_crew_reload_contract.sh`
  Checks modular cannon reload crew power, active broadside allocation, slot reservation, and the legacy reload multiplier fallback.

- `flag_rig_contract.tscn`
  Script: `scripts/test/flag_rig_contract.gd`
  Wrapper: `scripts/test/run_flag_rig_contract.sh`
  Checks concrete flag scene variants, yard-top rigs, streamer generation, and mast runtime flag-scene swapping.
