# Ship Authoring

Ship scenes should be built so the editor view predicts the runtime result.
The current ships still support legacy auto-fit behavior, but new ships should
prefer explicit authoring nodes where possible.

## Ship Blueprints

`data/ship_stats.json` is the first assembly layer for ships. A `ship_type`
selects a small blueprint that combines runtime stats, combat role, crew mix,
and the hull scene. New ship variants should prefer adding or editing a row
there before adding script-only conditionals.

Core blueprint fields:

- `ship_archetype`: reusable full-ship assembly from `ship_archetypes`
- `hull_scene`: hull scene used by editor previews and runtime spawning
- `hull_hp`, `move_speed`, `deck_height`: base physical stats
- `combat_profile`: reusable AI posture from `combat_profiles`
- `crew_composition`: ordered crew bag expanded by `ShipBlueprintHelper`
- `weapon_loadout`: ship weapons assembled by `ShipWeaponLoadoutHelper`

`ShipBlueprintHelper` keeps fallback hull mapping for legacy ship ids, but the
goal is that a ship can be assembled by picking a `ship_type`, hull markers,
weapon slots, and crew composition rather than editing several scripts.

`ship_archetypes` entries define reusable full-ship assemblies: hull scene,
base stats, combat profile, crew composition, and weapon loadout. A `ship_type`
can now be as small as a display name plus a selected archetype:

```json
{
  "name": "Cannon Sekibune",
  "ship_archetype": "sekibune_gunner"
}
```

A ship can still override any inherited field directly, so variants can reuse
an archetype while changing only a weapon slot, crew bag, HP value, or combat
profile.

`combat_profiles` entries define reusable movement and engagement postures.
Loadouts such as `raider_charger`, `stand_off_gunner`, and
`final_boss_gunner` group fields like `combat_role`, `allow_boarding`,
`preferred_range`, `range_tolerance`, `retreat_distance`, and boss
`orbit_distance`. A ship can still override any inherited field directly:

```json
{
  "combat_profile": "stand_off_gunner",
  "preferred_range": 16.0
}
```

`weapon_profiles` entries define reusable weapon blocks: kind, launcher scene,
projectile, team, and common runtime tuning. `weapon_loadout` entries then pick
a profile and name the authoring slot they prefer. For example a support ship
can declare three `joseon_light_cannon` entries using `CannonFront`,
`CannonLeft`, and `CannonRight`; if hull markers with those names exist, they
override the fallback positions in the JSON. Boss ships can mix cannon and
singigeon profiles in the same list. The player ship also declares its cannon
upgrade slots in
`panokseon_player.weapon_loadout`, so changing the player broadside layout
should start in the blueprint instead of in `UpgradeManager`.

Profiles can be overridden per entry when a variant needs a one-off value:

```json
{
  "profile": "joseon_light_cannon",
  "name": "CannonLeft",
  "slot": "CannonLeft",
  "required_level": 2
}
```

Common profile/runtime fields include:

- `profile`: reusable weapon profile name from `weapon_profiles`
- `kind`: `cannon` or `singigeon`
- `scene`: launcher PackedScene
- `team`: `player` or `enemy`
- `projectile_scene`: projectile PackedScene assigned to launcher properties
  such as `cannonball_scene` or `rocket_scene`
- `fire_cooldown`, `detection_range`, `detection_arc`, `projectile_speed`:
  launcher tuning values applied when the weapon is spawned
- `upgrade_level`: optional launcher upgrade hook for scenes that implement
  `upgrade_to_level`

## Spawn Recipes

`data/enemy_spawn_rules.json` is the encounter assembly layer. `spawn_recipes`
define reusable groups of ship types and roles, while `formation.fleet_templates`
decides which recipes belong to light, mixed, or heavy encounter pools:

```json
{
  "recipe": "mixed_crossfire"
}
```

Recipes can still be overridden inline with direct `ships` entries, but new
encounters should prefer naming the recipe once and reusing it from the fleet
pool. This keeps encounter authoring close to a map editor: choose a recipe,
choose a formation, then let the spawner place the ships around the player.

`encounter_profiles` define the next assembly layer: time windows that choose
between fleet pools. `formation.encounter_profile` selects the active profile,
and each row points to fleet classes through `fleet_weights`:

```json
{
  "encounter_profile": "opening_pressure"
}
```

