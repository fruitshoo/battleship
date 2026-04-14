# Sea Site Scripts

Runtime logic for sea-surface points of interest.

- `drifting_supply_site.gd`: a small discoverable site that opens bonus upgrade choices.
- `static_reward_site.gd`: shared logic for stationary places that open reward choices without being absorbed.
- `sea_site_spawner.gd`: keeps a limited number of sea sites around the player and prefers crosswind/downwind spawn directions before falling back.

Future site scripts can cover reefs, small islands, temporary bases, wreckage,
or other place-like encounters.
