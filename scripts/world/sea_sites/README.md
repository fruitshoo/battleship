# Sea Site Scripts

Runtime logic for sea-surface points of interest.

- `drifting_supply_site.gd`: a small discoverable site that can grant an immediate field reward while bobbing on the water.
- `static_reward_site.gd`: shared logic for stationary places that grant configurable rewards without being absorbed.
- `sea_site_reward_helper.gd`: applies site reward profiles such as minor stat bonuses, upgrade choices, hull repair, crew limit expansion, and crew recovery.
- `sea_site_spawner.gd`: keeps a limited number of sea sites around the player, tuned for roughly 8-12 visible opportunities across a 10-minute run, and prefers crosswind/downwind spawn directions before falling back.

Configured site reward profiles:

- `reef_marker_site.tscn`: minor stat bonus.
- `tiny_islet_site.tscn`: minor stat bonus.
- `temporary_outpost_site.tscn`: minor stat bonus.
- `drifting_supply_site.tscn`: hull repair.
