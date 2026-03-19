class_name VfxBudget
extends RefCounted

const SceneGroupCache = preload("res://scripts/helpers/scene_group_cache.gd")
const DISTANCE_BIAS_MULT: float = 1.2

static var _last_frame: int = -1
static var _spawn_counts: Dictionary = {}

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
	var current := int(_spawn_counts.get(key, 0))
	if current >= max_per_frame:
		return false
	_spawn_counts[key] = current + 1
	return true

static func _is_within_budget_distance(tree: SceneTree, position: Vector3, max_distance: float) -> bool:
	if not is_instance_valid(tree):
		return true
	var adjusted_distance: float = max_distance * DISTANCE_BIAS_MULT
	var camera := tree.root.get_camera_3d()
	if is_instance_valid(camera):
		return camera.global_position.distance_squared_to(position) <= adjusted_distance * adjusted_distance
	var player: Node = SceneGroupCache.get_first(tree, "player") as Node
	if player is Node3D:
		return (player as Node3D).global_position.distance_squared_to(position) <= adjusted_distance * adjusted_distance
	return true
