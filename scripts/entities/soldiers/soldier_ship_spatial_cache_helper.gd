extends RefCounted
class_name SoldierShipSpatialCacheHelper

const SHIP_ENEMY_SCAN_CACHE_FRAME_WINDOW := 2
const SHIP_ENEMY_SCAN_PRUNE_INTERVAL := 30
const SHIP_ENEMY_SCAN_MAX_DISTANCE_SQ := 1600.0
const SHIP_DECK_BUCKET_CACHE_FRAME_WINDOW := 2
const SHIP_DECK_BUCKET_PRUNE_INTERVAL := 30
const SHIP_DECK_BUCKET_CELL_SIZE := 2.4

static var _ship_enemy_scan_cache: Dictionary = {}
static var _ship_enemy_scan_cache_last_prune_frame: int = -1000
static var _ship_deck_bucket_cache: Dictionary = {}
static var _ship_deck_bucket_cache_last_prune_frame: int = -1000


static func get_valid_node3d(value: Variant) -> Node3D:
	if not is_instance_valid(value):
		return null
	var node: Node3D = value as Node3D
	if node == null or not is_instance_valid(node):
		return null
	return node


static func get_ship_enemy_scan_data(soldier) -> Dictionary:
	var owned_ship: Node3D = get_valid_node3d(soldier.owned_ship)
	if owned_ship == null:
		return {}
	if NodeContractHelper.is_sinking_or_dying(owned_ship):
		return {}
	var current_frame: int = Engine.get_physics_frames()
	var cache_key: String = _make_ship_enemy_scan_cache_key(owned_ship, str(soldier.team))
	var cached_variant: Variant = _ship_enemy_scan_cache.get(cache_key, null)
	if typeof(cached_variant) == TYPE_DICTIONARY:
		var cached: Dictionary = cached_variant as Dictionary
		var cached_frame: int = int(cached.get("frame", -1000))
		if current_frame - cached_frame < SHIP_ENEMY_SCAN_CACHE_FRAME_WINDOW:
			return cached
	var rebuilt: Dictionary = _build_ship_enemy_scan_data(soldier, owned_ship, current_frame)
	_ship_enemy_scan_cache[cache_key] = rebuilt
	_prune_ship_enemy_scan_cache(current_frame)
	return rebuilt


static func _build_ship_enemy_scan_data(soldier, owned_ship: Node3D, current_frame: int) -> Dictionary:
	var nearby_enemy_ships: Array = []
	var nearby_ally_distress_ships: Array = []
	var opposing_team: String = "enemy" if soldier.team == "player" else "player"
	for other_ship in EntityRegistry.get_ships_by_team(opposing_team):
		if not is_instance_valid(other_ship) or other_ship == owned_ship:
			continue
		if other_ship.has_method("is_sinking_or_dying") and other_ship.is_sinking_or_dying():
			continue
		var enemy_ship_diff_xz := Vector2(
			owned_ship.global_position.x - other_ship.global_position.x,
			owned_ship.global_position.z - other_ship.global_position.z
		)
		if enemy_ship_diff_xz.length_squared() > SHIP_ENEMY_SCAN_MAX_DISTANCE_SQ:
			continue
		nearby_enemy_ships.append(other_ship)

	var own_team := str(soldier.team).strip_edges().to_lower()
	for ally_ship in EntityRegistry.get_ships_by_team(own_team):
		if not is_instance_valid(ally_ship) or ally_ship == owned_ship:
			continue
		if ally_ship.has_method("is_sinking_or_dying") and ally_ship.is_sinking_or_dying():
			continue
		var ally_ship_diff_xz := Vector2(
			owned_ship.global_position.x - ally_ship.global_position.x,
			owned_ship.global_position.z - ally_ship.global_position.z
		)
		if ally_ship_diff_xz.length_squared() > SHIP_ENEMY_SCAN_MAX_DISTANCE_SQ:
			continue
		var ally_team := NodeContractHelper.get_team_tag(ally_ship, "").strip_edges().to_lower()
		if not ally_team.is_empty() and ally_team != own_team:
			continue
		var hostile_count: int = int(ally_ship.get("deck_hostile_boarder_count")) if ally_ship.get("deck_hostile_boarder_count") != null else 0
		if ally_ship.get("deck_is_contested") != true and ally_ship.get("deck_is_overrun") != true and hostile_count <= 0:
			continue
		nearby_ally_distress_ships.append(ally_ship)

	var nearby_target_ships := nearby_enemy_ships.duplicate()
	nearby_target_ships.append_array(nearby_ally_distress_ships)
	return {
		"frame": current_frame,
		"ship": owned_ship,
		"nearby_enemy_ships": nearby_enemy_ships,
		"nearby_ally_distress_ships": nearby_ally_distress_ships,
		"nearby_target_ships": nearby_target_ships,
}


