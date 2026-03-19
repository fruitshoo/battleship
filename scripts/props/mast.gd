@tool
extends Node3D

const MastVisualHelper = preload("res://scripts/props/mast_visual_helper.gd")
const MastGeometryHelper = preload("res://scripts/props/mast_geometry_helper.gd")
const MastWindHelper = preload("res://scripts/props/mast_wind_helper.gd")
const SAIL_SMOKE_SCENE = preload("res://scenes/effects/fire_effect.tscn")
const SAIL_BURN_MASK_A = preload("res://assets/vfx/masks/sail_burn_mask_a.png")
const SAIL_BURN_MASK_B = preload("res://assets/vfx/masks/sail_burn_mask_b.png")
const SAIL_BURN_MASK_C = preload("res://assets/vfx/masks/sail_burn_mask_c.png")

## 돛대 (Mast) 오브젝트
## 자체적으로 돛 각도 회전 및 펄럭임 제어

@export var max_wind_intake: float = 1.0 # 모델별 바람 허용량 조절 가능
@export_group("Sail Material")
@export var use_sail_texture: bool = false:
	set(value):
		use_sail_texture = value
		_apply_sail_material_settings()
@export var sail_texture: Texture2D:
	set(value):
		sail_texture = value
		_apply_sail_material_settings()
@export var swap_sail_uv_axes: bool = false:
	set(value):
		swap_sail_uv_axes = value
		_apply_sail_material_settings()
@export var flip_sail_u: bool = false:
	set(value):
		flip_sail_u = value
		_apply_sail_material_settings()
@export var flip_sail_v: bool = false:
	set(value):
		flip_sail_v = value
		_apply_sail_material_settings()
@export var sail_damage: float = 0.0:
	set(value):
		var target_value: float = clamp(value, 0.0, 1.0)
		if is_equal_approx(sail_damage, target_value):
			return
		sail_damage = target_value
		_apply_sail_material_settings()
@export var burn_amount: float = 0.0:
	set(value):
		var target_value: float = clamp(value, 0.0, 1.0)
		if is_equal_approx(burn_amount, target_value):
			return
		burn_amount = target_value
		_apply_sail_material_settings()
		_update_sail_smoke()
@export var hole_alpha_strength: float = 1.0:
	set(value):
		var target_value: float = clamp(value, 0.0, 2.0)
		if is_equal_approx(hole_alpha_strength, target_value):
			return
		hole_alpha_strength = target_value
		_apply_sail_material_settings()
@export var sail_uv_scale: Vector2 = Vector2.ONE:
	set(value):
		sail_uv_scale = value
		_apply_sail_material_settings()
@export var sail_uv_offset: Vector2 = Vector2.ZERO:
	set(value):
		sail_uv_offset = value
		_apply_sail_material_settings()
@export_group("Mast Geometry")
@export var mast_height_scale: float = 1.0:
	set(value):
		mast_height_scale = max(value, 0.1)
		_apply_mast_geometry()
@export_group("Sail Geometry")
@export var sail_size: Vector2 = Vector2(3.5, 7.0):
	set(value):
		sail_size = Vector2(max(value.x, 0.1), max(value.y, 0.1))
		_apply_sail_geometry()
@export var sail_bottom_width_scale: float = 1.0:
	set(value):
		sail_bottom_width_scale = clamp(value, 0.35, 1.25)
		_apply_sail_material_settings()
@export var sail_offset: Vector3 = Vector3.ZERO:
	set(value):
		sail_offset = value
		_apply_sail_geometry()
@export_group("Yardarm Geometry")
@export var yardarm_scale: Vector3 = Vector3.ONE:
	set(value):
		yardarm_scale = Vector3(max(value.x, 0.01), max(value.y, 0.01), max(value.z, 0.01))
		_apply_sail_geometry()
@export var yardarm_offset: Vector3 = Vector3.ZERO:
	set(value):
		yardarm_offset = value
		_apply_sail_geometry()

@onready var mast_mesh: MeshInstance3D = $MastMesh
@onready var sail_visual: Node3D = $SailVisual
@onready var yardarm_mesh: MeshInstance3D = $SailVisual/Yardarm
@onready var sail_mesh: MeshInstance3D = $SailVisual/SailMesh
@onready var sail_model_root: Node3D = get_node_or_null("SailVisual/sail2") as Node3D
@onready var yardarm_model_root: Node3D = get_node_or_null("SailVisual/yardarm2") as Node3D
@onready var mast_model_root: Node3D = get_node_or_null("mast2") as Node3D
@onready var flag: Node3D = $SailVisual/Flag

var sail_angle: float = 0.0
const BASE_SAIL_SIZE := Vector2(3.5, 7.0)
var _base_mast_mesh_position := Vector3.ZERO
var _base_mast_mesh_scale := Vector3.ONE
var _base_sail_visual_position := Vector3.ZERO
var _base_yardarm_mesh_position := Vector3.ZERO
var _base_yardarm_mesh_scale := Vector3.ONE
var _base_sail_mesh_position := Vector3.ZERO
var _base_flag_position := Vector3.ZERO
var _base_model_root_position := Vector3.ZERO
var _base_model_root_scale := Vector3.ONE
var _base_yardarm_model_position := Vector3.ZERO
var _base_yardarm_model_scale := Vector3.ONE
var _base_mast_model_position := Vector3.ZERO
var _base_mast_model_scale := Vector3.ONE
var _base_mast_model_bounds := AABB()
var _has_mast_model_bounds := false
var _base_mast_top_y := 0.0
var _damage_seed: float = 0.0
var _sail_smoke_instance: Node3D = null
var _cached_wind_manager: Node = null
var _current_wind_intake: float = 0.0
var _last_applied_wind_strength: float = -1.0

