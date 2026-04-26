extends Node3D
class_name WakeTrail3D

const FRAME_COUNT := 64.0
const BASE_FRAME_RATE := 18.0

var _active: bool = false
var _speed_ratio: float = 0.0
var _turn_ratio: float = 0.0
var _turbulence: float = 0.0
var _frame_time: float = 0.0
var _side_materials: Array[ShaderMaterial] = []
var _rear_materials: Array[ShaderMaterial] = []
var _base_scales: Dictionary = {}

@onready var side_wake: MeshInstance3D = get_node_or_null("SideWake")
@onready var rear_wake: MeshInstance3D = get_node_or_null("RearWake")

var emitting: bool:
	get:
		return _active
	set(value):
		set_wake_state(value, _speed_ratio, _turn_ratio, _turbulence)


func _ready() -> void:
	_side_materials = []
	_rear_materials = []
	_prepare_wake_card(side_wake, _side_materials)
	_prepare_wake_card(rear_wake, _rear_materials)
	_set_cards_visible(false)
	set_process(false)


func set_wake_state(active: bool, speed_ratio: float = 0.0, turn_ratio: float = 0.0, turbulence: float = 0.0) -> void:
	_active = active
	_speed_ratio = clampf(speed_ratio, 0.0, 1.0)
	_turn_ratio = clampf(turn_ratio, -1.0, 1.0)
	_turbulence = clampf(turbulence, 0.0, 1.0)
	_set_cards_visible(active)
	set_process(active)
	_apply_visual_state()


func _process(delta: float) -> void:
	var frame_rate := BASE_FRAME_RATE * lerpf(0.65, 1.55, _speed_ratio)
	_frame_time = fmod(_frame_time + delta * frame_rate, FRAME_COUNT)
	_apply_visual_state()


func _prepare_wake_card(card: MeshInstance3D, material_list: Array[ShaderMaterial]) -> void:
	if not is_instance_valid(card):
		return
	_base_scales[card] = card.scale
	var material := card.get_surface_override_material(0) as ShaderMaterial
	if material:
		var unique_material := material.duplicate() as ShaderMaterial
		card.set_surface_override_material(0, unique_material)
		material_list.append(unique_material)
	card.visible = false


func _apply_visual_state() -> void:
	var base_alpha := 0.0
	if _active:
		base_alpha = lerpf(0.2, 0.72, _speed_ratio)
		base_alpha += _turbulence * 0.12
	base_alpha = clampf(base_alpha, 0.0, 0.82)

	var side_alpha := base_alpha * lerpf(0.92, 1.12, absf(_turn_ratio))
	_apply_material(side_wake, _side_materials, 0, side_alpha)
	for material in _rear_materials:
		material.set_shader_parameter("frame", fmod(_frame_time + 11.0, FRAME_COUNT))
		material.set_shader_parameter("alpha", base_alpha * 0.55)

	_apply_scale(side_wake, Vector3(lerpf(0.82, 1.18, _speed_ratio), 1.0, lerpf(0.72, 1.12, _speed_ratio)))
	_apply_scale(rear_wake, Vector3(lerpf(0.72, 1.05, _speed_ratio), 1.0, lerpf(0.62, 1.0, _speed_ratio)))


func _apply_material(card: MeshInstance3D, materials: Array[ShaderMaterial], material_index: int, alpha_value: float) -> void:
	if not is_instance_valid(card) or material_index < 0 or material_index >= materials.size():
		return
	var material := materials[material_index]
	material.set_shader_parameter("frame", _frame_time)
	material.set_shader_parameter("alpha", alpha_value)


func _apply_scale(card: MeshInstance3D, scale_mult: Vector3) -> void:
	if not is_instance_valid(card) or not _base_scales.has(card):
		return
	card.scale = (_base_scales[card] as Vector3) * scale_mult


func _set_cards_visible(visible: bool) -> void:
	if is_instance_valid(side_wake):
		side_wake.visible = visible
	if is_instance_valid(rear_wake):
		rear_wake.visible = visible