Inside the profile, `fleet_weights` can reference any fleet class declared in
`formation.fleet_templates`. Legacy `light_weight`, `mixed_weight`, and
`heavy_weight` rows still parse, but new encounter schedules should use the
named `fleet_weights` dictionary so custom pools can be added without changing
spawner code.

`scenario_triggers` are the map-editor style trigger layer. A trigger watches a
condition and runs one or more actions once it becomes true. Current triggers
support elapsed-time conditions and actions such as switching the active
encounter profile:

```json
{
  "id": "enter_midgame_pressure",
  "condition": { "elapsed_time": 120.0 },
  "actions": [
    { "type": "set_encounter_profile", "profile": "midgame_pressure" }
  ]
}
```

The runtime also understands `spawn_fleet`, `spawn_recipe`, `spawn_ship`,
`run_scenario_trigger`, `spawn_mid_boss`, `trigger_boss_event`, and
`stop_regular_spawns` actions. New default encounter rules should prefer
profile-switch triggers before direct boss or fleet spawns, because they
preserve the normal spawn budget while still changing the shape of the battle.

## Authoring Palette

`data/authoring_palette.json` is the editor-facing inventory of reusable parts.
It does not redefine stats or encounter behavior; it lists stable ids from
`ship_stats.json` and `enemy_spawn_rules.json` so tools can offer a palette of
things to place or combine:

- `ship_archetypes`
- `ship_types`
- `weapon_profiles`
- `combat_profiles`
- `movement_intents`
- `spawn_recipes`
- `fleet_classes`
- `encounter_profiles`
- `scenario_triggers`

The top-level `block_schema_version` and `assembly_blocks` table describe how
each catalog behaves as a Lego-like authoring block: `action` blocks execute a
runtime command such as `spawn_ship` or `spawn_recipe`, `authoring_meta` blocks
fill the assembly card, and `reference` blocks expose reusable source pieces
without direct execution. The contract requires one block descriptor for every
palette catalog so HUD tools and runtime harnesses agree on the same assembly
surface.

Each palette entry has an `id`, `label`, and optional `tags`. Some entries also
carry a small reference field such as `ship_archetype`, `fleet_class`, or
`recipes` so an editor can group related parts without reading every source
file. `movement_intents` are palette-local reference blocks for recurring AI
steering states such as side-follow, contact settle, rear recovery, support
assist, and ranged standoff. Each movement intent declares a `family`, currently
`enemy_runtime` or `support_runtime`, so authoring tools know which runtime
harness owns the intent instead of guessing from tags. They give designers a
named movement intent to pair mentally with a ship or combat profile without
turning that reference into a runtime action.
The project contract sweep verifies that every source-backed listed id still
exists in the source data, that every source-data part has a palette entry, and
that palette-local catalog entries have stable ids, labels, modes, and
descriptions.

The debug HUD reads this palette in debug builds. The `조립 팔레트` section lets
authors select a reusable part into a small assembly slot, run it immediately,
or add several selected parts into a queue, reorder the selected queue item, and
duplicate or delete only the selected queue item before executing the queue in order.
Hovering or keyboard-focusing a palette button previews the resolved source
data: ship archetype, combat profile, crew/loadout, recipe ships, profile
weights, movement intent, or trigger actions. Combat profile and movement
intent buttons are reference-only: selecting them updates the preview and
selection slot, but does not enable immediate execution or queue insertion.
Those selections also fill the HUD's assembly card. When a ship or recipe is
added to the queue, the card is copied into that queue action as `authoring`
metadata, preserving the chosen combat profile and movement intent in saved
queues, presets, trigger exports, and merge-ready patches without changing the
runtime spawn command. The card and queue display the movement intent family
next to the chosen movement intent so enemy-runtime and support-runtime blocks
remain visually distinct while assembling. The queue can be saved to and loaded from
`user://authoring_palette_queue.json`, using a small JSON action list, and it
can also be exported as a ready-to-copy scenario trigger fragment at
`user://authoring_palette_scenario_trigger.json`. Named queue presets are kept
at `user://authoring_palette_scenario_presets.json`; each preset stores both
the editable queue actions and the runtime `scenario_triggers` fragment. The
HUD preset picker lists saved presets so authors can choose a stored encounter
fragment, inspect its action list, load it back into the queue, or execute it
immediately without mutating the current queue. The selected preset can also be
exported as a merge-ready data patch at
`user://authoring_palette_data_patch.json`; the patch targets
`res://data/enemy_spawn_rules.json` and carries a `scenario_triggers` fragment
without overwriting source data from inside the running game. The HUD can also
check that patch for merge blockers: duplicate trigger ids, unsupported action
types, and missing ship, recipe, fleet, profile, or trigger references. If the
patch is clean, the HUD can merge its `scenario_triggers` into
`data/enemy_spawn_rules.json` and add matching trigger entries to
`data/authoring_palette.json` so the new encounter fragment returns to the
palette as a reusable part. The selected preset can also be deleted from the
user preset store without changing the current queue. The project contract
sweep includes a HUD harness for the selection slot, preview text, clear
action, reference-only combat/movement blocks, assembly-card metadata, queue
save/load, scenario-trigger export, named preset save/load, queue reorder,
queue item duplication/deletion, preset selection, preset content preview,
data-patch promotion/checking, blocked merge handling, direct preset execution,
preset deletion, and execute path.

