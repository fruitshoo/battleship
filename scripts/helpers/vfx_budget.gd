class_name VfxBudget
extends RefCounted

const DISTANCE_BIAS_MULT: float = 1.2

static var _last_frame: int = -1
static var _spawn_counts: Dictionary = {}
static var _budget_scale_frame: int = -1
static var _cached_budget_scale: float = 1.0

static func _refresh_if_needed() -> void:
	var frame := Engine.get_physics_frames()
	if frame == _last_frame:
		return
	_last_frame = frame
	_spawn_counts.clear()

static func allow_spawn(tree: SceneTree, key: String, position: Vector3, max_per_frame: int, max_distance: float = -1.0) -> bool:
	_refresh_if_needed()
	if max_distance > 0.0 and not _is_within_budget_distance(tree, position, max_distance):
		return false
	var effective_max := _get_effective_max_per_frame(max_per_frame)
	var current := int(_spawn_counts.get(key, 0))
	if current >= effective_max:
		return false
	_spawn_counts[key] = current + 1
	return true


static func _get_effective_max_per_frame(max_per_frame: int) -> int:
	var budget_scale := get_budget_scale()
	if budget_scale >= 0.999:
		return max_per_frame
	return maxi(1, int(ceil(float(max_per_frame) * budget_scale)))


static func get_budget_scale() -> float:
	var frame := Engine.get_physics_frames()
	if frame == _budget_scale_frame:
		return _cached_budget_scale
	_budget_scale_frame = frame
	var ship_pressure: float = _pressure_from_count(EntityRegistry.count_ships(), 12, 20)
	var soldier_pressure: float = _pressure_from_count(EntityRegistry.count_soldiers(), 40, 70)
	var projectile_pressure: float = _pressure_from_count(EntityRegistry.count_projectiles(), 20, 50)
	var combined: float = 1.0
	combined -= ship_pressure * 0.18
	combined -= soldier_pressure * 0.12
	combined -= projectile_pressure * 0.22
	_cached_budget_scale = clampf(combined, 0.35, 1.0)
	return _cached_budget_scale


static func get_continuous_effect_scale() -> float:
	return get_budget_scale()


static func _pressure_from_count(count: int, soft_threshold: int, hard_window: int) -> float:
	if count <= soft_threshold:
		return 0.0
	return clampf(float(count - soft_threshold) / maxf(float(hard_window), 1.0), 0.0, 1.0)

static func _is_within_budget_distance(tree: SceneTree, position: Vector3, max_distance: float) -> bool:
	if not is_instance_valid(tree):
		return true
	var adjusted_distance: float = max_distance * DISTANCE_BIAS_MULT
	var camera := tree.root.get_camera_3d()
	if is_instance_valid(camera):
		return camera.global_position.distance_squared_to(position) <= adjusted_distance * adjusted_distance
	var player: Node = EntityRegistry.get_first_ship_by_team("player") as Node
	if player is Node3D:
		return (player as Node3D).global_position.distance_squared_to(position) <= adjusted_distance * adjusted_distance
	return true
