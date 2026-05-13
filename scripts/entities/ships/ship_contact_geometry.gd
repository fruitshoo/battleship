extends RefCounted
class_name ShipContactGeometry


const DEFAULT_BASE_COLLISION_RADIUS := 4.5
const DEFAULT_WIDTH_MULTIPLIER := 1.0
const DEFAULT_LENGTH_MULTIPLIER := 1.0
const DEFAULT_BOARDING_BREAK_DISTANCE := 12.0
const BOARDING_ATTEMPT_DISTANCE_PAD := 2.2
const SEPARATION_BASE_PAD := 0.18
const SEPARATION_PLAYER_PAD := 0.12
const SEPARATION_BOSS_PAD := 0.20
const AUTHORED_DECK_COLLISION_PAD := 0.35

static var _half_extents_cache_frame: int = -1
static var _half_extents_cache: Dictionary = {}


static func get_soft_collision_half_extents(ship: Node) -> Vector2:
	if not is_instance_valid(ship):
		return Vector2(DEFAULT_BASE_COLLISION_RADIUS, DEFAULT_BASE_COLLISION_RADIUS)
	var current_frame := Engine.get_physics_frames()
	if current_frame != _half_extents_cache_frame:
		_half_extents_cache_frame = current_frame
		_half_extents_cache.clear()
	var ship_id := ship.get_instance_id()
	if _half_extents_cache.has(ship_id):
		return _half_extents_cache[ship_id]
	var authored_deck_extents := ShipAuthoringHelper.get_deck_area_half_extents(ship)
	if authored_deck_extents.x > 0.01 and authored_deck_extents.y > 0.01:
		var authored_extents := Vector2(
			authored_deck_extents.x + AUTHORED_DECK_COLLISION_PAD,
			authored_deck_extents.y + AUTHORED_DECK_COLLISION_PAD
		)
		_half_extents_cache[ship_id] = authored_extents
		return authored_extents
	var base_radius := NodeContractHelper.get_base_collision_radius_value(ship)
	var width_mult := NodeContractHelper.get_collision_width_multiplier_value(ship)
	var length_mult := NodeContractHelper.get_collision_length_multiplier_value(ship)
	var fallback_extents := Vector2(
		maxf(0.01, base_radius * width_mult),
		maxf(0.01, base_radius * length_mult)
	)
	_half_extents_cache[ship_id] = fallback_extents
	return fallback_extents


static func get_contact_area_collision_shape(area: Node) -> CollisionShape3D:
	if not is_instance_valid(area):
		return null
	for child in area.get_children():
		if child is CollisionShape3D:
			return child as CollisionShape3D
	return null


static func get_directional_collision_radius(ship: Node3D, world_dir: Vector3) -> float:
	if not is_instance_valid(ship):
		return DEFAULT_BASE_COLLISION_RADIUS
	var dir := world_dir
	dir.y = 0.0
	if dir.length_squared() <= 0.0001:
		var half := get_soft_collision_half_extents(ship)
		return maxf(half.x, half.y)
	dir = dir.normalized()

	var fwd := -ship.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() <= 0.0001:
		fwd = Vector3.FORWARD
	else:
		fwd = fwd.normalized()

	var half_extents := get_soft_collision_half_extents(ship)
	return half_extents.x + (half_extents.y - half_extents.x) * absf(fwd.dot(dir))


static func get_collision_distance_between(ship: Node3D, other: Node3D) -> float:
	if not is_instance_valid(ship) or not is_instance_valid(other):
		return 0.0
	var diff := other.global_position - ship.global_position
	diff.y = 0.0
	var dir := diff.normalized() if diff.length_squared() > 0.0001 else Vector3.FORWARD
	return get_directional_collision_radius(ship, dir) + get_directional_collision_radius(other, -dir)


static func get_separation_padding(ship: Node) -> float:
	if not is_instance_valid(ship):
		return 0.0
	var base_pad := SEPARATION_BASE_PAD
	match ship.name:
		"PlayerShip":
			base_pad = SEPARATION_PLAYER_PAD
		"BossShip":
			base_pad = SEPARATION_BOSS_PAD
	var pad_scale: Variant = ship.get("separation_pad_scale")
	if pad_scale != null:
		base_pad *= float(pad_scale)
	return base_pad


static func get_guard_scale(ship: Node) -> float:
	if not is_instance_valid(ship):
		return 1.0
	match ship.name:
		"EnemyShip", "BossShip":
			return 0.93
		_:
			return 1.0


static func get_boarding_attempt_distance(ship: Node3D, target: Node3D, fallback_break_distance: float = DEFAULT_BOARDING_BREAK_DISTANCE) -> float:
	if not is_instance_valid(ship):
		return 0.0
	var attempt_distance := _get_float_property(ship, "boarding_break_distance", fallback_break_distance)
	if is_instance_valid(target):
		attempt_distance = maxf(attempt_distance, get_collision_distance_between(ship, target) + BOARDING_ATTEMPT_DISTANCE_PAD)
	return maxf(0.0, attempt_distance)


static func _get_float_property(node: Node, property_name: String, fallback: float) -> float:
	if not is_instance_valid(node):
		return fallback
	var value: Variant = node.get(property_name)
	if value == null:
		return fallback
	return float(value)