static func _make_ship_enemy_scan_cache_key(ship: Node3D, team_name: String) -> String:
	return "%d:%s" % [ship.get_instance_id(), team_name.strip_edges().to_lower()]


static func _prune_ship_enemy_scan_cache(current_frame: int) -> void:
	if current_frame - _ship_enemy_scan_cache_last_prune_frame < SHIP_ENEMY_SCAN_PRUNE_INTERVAL:
		return
	_ship_enemy_scan_cache_last_prune_frame = current_frame
	for cache_key in _ship_enemy_scan_cache.keys():
		var entry_variant: Variant = _ship_enemy_scan_cache.get(cache_key, null)
		if typeof(entry_variant) != TYPE_DICTIONARY:
			_ship_enemy_scan_cache.erase(cache_key)
			continue
		var entry: Dictionary = entry_variant as Dictionary
		var cached_ship: Node3D = get_valid_node3d(entry.get("ship", null))
		var cached_frame: int = int(entry.get("frame", -1000))
		if cached_ship == null or current_frame - cached_frame >= SHIP_ENEMY_SCAN_PRUNE_INTERVAL:
			_ship_enemy_scan_cache.erase(cache_key)


static func resolve_ship_deck_half_extents(_soldier, ship: Node3D) -> Vector2:
	if is_instance_valid(ship) and ship.has_method("get_deck_half_extents"):
		var ext: Variant = ship.call("get_deck_half_extents")
		if ext is Vector2 and ext.x > 0.01 and ext.y > 0.01:
			return ext

	var radius: float = ship.get("base_collision_radius") if "base_collision_radius" in ship else 4.5
	var w_mult: float = ship.get("width_multiplier") if "width_multiplier" in ship else 1.0
	var l_mult: float = ship.get("length_multiplier") if "length_multiplier" in ship else 1.0
	return Vector2(
		maxf(0.4, radius * w_mult * 0.85),
		maxf(0.8, radius * l_mult * 0.85)
	)


static func get_ship_deck_bucket_candidates(ship: Node3D, team_name: String, local_center: Vector3, radius: float) -> Array:
	var bucket_data: Dictionary = _get_ship_deck_bucket_data(ship)
	if bucket_data.is_empty():
		return []
	var normalized_team: String = team_name.strip_edges().to_lower()
	if _does_radius_cover_ship_deck(ship, local_center, radius):
		var soldiers_by_team_variant: Variant = bucket_data.get("soldiers_by_team", {})
		if typeof(soldiers_by_team_variant) == TYPE_DICTIONARY:
			var soldiers_by_team: Dictionary = soldiers_by_team_variant as Dictionary
			var soldiers: Array = soldiers_by_team.get(normalized_team, [])
			if not soldiers.is_empty():
				return soldiers
	var buckets_variant: Variant = bucket_data.get("buckets_by_team", {})
	if typeof(buckets_variant) != TYPE_DICTIONARY:
		return []
	var buckets_by_team: Dictionary = buckets_variant as Dictionary
	var team_bucket_variant: Variant = buckets_by_team.get(normalized_team, {})
	if typeof(team_bucket_variant) != TYPE_DICTIONARY:
		return []
	var team_buckets: Dictionary = team_bucket_variant as Dictionary
	var cell_size: float = float(bucket_data.get("cell_size", SHIP_DECK_BUCKET_CELL_SIZE))
	var center_cell: Vector2i = _get_ship_deck_bucket_cell(local_center, cell_size)
	var cell_radius: int = maxi(0, int(ceil(maxf(radius, 0.01) / maxf(cell_size, 0.01))))
	var candidates: Array = []
	for x in range(center_cell.x - cell_radius, center_cell.x + cell_radius + 1):
		for y in range(center_cell.y - cell_radius, center_cell.y + cell_radius + 1):
			var bucket: Array = team_buckets.get(Vector2i(x, y), [])
			if bucket.is_empty():
				continue
			candidates.append_array(bucket)
	return candidates