## Deck Work Priority

`SoldierShipWorkPriorityHelper` owns the runtime priority table for shipboard
work. The table is ordered from emergency work to routine duty:
`deck_defense`, `corpse_cleanup`, `cannon_reload`, `rigging_repair`,
`gunnery_station`, `shiphandling_rowing`, `shiphandling_rudder`, and
`shiphandling_cruise`. Each row declares its priority, phase, runtime owner,
and whether it preempts routine deck work. Immediate actions such as corpse
cleanup and cannon reload reserve their own work slot, while routine duty asks
for a ship work directive through `SoldierShipDutyHelper`.

`SoldierActionHelper` owns the named action catalog for soldier-side work. An
action definition gives each action a stable name, family, AI-lock default, and
animation name. Corpse cleanup currently names `corpse_cleanup_approach`,
`corpse_cleanup_carry`, and `corpse_cleanup_throw` without forcing a custom
pose, so visual animation can be added later without changing the gameplay
sequence. Cannon reload uses the same catalog through `cannon_reload`.

`ShipAllyRoleHelper` owns allied ship roles. `player_flagship`,
`support_fleet`, and `captured_minion` are separate roles even when old runtime
paths still use the `captured_minion` group as a shared ally-minion bucket.
Only `captured_minion` consumes capture slots; support ships can share the
legacy bucket for AI discovery without reducing the player's captured-ship
capacity.

## Root Structure

Required root children:

- `HitArea`: `Area3D` with `CollisionShape3D` using `BoxShape3D`
- `ProximityArea`: `Area3D` with `CollisionShape3D` using `BoxShape3D`
- `Soldiers`: crew container
- a hull source: either a visible `*Hull` child or an exported `hull_scene`

Optional authoring root:

```text
Authoring (ShipAuthoringVisualizer)
  DeckArea
  BoardingAnchors
  CannonSlots
  WeaponSlots
  CrewSlots
```

These optional markers are safe to add now. If they are absent, the game keeps
using the existing automatic hull/deck calculations.

All current hull scenes expose this authoring root. Large or boss-ready hulls
provide seven cannon slots and eight crew slots. Smaller raider/support hulls
provide at least front/left/right cannon slots and six crew slots.
`WeaponSlots` is optional for legacy cannon-only hulls; use it for non-cannon
launchers such as `SingigeonFront`.

## Boarding Anchors

`Authoring/BoardingAnchors` can contain `Marker3D` nodes. Names containing
`Left` or `Port` are used for the left side. Names containing `Right` or
`Starboard` are used for the right side. When markers exist, boarding ropes use
them before falling back to calculated deck-edge positions.

The current player hull uses:

- `RightForward`
- `RightMid`
- `RightRear`
- `LeftForward`
- `LeftMid`
- `LeftRear`
- `Bow`
- `Stern`

## Cannon Slots

`Authoring/CannonSlots` can contain `Marker3D` nodes named after cannon slots.
The player cannon upgrade sync reads `panokseon_player.weapon_loadout`, then lets
these markers override the JSON fallback positions. Supported player slot names:

- `CannonFront`
- `CannonLeft`
- `CannonRight`
- `CannonLeftExtra`
- `CannonRightExtra`
- `CannonLeftExtraRear`
- `CannonRightExtraForward`

Existing visible cannon nodes with the same names are still valid authoring
sources when a marker is absent.

## Weapon Slots

