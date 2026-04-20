@tool
extends Node3D

const DebugDrawBridge = preload("res://scripts/helpers/debug_draw_bridge.gd")

static var runtime_enabled: bool = false
static var runtime_mode: int = 0

@export var show_in_editor: bool = false

const MODE_ALL := 0
const MODE_BASE := 1
const MODE_SEPARATION := 2
const MODE_GUARD := 3

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
	DebugDrawBridge.set_collision_debug_enabled(enabled)

static func cycle_runtime_mode() -> int:
	runtime_mode = wrapi(runtime_mode + 1, 0, 4)
	return runtime_mode

func set_visualizer_enabled(enabled: bool) -> void:
	set_runtime_enabled(enabled)
	_refresh_visibility()


func set_visualizer_mode(mode: int) -> void:
	runtime_mode = clampi(mode, MODE_ALL, MODE_GUARD)
	_refresh_visibility()


func _draw_debug_bounds(parent: Node, base_radius: float, width_mult: float, length_mult: float) -> void:
	if not visible or not (parent is Node3D) or not DebugDrawBridge.can_draw():
		return
	var ship := parent as Node3D
	if _is_mesh_visible(MODE_BASE):
		DebugDrawBridge.draw_ellipse_xz(
			ship.global_position,
			ship.global_transform.basis,
			base_radius * width_mult,
			base_radius * length_mult,
			Color(1.0, 0.45, 0.05, 0.95),
			0.35,
			0.0,
			72,
			0.036
		)
	if _is_mesh_visible(MODE_SEPARATION):
		var separation_pad := _get_separation_padding(parent)
		DebugDrawBridge.draw_ellipse_xz(
			ship.global_position,
			ship.global_transform.basis,
			base_radius * width_mult + separation_pad,
			base_radius * length_mult + separation_pad,
			Color(1.0, 0.9, 0.2, 0.86),
			1.0,
			0.0,
			72,
			0.032
		)
	var guard_scale := _get_guard_scale(parent)
	if _is_mesh_visible(MODE_GUARD) and guard_scale < 0.999:
		DebugDrawBridge.draw_ellipse_xz(
			ship.global_position,
			ship.global_transform.basis,
			base_radius * width_mult * guard_scale,
			base_radius * length_mult * guard_scale,
			Color(0.45, 0.95, 1.0, 0.9),
			1.65,
			0.0,
			72,
			0.034
		)

func _get_separation_padding(parent: Node) -> float:
	if not is_instance_valid(parent):
		return 0.0
	var base_pad := 0.18
	match parent.name:
		"PlayerShip":
			base_pad = 0.12
		"BossShip":
			base_pad = 0.20
	var pad_scale = parent.get("separation_pad_scale")
	if pad_scale != null:
		base_pad *= float(pad_scale)
	return base_pad

func _get_guard_scale(parent: Node) -> float:
	if not is_instance_valid(parent):
		return 1.0
	match parent.name:
		"EnemyShip":
			return 0.93
		"BossShip":
			return 0.93
		_:
			return 1.0

func _is_mesh_visible(mode: int) -> bool:
	return runtime_mode == MODE_ALL or runtime_mode == mode
