@tool
extends Node3D

const MastVisualHelper = preload("res://scripts/props/mast_visual_helper.gd")
const MastGeometryHelper = preload("res://scripts/props/mast_geometry_helper.gd")
const MastWindHelper = preload("res://scripts/props/mast_wind_helper.gd")
const FlagSceneLibrary = preload("res://scripts/props/flag_scene_library.gd")
const SAIL_SMOKE_SCENE = preload("res://scenes/effects/fire_effect.tscn")
const SAIL_BURN_MASK_C = preload("res://assets/vfx/masks/sail_burn_mask_c.png")

## 돛대 (Mast) 오브젝트
## 자체적으로 돛 각도 회전 및 펄럭임 제어

@export var max_wind_intake: float = 1.0 # 모델별 바람 허용량 조절 가능
@export_group("Flag")
@export var flag_scene_override: PackedScene:
	set(value):
		flag_scene_override = value
		if is_inside_tree() and value != null:
			_replace_flag_scene(value)
@export var flag_texture_override: Texture2D:
	set(value):
		flag_texture_override = value
		if is_inside_tree():
			_apply_flag_texture_override()

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
@export_range(1.0, 20.0, 0.5) var sail_view_fade_speed: float = 7.5
# Geometry is edited directly in the scene tree now.
# Keep these as plain runtime fields so older code paths remain harmless,
# but do not expose them in the inspector.
var mast_height_scale: float = 1.0
var sail_size: Vector2 = Vector2(3.5, 7.0)
var sail_mesh_offset: Vector3 = Vector3.ZERO
var sail_bottom_width_scale: float = 1.0
var sail_offset: Vector3 = Vector3.ZERO
var yardarm_scale: Vector3 = Vector3.ONE
var yardarm_offset: Vector3 = Vector3.ZERO
var flag_offset: Vector3 = Vector3.ZERO

@onready var mast_mesh: MeshInstance3D = $MastMesh
@onready var sail_visual: Node3D = $SailVisual
@onready var sail_mesh: MeshInstance3D = $SailVisual/SailMesh
# Optional dormant reference roots kept only if we temporarily park imported meshes
# under the mast scene while tuning proportions.
@onready var sail_model_root: Node3D = get_node_or_null("SailVisual/sail_model") as Node3D
@onready var yardarm_model_root: Node3D = get_node_or_null("SailVisual/yardarm") as Node3D
@onready var mast_model_root: Node3D = get_node_or_null("mast_model") as Node3D
@onready var flag: Node3D = $SailVisual/Flag

var sail_angle: float = 0.0
const BASE_SAIL_SIZE := Vector2(3.5, 7.0)
var _base_mast_mesh_position := Vector3.ZERO
var _base_mast_mesh_scale := Vector3.ONE
var _base_sail_visual_position := Vector3.ZERO
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
var _last_applied_flutter_strength: float = -1.0
var _sail_view_fade_alpha: float = 1.0
var _sail_view_fade_target_alpha: float = 1.0

func _enter_tree() -> void:
	# Apply the instance's exported sail settings as soon as the scene enters the tree,
	# so hull-specific overrides are visible from the first rendered frame.
	_apply_sail_material_settings()

func _ready() -> void:
	_damage_seed = float(get_instance_id() % 997) / 997.0
	_cached_wind_manager = get_node_or_null("/root/WindManager")
	_apply_flag_scene_override()
	MastGeometryHelper.capture_base_state(self)
	_apply_mast_geometry()
	_apply_sail_geometry()
	_apply_sail_material_settings()
	if Engine.is_editor_hint():
		return
	_update_sail_smoke()
	_update_sail_wind_visual()

func set_sail_angle(angle: float) -> void:
	if is_equal_approx(sail_angle, angle):
		return
	sail_angle = angle
	if Engine.is_editor_hint():
		return
	_update_sail_wind_visual()

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_update_sail_wind_visual()
	_update_sail_view_fade(delta)

func set_team_color(team: String) -> void:
	set_flag_kind(FlagSceneLibrary.get_team_kind(team))

func set_flag_kind(kind: String, texture: Texture2D = null) -> void:
	var normalized_kind := FlagSceneLibrary.normalize_kind(kind)
	var scene_path := FlagSceneLibrary.get_scene_path(normalized_kind)
	if not scene_path.is_empty():
		var scene := load(scene_path) as PackedScene
		if scene != null and _replace_flag_scene(scene):
			if texture != null:
				set_flag_texture(texture)
			elif flag_texture_override != null:
				_apply_flag_texture_override()
			_apply_flag_kind_to_active_flag(normalized_kind)
			return
	if is_instance_valid(flag):
		_apply_flag_kind_to_active_flag(normalized_kind)
		if texture != null:
			set_flag_texture(texture)

func set_flag_scene(scene: PackedScene, texture: Texture2D = null) -> void:
	flag_scene_override = scene
	if texture != null:
		set_flag_texture(texture)

func set_flag_texture(texture: Texture2D) -> void:
	flag_texture_override = texture

func get_flag_node() -> Node3D:
	if is_instance_valid(flag):
		return flag
	return get_node_or_null("SailVisual/Flag") as Node3D

