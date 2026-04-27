# Sea Sites

Small points of interest that sit on the sea surface and reward exploration.

Use this folder for runtime scenes such as drifting supplies, small islands,
reefs, temporary bases, wreckage, and other place-like encounters. Keep one
script with the same base name under `scripts/world/sea_sites/`.

Temporary static reward sites:

- `reef_marker_site.tscn`
- `tiny_islet_site.tscn`
- `temporary_outpost_site.tscn`

Static sites now grant small run-scoped `minor_stat_bonus` rewards by default.
Drifting supplies remain recovery-focused so exploration and emergency pickup
keep distinct roles.
