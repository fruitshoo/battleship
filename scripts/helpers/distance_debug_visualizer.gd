@tool
extends Node3D

const DebugDrawBridge = preload("res://scripts/helpers/debug_draw_bridge.gd")
const EntityRegistry = preload("res://scripts/helpers/entity_registry.gd")
const NodeContractHelper = preload("res://scripts/helpers/node_contract_helper.gd")

static var runtime_enabled: bool = false
var tracked_ship: Node3D = null

const RING_RADII: Array[float] = [2.0, 4.0, 6.0, 8.0, 10.0]
const RING_COLORS: Array[Color] = [
	Color(0.46, 0.95, 1.0, 0.16),
	Color(0.46, 0.95, 1.0, 0.16),
	Color(0.95, 0.88, 0.28, 0.18),
	Color(0.95, 0.64, 0.24, 0.18),
	Color(1.0, 0.36, 0.24, 0.2),
]

var _pulse_time: float = 0.0
var _cached_cannon_range: float = 0.0
var _cannon_range_refresh_left: float = 0.0

func _ready() -> void:
	add_to_group("distance_debug_visualizers")
	top_level = true
	_sync_world_transform()
	_refresh_visibility()
	set_process(true)


func _process(delta: float) -> void:
	_sync_world_transform()
	_update_cannon_range(delta)
	_update_pulse_animation(delta)
	_refresh_visibility()
	if _is_draw_active():
		_draw_distance_debug()


func _update_pulse_animation(delta: float) -> void:
	if not runtime_enabled and not Engine.is_editor_hint():
		return
	_pulse_time += delta * 2.0


static func set_runtime_enabled(enabled: bool) -> void:
	runtime_enabled = enabled


func _refresh_visibility() -> void:
	var visible_now: bool = Engine.is_editor_hint() or runtime_enabled
	visible = visible_now


func _sync_world_transform() -> void:
	var target_ship: Node3D = tracked_ship
	if not is_instance_valid(target_ship):
		target_ship = get_parent_node_3d()
	if not is_instance_valid(target_ship):
		return
	var anchor_pos := target_ship.global_position
	global_transform = Transform3D(Basis.IDENTITY, Vector3(anchor_pos.x, anchor_pos.y, anchor_pos.z))


func _update_cannon_range(delta: float) -> void:
	_cannon_range_refresh_left = maxf(0.0, _cannon_range_refresh_left - delta)
	if _cannon_range_refresh_left > 0.0:
		return
	_cannon_range_refresh_left = 0.35
	var owner_ship := get_parent_node_3d()
	if not is_instance_valid(owner_ship):
		owner_ship = tracked_ship
	if not is_instance_valid(owner_ship):
		_cached_cannon_range = 0.0
		return
	_cached_cannon_range = _get_owner_cannon_range(owner_ship)


func _draw_distance_debug() -> void:
	var target_ship := _resolve_target_ship()
	if not is_instance_valid(target_ship):
		return
	var anchor := target_ship.global_position
	var pulse_val := (sin(_pulse_time) + 1.0) * 0.5
	for index in range(RING_RADII.size()):
		var color := RING_COLORS[index]
		color.a = lerpf(0.42, 0.8, pulse_val) if index < 2 else lerpf(0.5, 0.9, pulse_val)
		DebugDrawBridge.draw_circle_xz(anchor, RING_RADII[index], color, 0.92 + float(index) * 0.1, 0.0, 64, 0.026)
	if _cached_cannon_range > 0.01:
		DebugDrawBridge.draw_circle_xz(anchor, _cached_cannon_range, Color(1.0, 0.93, 0.54, 0.9), 0.86, 0.0, 96, 0.038)
	_draw_nearest_target_line(target_ship, _cached_cannon_range)


func _draw_nearest_target_line(owner_ship: Node3D, cannon_range: float) -> void:
	var nearest := _find_nearest_enemy_ship(owner_ship)
	if not is_instance_valid(nearest):
		return
	var planar_distance := Vector2(
		nearest.global_position.x - owner_ship.global_position.x,
		nearest.global_position.z - owner_ship.global_position.z
	).length()
	var color := Color(0.42, 1.0, 0.42, 0.9) if cannon_range > 0.01 and planar_distance <= cannon_range else Color(0.72, 0.72, 0.72, 0.72)
	if planar_distance <= 2.0:
		color = Color(1.0, 0.25, 0.15, 0.95)
	DebugDrawBridge.draw_line_raised(owner_ship.global_position, nearest.global_position, 1.35, color, 0.0, 0.035)
	DebugDrawBridge.draw_marker(nearest.global_position, color, "%.1fm" % planar_distance, 0.0, 0.22, 1.65)


func _resolve_target_ship() -> Node3D:
	var target_ship: Node3D = tracked_ship
	if not is_instance_valid(target_ship):
		target_ship = get_parent_node_3d()
	return target_ship


func _is_draw_active() -> bool:
	return (Engine.is_editor_hint() or runtime_enabled) and DebugDrawBridge.can_draw()


func _find_nearest_enemy_ship(owner_ship: Node3D) -> Node3D:
	var owner_team := NodeContractHelper.get_team_tag(owner_ship)
	var candidates: Array = EntityRegistry.get_ships()
	var nearest_ship: Node3D = null
	var nearest_distance_sq := INF
	for ship in candidates:
		if not (ship is Node3D):
			continue
		var ship_3d := ship as Node3D
		if ship_3d == owner_ship or not is_instance_valid(ship_3d):
			continue
		if NodeContractHelper.get_team_tag(ship_3d) == owner_team:
			continue
		if NodeContractHelper.is_sinking_or_dying(ship_3d):
			continue
		var delta := Vector2(ship_3d.global_position.x - owner_ship.global_position.x, ship_3d.global_position.z - owner_ship.global_position.z)
		var dist_sq := delta.length_squared()
		if dist_sq < nearest_distance_sq:
			nearest_distance_sq = dist_sq
			nearest_ship = ship_3d
	return nearest_ship


func _get_owner_cannon_range(owner_ship: Node) -> float:
	var max_range: float = 0.0
	var stack: Array[Node] = [owner_ship]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if not is_instance_valid(node):
			continue
		if node.has_method("_get_current_range"):
			max_range = maxf(max_range, float(node.call("_get_current_range")))
		for child in node.get_children():
			if child is Node:
				stack.append(child)
	return max_range
