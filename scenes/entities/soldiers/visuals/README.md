# Soldier Visual Scenes

`soldier.tscn` owns gameplay, collision, weapons, markers, and AI. Files in this
folder are only the replaceable visual body for a soldier.

## Scene Contract

- The scene root should be a `Node3D`.
- Name the main body mesh `Body`. It may be nested, for example
  `Armature/Body` or `ModelRoot/Body`.
- Extra meshes such as `Head`, `Hat`, `Armor`, or cloth pieces are fine.
- Team color, hit flash, and death tint use the `Body` mesh.
- Attack and death/recovery pose movement uses the whole visual root
  instantiated as `VisualRoot/CustomVisual`.
- If no custom visual is assigned, `soldier.tscn` falls back to its capsule mesh.

## Current Slots

- `soldier_player_visual.tscn`
- `soldier_enemy_visual.tscn`
- `soldier_captain_visual.tscn`

When real models are ready, replace the placeholder body inside these scenes
instead of changing the soldier gameplay scene.
