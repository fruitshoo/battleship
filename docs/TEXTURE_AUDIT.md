# Texture Audit

Last checked: 2026-03-21

This is a quick audit of large texture files and obvious cleanup candidates.
The focus is:

- duplicate files that can likely be consolidated
- runtime textures that look larger or less compressed than necessary
- "source" or preview files that may not need to ship

## High-value duplicate candidates

These files are byte-for-byte identical.

### Shield textures

All of the following are identical `1024x1024` PNGs at about `2.29 MB` each:

- `assets/models/props/shield/shield_albedo.png`
- `assets/models/props/shield/shield_round_shield_albedo.png`
- `assets/models/props/shield/shield_rectangle_shield_albedo.png`
- `assets/models/props/shield/shield_round_Gemini_Generated_Image_p9aqrip9aqrip9aq.png`
- `assets/models/props/shield/shield_rectangle_Gemini_Generated_Image_p9aqrip9aqrip9aq.png`

Current runtime reference found:

- `assets/models/props/shield/shield_shared_material.tres` -> `shield_albedo.png`

Recommendation:

- keep `shield_albedo.png` as canonical
- consider archiving or removing the other four after confirming they are not needed for future GLB reimport workflow

### Yardarm / sail mast textures

The old mast GLB was re-exported with embedded material colors, so
`assets/models/props/mast/mast_mast_albedo.png` is no longer required.
The remaining duplicated rig textures are identical `1024x1024` PNGs at about `1.68 MB` each:

- `assets/models/props/yardarm/yardarm_mast_albedo.png`
- `assets/models/props/sail/sail_mast_albedo.png`

Recommendation:

- keep one canonical texture and align any source pipeline docs around it
- do not delete immediately unless we confirm the imported GLBs do not rely on file-local names for future reimport

### Cannon albedo textures

These are identical `1024x1024` PNGs at about `1.83 MB` each:

- `assets/models/props/cannon/cannon_albedo.png`
- `assets/models/props/cannon/cannon_cannon_albedo.png`

Recommendation:

- keep `cannon_albedo.png` as canonical
- treat `cannon_cannon_albedo.png` as cleanup candidate after source-pipeline check

### Barrel textures

These are identical `512x512` PNGs at about `477 KB` each:

- `assets/models/props/barrel/barrel_albedo.png`
- `assets/models/props/barrel/barrel_Gemini_Generated_Image_54yscu54yscu54ys.png`

Current runtime reference found:

- `assets/models/props/barrel/barrel_shared_material.tres` -> `barrel_albedo.png`

Recommendation:

- keep `barrel_albedo.png` as canonical
- archive or remove the Gemini-named duplicate after source-pipeline check

## Large runtime-used textures

These files are actually used by runtime scenes or materials.

### Main menu background

- `assets/ui/menu/main_menu_background.png`
- size: `1536x1024`
- source size: about `2.14 MB`
- used by: `scenes/main_menu.tscn`
- import setting: `compress/mode=0`

Recommendation:

- likely safe to reduce to `1280` width or convert to a better-compressed source format
- this is a strong candidate for reduction because it is a mostly static menu background

### Water splash particle textures

- `assets/vfx/particles/water/water_splash_omni.png`
- `assets/vfx/particles/water/water_splash_medium.png`
- size: `640x640`
- source sizes: about `666 KB` and `618 KB`
- import setting: `compress/mode=0`

Recommendation:

- good candidate to reduce to `512x512` or `384x384`
- particle sprites usually tolerate downsizing well
- also worth revisiting compression settings

### Water caustics / foam

- `assets/shaders/caustics/foam.png`
- size: `640x640`
- source size: about `970 KB`
- used by: `resources/materials/water.tres`
- import already uses VRAM compression

Recommendation:

- likely the next best runtime reduction target after menu background and splash particles
- consider lowering source resolution to `512` or `384` if visual tests still look good

## Likely source or preview assets

These do not currently show up as direct runtime references in scenes/resources checked during this audit.

- `assets/models/props/cannon/cannon_material_preview.png` (`2048x1024`, about `1.24 MB`)
- `assets/models/props/cannon/cannon_wood_source.png` (`1024x1024`, about `672 KB`)
- `assets/models/props/cannon/cannon_metal_source.png` (`1024x1024`, about `558 KB`)

Recommendation:

- keep if they are part of the authoring workflow
- otherwise consider moving them into a separate source-art folder or excluding them from shipping builds

## Lower priority / probably fine

These are in use, but they do not stand out as urgent cleanup targets:

- `assets/models/props/sail/horizon_sail.png` (`512x512`, about `450 KB`)
- `assets/models/props/sail/vertical_sail.png` (`512x512`, about `438 KB`)
- `assets/models/props/sail/sail_albedo.png` (`512x620`, about `475 KB`)

## Recommended order

1. Decide canonical filenames for duplicate textures
2. Clean duplicates that are not needed for the GLB/source workflow
3. Compress or resize:
   - `assets/ui/menu/main_menu_background.png`
   - `assets/vfx/particles/water/water_splash_omni.png`
   - `assets/vfx/particles/water/water_splash_medium.png`
   - `assets/shaders/caustics/foam.png`
4. Optionally move authoring-only source textures into a dedicated source-art folder
