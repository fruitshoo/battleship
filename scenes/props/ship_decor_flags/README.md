# Ship Decor Flags

These scenes are the shared ship flag family for mast-mounted role flags and decorative hull flags. They replace the older `scenes/props/flags` family so flag visuals use one shader, one mask workflow, and one runtime API.

## Obang Set

- `obang_center_hwangryong.tscn`: center command flag
- `obang_left_cheongryong.tscn`: left command flag
- `obang_right_baekho.tscn`: right command flag
- `obang_front_jujak.tscn`: front command flag
- `obang_rear_hyeonmu.tscn`: rear command flag

The source art is stored under `assets/source/ship_decor_flags/obang/`, and game-ready 512x512 textures live under `assets/textures/ship_decor_flags/obang/`.

## Cloth Pinning

Decor flag materials use `pin_mode` in `assets/shaders/ship_decor_flag.gdshader`:

- `0`: left edge pinned, for side-mounted hanging flags.
- `1`: top edge pinned, for crossbar-mounted square flags such as the hwangryong command flag.
- `2`: left and top edges pinned, for stiffer framed cloth.

The wave phase and optional shape mask follow the selected pin mode, so top-pinned flags ripple downward and keep mask cutouts away from the fixed top edge.

Use `free_rotate_with_wind = false` on rigid hull-mounted standards that should stay aligned to the ship. The shader can still provide a small cloth flutter.

`wave_strength` and `side_drag` can be pushed up to `0.8` in the material inspector for exaggerated preview tuning. Values above roughly `0.25` are intentionally dramatic and may clip through rods or rails depending on placement.

## Shape Masks

Set `use_shape_mask = true` and assign `shape_mask_texture` to cut the rectangular cloth into the flag silhouette. White mask pixels remain visible, black pixels are discarded. Prefer masks for every shape instead of shader-side shape enums.

- `assets/textures/ship_decor_flags/masks/old_square_flag_mask_512.png`
- `assets/textures/ship_decor_flags/masks/triangle_flag_mask_512.png`
- `assets/textures/ship_decor_flags/masks/swallowtail_flag_mask_512.png`

Runtime role flags are registered in `scripts/props/flag_scene_library.gd`, but their visual scene is shared:

- `standard_flag.tscn`: common non-Obang mast/menu flag. Player, enemy, boss, and site kinds map here unless a role gets a genuinely distinct visual later.

Fixed emblems belong to each flag scene's `ShaderMaterial`. Keep `emblem_texture`, `emblem_color`, and `emblem_strength` authored in the scene instead of injecting them from script unless a future feature needs runtime customization.

Because the mask removes edge area, shrink emblem art with `emblem_uv_scale` values above `1.0` so the motif stays inside the safe cloth area.
