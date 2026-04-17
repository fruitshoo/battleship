# Audio Replacement Plan

Status: assume all current audio assets are replacement targets for release until proven otherwise.

## Policy

- Treat every runtime audio asset under `assets/audio` as temporary/development-use only.
- Do not ship any audio asset unless its commercial-use license is verified and recorded.
- Preferred replacement sources:
  - `CC0`
  - `CC BY` with attribution recorded
  - commercially licensed packs
  - first-party / custom-made assets

## Replacement Priority

### Tier 1: Core Combat and Feedback
These affect moment-to-moment feel and should be replaced first.

- `cannon_fire`
- `impact_wood`
- `rocket_launch`
- `heavy_missle_impact`
- `sword_swing`
- `soldier_hit`
- `soldier_die`
- `bow_shoot`
- `water_splash_large`
- `water_splash_small`
- `treasure_collect`
- `ui_click`
- `level_up`

#### Tier 1 checklist

- [ ] `cannon_fire`: 2-3 variants, short transient, low tail
- [ ] `impact_wood` / `wood_break`: dry wood hit/break pair
- [ ] `rocket_launch` / `heavy_missle_impact`: launch + impact pair
- [ ] `sword_swing`: at least 4 variants
- [ ] `soldier_hit`: at least 4 light hit / metallic contact variants
- [ ] `soldier_die`: at least 4-6 short death splashes / body falls
- [ ] `bow_shoot`: 2-3 variants
- [ ] `water_splash_large`: 3 variants
- [ ] `water_splash_small`: 3 variants
- [ ] `treasure_collect`: 3 lightweight pickup variants
- [ ] `ui_click`: 5 lightweight UI variants, same loudness family
- [ ] `level_up`: 1 signature progression cue

### Tier 2: Vehicle / Movement / State
These matter a lot, but the game remains testable without final versions.

- `oars_rowing`
- `sail_flap`
- `cannon_fuse`
- `cannon_reload`
- `fire_crackling` (current project file: `sfx_fire_crackling.ogg`, if kept it still needs verified provenance)

### Tier 3: Ambient / Flavor
These can be swapped later without blocking release prep.

- `wave_splash`
- `flag_flapping`
- `flag_crash`
- `steam_hiss`
- `metal_drop`
- miscellaneous one-off placeholder clips

### Future Flavor: Cute Soldier Charge Shouts

This is a future task, not part of the current audio pass.
Reference mood: `Shieldwall`-style small, cute soldier charge voices rather than realistic war screams.

Target feel:

- Short toy-soldier shouts, about 0.3-0.7 seconds each.
- Cute and lively, not harsh, scary, or overly realistic.
- Best for emotional attachment to individual soldiers as the crew-survival loop becomes more important.

Suggested trigger points:

- Charge start: when a small group commits to boarding or rushes into melee.
- Boarding jump / deck clash: low random chance on the first contact moment.
- Capture success: a tiny cheer after an enemy ship is secured.

Implementation guardrails:

- Do not let every soldier shout. Pick 1-3 voices from a group event.
- Add a group cooldown, roughly 6-12 seconds, so it does not become noisy.
- Use small pitch variation per playback to create several soldier-like voices from a few recordings.
- Keep camera-distance attenuation mild, similar to recent melee/bow SFX tuning.
- Avoid triggering during constant idle guard standoffs; it should mark commitment or success.

Candidate file plan:

- `sfx_soldier_charge_wa_01.ogg`
- `sfx_soldier_charge_wa_02.ogg`
- `sfx_soldier_charge_gaja_01.ogg`
- `sfx_soldier_charge_chyeora_01.ogg`
- `sfx_soldier_cheer_manse_01.ogg`

Preferred source:

- First-party recordings or custom-made voice clips.
- If using an external pack, record exact source and license in [audio_license_inventory.md](/Users/shk/Godot/battleship/docs/audio_license_inventory.md).

## Release blockers

These should not remain unresolved near release:

- Any file still marked `UNVERIFIED` in [audio_license_inventory.md](/Users/shk/Godot/battleship/docs/audio_license_inventory.md)
- Any runtime key in `AudioManager` still pointing at temporary audio
- Format outliers that should likely be normalized during replacement:
  - `sfx_metal_drop.mp3`
  - `sfx_water_splash.mov`

## Current asset notes

- `click1.ogg` ~ `click5.ogg`
  - Present in the project, but not currently mapped by `AudioManager`
  - Verify whether these are old leftovers or candidates for future UI replacements
- `sfx_water_splash.mov`
  - Suspicious as a runtime audio asset
  - Verify whether this is a mistaken export or a source file that should stay outside shipping assets

## Runtime Mapping
Current `AudioManager` keys and the files they map to.

| Key | Files |
|---|---|
| `cannon_fire` | `sfx_cannon_fire.ogg`, `sfx_cannon_fire_02.ogg` |
| `cannon_fuse` | `sfx_match_sizzle.ogg`, `sfx_steam_hiss.ogg` |
| `impact_wood` | `sfx_flag_crash.ogg` |
| `ui_click` | `sfx_ui_click_1.ogg` ~ `sfx_ui_click_5.ogg` |
| `level_up` | `sfx_levelup.ogg` |
| `rocket_launch` | `sfx_explosion_impact.ogg` |
| `rocket_launch_01` | `sfx_rocket_launch_01.ogg` |
| `rocket_launch_02` | `sfx_rocket_launch_02.ogg` |
| `rocket_launch_03` | `sfx_rocket_launch_03.ogg` |
| `heavy_missle_impact` | `sfx_heavy_missle_impact.ogg` |
| `wood_break` | `sfx_flag_crash.ogg` |
| `sail_flap` | `sfx_flag_flapping.ogg` |
| `sword_swing` | `sfx_sword_swing_1.ogg` ~ `sfx_sword_swing_4.ogg` |
| `bow_shoot` | `sfx_bow_01.ogg`, `sfx_bow_02.ogg` |
| `musket_fire` | `sfx_musket_fire.ogg`, `sfx_musket_fire_02.ogg` |
| `soldier_hit` | `sfx_sword_ting_1.ogg` ~ `sfx_sword_ting_4.ogg` |
| `wave_splash` | `sfx_wave_01.ogg` ~ `sfx_wave_03.ogg` |
| `treasure_collect` | `sfx_pickup_1.ogg` ~ `sfx_pickup_3.ogg` |
| `soldier_die` | `sfx_soldier_die_1.ogg` ~ `sfx_soldier_die_6.ogg` |
| `water_splash_large` | `sfx_water_splash_large_1.ogg` ~ `sfx_water_splash_large_3.ogg` |
| `water_splash_small` | `sfx_water_splash_small_1.ogg` ~ `sfx_water_splash_small_3.ogg` |
| `cannon_reload` | `sfx_metal_drop.mp3` |
| `oars_rowing` | `sfx_oars.ogg` |

## Suggested Work Order

1. Replace Tier 1 assets with clearly licensed commercial-safe alternatives.
2. Update `docs/audio_license_inventory.md` with verified source + license for new files.
3. Rename or keep existing runtime keys so gameplay code does not need to change.
4. Replace Tier 2 assets.
5. Replace Tier 3 assets.
6. Before release, verify that no `UNVERIFIED` entries remain in `docs/audio_license_inventory.md`.
7. Remove any leftover unused source files from `assets/audio` after runtime mappings are finalized.

## Notes

- Favor keeping the current `AudioManager` keys stable and only swapping file paths.
- If a replacement pack contains multiple variants, match the current pattern of grouped random playback.
- Consider converting `sfx_metal_drop.mp3` to `.ogg` during replacement so all SFX share the same distribution format.