`Authoring/WeaponSlots` is the generic launcher slot layer. Runtime loadout
placement checks `WeaponSlots` first and falls back to `CannonSlots`, so old
cannon-only hulls keep working while new launchers can use the same assembly
path.

The current boss hull uses:

- `SingigeonFront`

## Support Ship Template

Player support ships use `res://scenes/ships/support_ship.tscn`. The scene uses
`support_ship.gd`, which inherits the existing `ChaserShip` behavior but fixes
the ship identity as a player support-fleet ship. Support spawning should
instantiate this scene directly instead of borrowing `enemy_ship.tscn` and
overriding hidden properties in code.

The support ship currently uses `maengseon_hull.tscn`, which provides:

- 3 `CannonSlots` for the support cannon cap
- 8 `BoardingAnchors` for rope attachment
- 6 `CrewSlots` for initial and rescued support crew placement

## Current Hull Coverage

The project contract sweep checks authoring markers on these hull scenes:

- `panokseon_hull.tscn`
- `maengseon_hull.tscn`
- `atakebune_hull.tscn`
- `geobukseon_hull.tscn`
- `kobayabune_hull.tscn`
- `sekibune_hull.tscn`
- `sekibune_melee_hull.tscn`

Every listed hull must keep `DeckArea`, `BoardingAnchors`, `CannonSlots`, and
`CrewSlots` so ship scenes can be assembled visually instead of relying on
hidden script-only defaults. Hulls with non-cannon launchers must also expose
matching `WeaponSlots`.

The sweep also checks rough marker layout. Cannon, weapon, and crew slots should
stay inside the visible hull footprint. Side boarding anchors should sit near
the left/right hull edges, while `Bow` and `Stern` should stay near the forward
and rear ends.

`Authoring` should keep `ship_authoring_visualizer.gd` attached. It is an
editor-only helper that draws a light deck footprint plus color-coded marker
proxies:

- yellow: `CannonSlots`
- red: `WeaponSlots`
- cyan: `BoardingAnchors`
- green: `CrewSlots`

The helper does not create runtime gameplay nodes.
The project contract sweep fails if generated visual nodes are ever saved into
the hull `.tscn` files or appear during runtime scene instantiation.

## Crew Slots

`Authoring/CrewSlots` can contain `Marker3D` nodes for initial player crew and
new crew spawn positions. If these markers are absent, crew still uses the old
random deck placement fallback. The current player hull uses:

- `CrewForwardLeft`
- `CrewForwardRight`
- `CrewMidLeft`
- `CrewMidRight`
- `CrewRearLeft`
- `CrewRearRight`
- `CrewSternLeft`
- `CrewSternRight`

## Validation

`ProjectContractSceneWiringHelper` runs `ShipAuthoringHelper` against the core
ship scenes during the project contract sweep. This catches missing hull sources,
missing contact areas, invalid contact shapes, and missing authoring summary
methods before a ship silently behaves differently at runtime. It also checks
the current hull scene library for minimum authoring marker coverage.

The same sweep validates `ship_archetypes`, `combat_profiles`,
`weapon_profiles`, and `weapon_loadout` entries in `data/ship_stats.json`.
Ship types must reference existing archetypes, and validation runs against the
resolved ship assembly. Combat profiles must use a supported `combat_role`,
boolean `allow_boarding`, and positive engagement distances. Weapon profiles
must resolve to supported weapon runtime fields, and loadout entries may either
declare those fields directly or inherit them through `profile`. Each resolved
loadout entry must have a supported `kind`, a unique `name`, a loadable
PackedScene in `scene`, and a non-empty `slot`. Slots must reference either
`Authoring/WeaponSlots` or the legacy `Authoring/CannonSlots` markers on the
selected hull. Optional `projectile_scene` paths must also load as
PackedScenes, `team` must be `player` or `enemy`, and positive tuning fields
must be greater than zero. The sweep also validates `enemy_spawn_rules.json`
spawn recipes, encounter profiles, scenario triggers, fleet template recipe
references, formation types, and spawned ship type names. Scenario trigger
actions are checked against the runtime-supported action set, including
`spawn_recipe`, `spawn_ship`, and `run_scenario_trigger`, so promoted palette
patches stay compatible with the project contract. Finally,
`authoring_palette.json` is checked against those source-data ids so editor
palettes cannot drift away from the actual game assembly blocks.