static func _does_radius_cover_ship_deck(ship: Node3D, local_center: Vector3, radius: float) -> bool:
	if not is_instance_valid(ship):
		return false
	var half_ext := resolve_ship_deck_half_extents(null, ship)
	var farthest_x: float = absf(local_center.x) + half_ext.x
	var farthest_z: float = absf(local_center.z) + half_ext.y
	var required_radius_sq: float = farthest_x * farthest_x + farthest_z * farthest_z
	return radius * radius >= required_radius_sq


static func _get_ship_deck_bucket_data(ship: Node3D) -> Dictionary:
	if not is_instance_valid(ship):
		return {}
	if NodeContractHelper.is_sinking_or_dying(ship):
		return {}
	var current_frame: int = Engine.get_physics_frames()
	var cache_key: int = ship.get_instance_id()
	var cached_variant: Variant = _ship_deck_bucket_cache.get(cache_key, null)
	if typeof(cached_variant) == TYPE_DICTIONARY:
		var cached: Dictionary = cached_variant as Dictionary
		var cached_frame: int = int(cached.get("frame", -1000))
		if current_frame - cached_frame < SHIP_DECK_BUCKET_CACHE_FRAME_WINDOW:
			return cached
	var rebuilt: Dictionary = _build_ship_deck_bucket_data(ship, current_frame)
	_ship_deck_bucket_cache[cache_key] = rebuilt
	_prune_ship_deck_bucket_cache(current_frame)
	return rebuilt


static func _build_ship_deck_bucket_data(ship: Node3D, current_frame: int) -> Dictionary:
	var buckets_by_team: Dictionary = {}
	var soldiers_by_team: Dictionary = {}
	for soldier in EntityRegistry.get_soldiers_by_ship(ship):
		if not is_instance_valid(soldier):
			continue
		if SoldierStateHelper.is_dead_soldier(soldier):
			continue
		var team_name: String = soldier.get_team_tag() if soldier.has_method("get_team_tag") else str(soldier.get("team"))
		team_name = team_name.strip_edges().to_lower()
		if team_name.is_empty():
			continue
		var soldiers_variant: Variant = soldiers_by_team.get(team_name, [])
		var team_soldiers: Array = soldiers_variant as Array if typeof(soldiers_variant) == TYPE_ARRAY else []
		team_soldiers.append(soldier)
		soldiers_by_team[team_name] = team_soldiers

		var team_bucket_variant: Variant = buckets_by_team.get(team_name, {})
		var team_buckets: Dictionary = team_bucket_variant as Dictionary if typeof(team_bucket_variant) == TYPE_DICTIONARY else {}
		var local_pos: Vector3 = ship.to_local(soldier.global_position)
		var cell: Vector2i = _get_ship_deck_bucket_cell(local_pos, SHIP_DECK_BUCKET_CELL_SIZE)
		var bucket: Array = team_buckets.get(cell, [])
		bucket.append(soldier)
		team_buckets[cell] = bucket
		buckets_by_team[team_name] = team_buckets
	return {
		"frame": current_frame,
		"ship": ship,
		"cell_size": SHIP_DECK_BUCKET_CELL_SIZE,
		"buckets_by_team": buckets_by_team,
		"soldiers_by_team": soldiers_by_team,
	}


static func _get_ship_deck_bucket_cell(local_pos: Vector3, cell_size: float) -> Vector2i:
	var safe_cell_size: float = maxf(cell_size, 0.01)
	return Vector2i(
		floori(local_pos.x / safe_cell_size),
		floori(local_pos.z / safe_cell_size)
	)


static func _prune_ship_deck_bucket_cache(current_frame: int) -> void:
	if current_frame - _ship_deck_bucket_cache_last_prune_frame < SHIP_DECK_BUCKET_PRUNE_INTERVAL:
		return
	_ship_deck_bucket_cache_last_prune_frame = current_frame
	for cache_key in _ship_deck_bucket_cache.keys():
		var entry_variant: Variant = _ship_deck_bucket_cache.get(cache_key, null)
		if typeof(entry_variant) != TYPE_DICTIONARY:
			_ship_deck_bucket_cache.erase(cache_key)
			continue
		var entry: Dictionary = entry_variant as Dictionary
		var cached_ship: Node3D = get_valid_node3d(entry.get("ship", null))
		var cached_frame: int = int(entry.get("frame", -1000))
		if cached_ship == null or current_frame - cached_frame >= SHIP_DECK_BUCKET_PRUNE_INTERVAL:
			_ship_deck_bucket_cache.erase(cache_key)