func _enter_tree() -> void:
	# Apply the instance's exported sail settings as soon as the scene enters the tree,
	# so hull-specific overrides are visible from the first rendered frame.
	_apply_sail_material_settings()

func _ready() -> void:
	_damage_seed = float(get_instance_id() % 997) / 997.0
	_cached_wind_manager = get_node_or_null("/root/WindManager")
	MastGeometryHelper.capture_base_state(self)
	_apply_mast_geometry()
	_apply_sail_geometry()
	_apply_sail_material_settings()
	_update_sail_smoke()
	_update_sail_wind_visual()

func set_sail_angle(angle: float) -> void:
	if is_equal_approx(sail_angle, angle):
		return
	sail_angle = angle
	_update_sail_wind_visual()

func _process(_delta: float) -> void:
	_update_sail_wind_visual()

func set_team_color(team: String) -> void:
	if flag and flag.has_method("set_team_color"):
		flag.set_team_color(team)

func set_sail_color(color: Color) -> void:
	for mesh in _get_sail_meshes():
		mesh.set_instance_shader_parameter("albedo", color)

func set_sail_texture(texture: Texture2D) -> void:
	sail_texture = texture
	use_sail_texture = texture != null
	_apply_sail_material_settings()

func configure_sail_uv(swap_axes: bool = false, flip_u: bool = false, flip_v: bool = false, uv_scale: Vector2 = Vector2.ONE, uv_offset: Vector2 = Vector2.ZERO) -> void:
	swap_sail_uv_axes = swap_axes
	flip_sail_u = flip_u
	flip_sail_v = flip_v
	sail_uv_scale = uv_scale
	sail_uv_offset = uv_offset
	_apply_sail_material_settings()

func _apply_sail_material_settings() -> void:
	MastVisualHelper.apply_sail_material_settings(self, SAIL_BURN_MASK_A, SAIL_BURN_MASK_B, SAIL_BURN_MASK_C)

func add_sail_damage(amount: float) -> void:
	var target_damage: float = clamp(sail_damage + maxf(amount, 0.0), 0.0, 1.0)
	if is_equal_approx(sail_damage, target_damage):
		return
	sail_damage = target_damage

func repair_sail_damage(amount: float) -> void:
	var target_damage: float = clamp(sail_damage - maxf(amount, 0.0), 0.0, 1.0)
	if is_equal_approx(sail_damage, target_damage):
		return
	sail_damage = target_damage

func get_sail_damage() -> float:
	return sail_damage

func set_burn_amount(value: float) -> void:
	var target_burn: float = clamp(value, 0.0, 1.0)
	if is_equal_approx(burn_amount, target_burn):
		return
	burn_amount = target_burn

func get_burn_amount() -> float:
	return burn_amount

func set_hole_alpha_strength(value: float) -> void:
	var target_strength: float = clamp(value, 0.0, 2.0)
	if is_equal_approx(hole_alpha_strength, target_strength):
		return
	hole_alpha_strength = target_strength

func get_hole_alpha_strength() -> float:
	return hole_alpha_strength

func _ensure_sail_smoke() -> Node3D:
	return MastVisualHelper.ensure_sail_smoke(self, SAIL_SMOKE_SCENE)

func _update_sail_smoke() -> void:
	MastVisualHelper.update_sail_smoke(self, SAIL_SMOKE_SCENE)

func _update_sail_wind_visual() -> void:
	MastWindHelper.update_sail_wind_visual(self)

func _apply_wind_strength_to_sails(wind_strength_value: float) -> void:
	MastWindHelper.apply_wind_strength_to_sails(self, wind_strength_value)

func _apply_mast_geometry() -> void:
	MastGeometryHelper.apply_mast_geometry(self)

func _apply_sail_geometry() -> void:
	MastGeometryHelper.apply_sail_geometry(self)

func _get_current_mast_top_y(height_scale: float) -> float:
	return MastGeometryHelper.get_current_mast_top_y(self, height_scale)

func _get_sail_meshes() -> Array[MeshInstance3D]:
	return MastGeometryHelper.get_sail_meshes(self)

func _find_first_mesh_instance(node: Node) -> MeshInstance3D:
	return MastGeometryHelper.find_first_mesh_instance(node)

func _compute_mesh_tree_aabb(root: Node3D) -> AABB:
	return MastGeometryHelper.compute_mesh_tree_aabb(root)

func _collect_mesh_instances(root: Node) -> Array[MeshInstance3D]:
	return MastGeometryHelper.collect_mesh_instances(root)

func _aabb_corners(aabb: AABB) -> Array[Vector3]:
	return MastGeometryHelper.aabb_corners(aabb)

func _ensure_sail_material(mesh: MeshInstance3D) -> ShaderMaterial:
	return MastVisualHelper.ensure_sail_material(self, mesh)

func _apply_deform_bounds(mesh: MeshInstance3D, mat: ShaderMaterial) -> void:
	MastVisualHelper.apply_deform_bounds(mesh, mat)
