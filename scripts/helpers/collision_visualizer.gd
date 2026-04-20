@tool
extends Node3D

const DebugDrawBridge = preload("res://scripts/helpers/debug_draw_bridge.gd")
const ShipContactGeometry = preload("res://scripts/entities/ships/ship_contact_geometry.gd")
const NodeContractHelper = preload("res://scripts/helpers/node_contract_helper.gd")

static var runtime_enabled: bool = false
static var runtime_mode: int = 0

@export var show_in_editor: bool = false

const MODE_ALL := 0
const MODE_CONTACT_AREAS := 1
const MODE_SOFT_COLLISION := 2
const MODE_SEPARATION := 3
const MODE_GUARD := 4
const MODE_BOARDING := 5
const MODE_COUNT := 6

func _ready() -> void:
	add_to_group("collision_visualizers")
	_refresh_visibility()
	set_process(true)

func _process(_delta: float) -> void:
	if not Engine.is_editor_hint() and not runtime_enabled:
		_refresh_visibility()
		return
		
	var parent = get_parent()
	if not parent: return
	
	# 부모 함선의 Export 변수 접근
	var r = parent.get("base_collision_radius")
	var w = parent.get("width_multiplier")
	var l = parent.get("length_multiplier")
	
	if r != null and w != null and l != null:
		_refresh_visibility()
		_draw_debug_bounds(parent, float(r), float(w), float(l))

func _refresh_visibility() -> void:
	var visible_now := (Engine.is_editor_hint() and show_in_editor) or (not Engine.is_editor_hint() and runtime_enabled)
	visible = visible_now

static func set_runtime_enabled(enabled: bool) -> void:
	runtime_enabled = enabled
	DebugDrawBridge.set_ship_bounds_debug_enabled(enabled)

static func cycle_runtime_mode() -> int:
	runtime_mode = wrapi(runtime_mode + 1, 0, MODE_COUNT)
	return runtime_mode

func set_visualizer_enabled(enabled: bool) -> void:
	set_runtime_enabled(enabled)
	_refresh_visibility()


func set_visualizer_mode(mode: int) -> void:
	runtime_mode = clampi(mode, MODE_ALL, MODE_BOARDING)
	_refresh_visibility()


func _draw_debug_bounds(parent: Node, base_radius: float, width_mult: float, length_mult: float) -> void:
	if not visible or not (parent is Node3D) or not DebugDrawBridge.can_draw():
		return
	var ship := parent as Node3D
	if _is_mesh_visible(MODE_CONTACT_AREAS):
		_draw_contact_area_box(NodeContractHelper.get_proximity_area(ship), Color(0.35, 0.85, 1.0, 0.82), 1.25, "prox")
		_draw_contact_area_box(NodeContractHelper.get_hit_area(ship), Color(1.0, 0.28, 0.2, 0.86), 1.05, "hit")
	if _is_mesh_visible(MODE_SOFT_COLLISION):
		var half_extents := ShipContactGeometry.get_soft_collision_half_extents(parent)
		DebugDrawBridge.draw_ellipse_xz(
			ship.global_position,
			ship.global_transform.basis,
			half_extents.x,
			half_extents.y,
			Color(1.0, 0.45, 0.05, 0.95),
			0.85,
			0.0,
			72,
			0.036
		)
		DebugDrawBridge.draw_text(ship.global_position + Vector3.UP * 1.45, "soft %.1fx%.1f" % [half_extents.x, half_extents.y], Color(1.0, 0.66, 0.22, 0.92), 0.0, 14)
	if _is_mesh_visible(MODE_SEPARATION):
		var separation_pad := ShipContactGeometry.get_separation_padding(parent)
		DebugDrawBridge.draw_ellipse_xz(
			ship.global_position,
			ship.global_transform.basis,
			base_radius * width_mult + separation_pad,
			base_radius * length_mult + separation_pad,
			Color(1.0, 0.9, 0.2, 0.86),
			1.45,
			0.0,
			72,
			0.032
		)
	var guard_scale := ShipContactGeometry.get_guard_scale(parent)
	if _is_mesh_visible(MODE_GUARD) and guard_scale < 0.999:
		DebugDrawBridge.draw_ellipse_xz(
			ship.global_position,
			ship.global_transform.basis,
			base_radius * width_mult * guard_scale,
			base_radius * length_mult * guard_scale,
			Color(0.45, 0.95, 1.0, 0.9),
			1.85,
			0.0,
			72,
			0.034
		)
	if _is_mesh_visible(MODE_BOARDING):
		_draw_boarding_range(ship)


static func get_mode_name(mode: int) -> String:
	match mode:
		MODE_CONTACT_AREAS:
			return "BOX"
		MODE_SOFT_COLLISION:
			return "SOFT"
		MODE_SEPARATION:
			return "SEPARATION"
		MODE_GUARD:
			return "GUARD"
		MODE_BOARDING:
			return "BOARDING"
		_:
			return "ALL"


func _draw_contact_area_box(area: Area3D, color: Color, label_y_offset: float, label: String) -> void:
	if not is_instance_valid(area):
		return
	var shape_node := ShipContactGeometry.get_contact_area_collision_shape(area)
	if not (shape_node is CollisionShape3D):
		return
	var collision_shape := shape_node as CollisionShape3D
	if not (collision_shape.shape is BoxShape3D):
		return
	var box_shape := collision_shape.shape as BoxShape3D
	DebugDrawBridge.draw_box(collision_shape.global_transform, box_shape.size, color, 0.0, 0.026)
	DebugDrawBridge.draw_text(collision_shape.global_position + Vector3.UP * label_y_offset, label, color, 0.0, 13)


func _draw_boarding_range(ship: Node3D) -> void:
	if not _can_board_for_debug(ship):
		return
	var target := NodeContractHelper.get_target_ship(ship)
	var anchor := ship.global_position
	var attempt_distance := ShipContactGeometry.get_boarding_attempt_distance(ship, target)
	var color := Color(0.28, 1.0, 0.62, 0.78)
	if is_instance_valid(target):
		anchor = target.global_position
		var planar_distance := Vector2(ship.global_position.x - target.global_position.x, ship.global_position.z - target.global_position.z).length()
		if planar_distance > attempt_distance:
			color = Color(1.0, 0.58, 0.16, 0.72)
	DebugDrawBridge.draw_circle_xz(anchor, attempt_distance, color, 1.25, 0.0, 72, 0.028)
	DebugDrawBridge.draw_text(anchor + Vector3.UP * 1.95, "boarding %.1fm" % attempt_distance, color, 0.0, 14)


func _can_board_for_debug(ship: Node) -> bool:
	if not is_instance_valid(ship):
		return false
	if ship.has_method("can_board_targets"):
		return ship.call("can_board_targets") == true
	if "allow_boarding" in ship:
		return ship.get("allow_boarding") == true
	return false

func _is_mesh_visible(mode: int) -> bool:
	return runtime_mode == MODE_ALL or runtime_mode == mode
