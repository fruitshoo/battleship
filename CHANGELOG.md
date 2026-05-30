# Changelog

## 0.4.4-alpha - 2026-05-30

### Performance
- Reduced soldier AI overhead by simplifying routine wander movement and deck-boundary correction.
- Split the in-game performance overlay into clearer frame, scene, render, ship, boarding, profile, and exclusive buckets.
- Added perf overlay shortcuts: `F10` toggle, `F9` freeze/live, and `F8` copy.
- Limited enemy-vs-enemy ship contact checks in crowded fights while keeping player-vs-enemy collision feel.

### Gameplay
- Simplified ship-to-ship soldier combat so visible melee happens after boarding puts enemies on the same deck.
- Kept support ship cards as summon choices: Maengseon can be active up to 2 ships, Panokseon up to 1 ship, and sunk supports can make their cards eligible again.
- Improved authored deck usage so `DeckArea` and `CrewSlots` guide soldier spawn and movement more consistently.

### Build
- Kept LimboAI disabled by default and excluded LimboAI/DebugDraw3D GDExtension DLLs from Windows release exports.
- Updated ship AI and authoring docs to match the current optimization and export rules.