func get_flag_shape_name() -> String:
	var active_flag := get_flag_node()
	if is_instance_valid(active_flag) and active_flag.has_method("get_flag_shape_name"):
		return str(active_flag.call("get_flag_shape_name"))
	return ""

func _apply_flag_scene_override() -> void:
	if flag_scene_override != null:
		_replace_flag_scene(flag_scene_override)
	elif not is_instance_valid(flag):
		flag = get_node_or_null("SailVisual/Flag") as Node3D

func _replace_flag_scene(scene: PackedScene) -> bool:
	if scene == null or not is_instance_valid(sail_visual):
		return false
	var old_transform := Transform3D.IDENTITY
	if is_instance_valid(flag):
		old_transform = flag.transform
		if flag.get_parent() == sail_visual:
			sail_visual.remove_child(flag)
		flag.queue_free()
	var new_flag := scene.instantiate() as Node3D
	if new_flag == null:
		return false
	new_flag.name = "Flag"
	new_flag.transform = old_transform
	sail_visual.add_child(new_flag)
	if Engine.is_editor_hint():
		var edited_root := get_tree().edited_scene_root if get_tree() else null
		if edited_root != null:
			new_flag.owner = edited_root
	flag = new_flag
	if flag_texture_override != null:
		_apply_flag_texture_override()
	return true

func _apply_flag_texture_override() -> void:
	if not is_instance_valid(flag):
		return
	if flag.has_method("set_flag_texture"):
		flag.call("set_flag_texture", flag_texture_override)

func _apply_flag_kind_to_active_flag(kind: String) -> void:
	if is_instance_valid(flag) and flag.has_method("set_flag_kind"):
		flag.call("set_flag_kind", kind)

func set_sail_color(color: Color) -> void:
	for mesh in _get_sail_meshes():
		mesh.set_instance_shader_parameter("albedo", color)

func set_sail_view_fade_alpha(alpha: float) -> void:
	var target_alpha: float = clampf(alpha, 0.0, 1.0)
	_sail_view_fade_target_alpha = target_alpha

func _update_sail_view_fade(delta: float) -> void:
	if is_equal_approx(_sail_view_fade_alpha, _sail_view_fade_target_alpha):
		return
	_sail_view_fade_alpha = lerpf(
		_sail_view_fade_alpha,
		_sail_view_fade_target_alpha,
		clampf(sail_view_fade_speed * delta, 0.0, 1.0)
	)
	if absf(_sail_view_fade_alpha - _sail_view_fade_target_alpha) <= 0.01:
		_sail_view_fade_alpha = _sail_view_fade_target_alpha
	for mesh in _get_sail_meshes():
		mesh.set_instance_shader_parameter("view_fade_alpha", _sail_view_fade_alpha)

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
	MastVisualHelper.apply_sail_material_settings(self, SAIL_BURN_MASK_C)

func add_sail_damage(amount: float) -> void:
	var target_damage: float = clamp(sail_damage + maxf(amount, 0.0), 0.0, 1.0)
	if is_equal_approx(sail_damage, target_damage):
		return
	sail_damage = target_damage
	_apply_sail_material_settings()

func repair_sail_damage(amount: float) -> void:
	var target_damage: float = clamp(sail_damage - maxf(amount, 0.0), 0.0, 1.0)
	if is_equal_approx(sail_damage, target_damage):
		return
	sail_damage = target_damage
	_apply_sail_material_settings()

func get_sail_damage() -> float:
	return sail_damage

func set_sail_damage(value: float) -> void:
	var target_damage: float = clamp(value, 0.0, 1.0)
	if is_equal_approx(sail_damage, target_damage):
		return
	sail_damage = target_damage
	_apply_sail_material_settings()

func set_burn_amount(value: float) -> void:
	var target_burn: float = clamp(value, 0.0, 1.0)
	if is_equal_approx(burn_amount, target_burn):
		return
	burn_amount = target_burn
	_apply_sail_material_settings()
	_update_sail_smoke()

func get_burn_amount() -> float:
	return burn_amount

func set_hole_alpha_strength(value: float) -> void:
	var target_strength: float = clamp(value, 0.0, 2.0)
	if is_equal_approx(hole_alpha_strength, target_strength):
		return
	hole_alpha_strength = target_strength
	_apply_sail_material_settings()

func get_hole_alpha_strength() -> float:
	return hole_alpha_strength

func _ensure_sail_smoke() -> Node3D:
	return MastVisualHelper.ensure_sail_smoke(self, SAIL_SMOKE_SCENE)

func _update_sail_smoke() -> void:
	if Engine.is_editor_hint():
		return
	MastVisualHelper.update_sail_smoke(self, SAIL_SMOKE_SCENE)

func _update_sail_wind_visual() -> void:
	if Engine.is_editor_hint():
		return
	MastWindHelper.update_sail_wind_visual(self)

func _apply_wind_strength_to_sails(wind_strength_value: float) -> void:
	MastWindHelper.apply_wind_strength_to_sails(self, wind_strength_value)

func _apply_sail_flutter_to_sails(flutter_strength_value: float) -> void:
	MastWindHelper.apply_sail_flutter_to_sails(self, flutter_strength_value)

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
