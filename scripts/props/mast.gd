@tool
extends Node3D

const MastVisualHelper = preload("res://scripts/props/mast_visual_helper.gd")
const SAIL_SMOKE_SCENE = preload("res://scenes/effects/fire_effect.tscn")
const SAIL_BURN_MASK_A = preload("res://assets/vfx/masks/sail_burn_mask_a.png")
const SAIL_BURN_MASK_B = preload("res://assets/vfx/masks/sail_burn_mask_b.png")

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
		sail_damage = clamp(value, 0.0, 1.0)
		_apply_sail_material_settings()
@export var burn_amount: float = 0.0:
	set(value):
		burn_amount = clamp(value, 0.0, 1.0)
		_apply_sail_material_settings()
		_update_sail_smoke()
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

func _enter_tree() -> void:
	# Apply the instance's exported sail settings as soon as the scene enters the tree,
	# so hull-specific overrides are visible from the first rendered frame.
	_apply_sail_material_settings()

func _ready() -> void:
	_damage_seed = float(get_instance_id() % 997) / 997.0
	_cached_wind_manager = get_node_or_null("/root/WindManager")
	if is_instance_valid(mast_mesh):
		_base_mast_mesh_position = mast_mesh.position
		_base_mast_mesh_scale = mast_mesh.scale
	if is_instance_valid(sail_visual):
		_base_sail_visual_position = sail_visual.position
	if is_instance_valid(yardarm_mesh):
		_base_yardarm_mesh_position = yardarm_mesh.position
		_base_yardarm_mesh_scale = yardarm_mesh.scale
	if is_instance_valid(sail_mesh):
		_base_sail_mesh_position = sail_mesh.position
	if is_instance_valid(flag):
		_base_flag_position = flag.position
	if is_instance_valid(sail_model_root):
		_base_model_root_position = sail_model_root.position
		_base_model_root_scale = sail_model_root.scale
	if is_instance_valid(yardarm_model_root):
		_base_yardarm_model_position = yardarm_model_root.position
		_base_yardarm_model_scale = yardarm_model_root.scale
	if is_instance_valid(mast_model_root):
		_base_mast_model_position = mast_model_root.position
		_base_mast_model_scale = mast_model_root.scale
		_base_mast_model_bounds = _compute_mesh_tree_aabb(mast_model_root)
		_has_mast_model_bounds = _base_mast_model_bounds.size.y > 0.001
	_base_mast_top_y = _get_current_mast_top_y(1.0)
	_apply_mast_geometry()
	_apply_sail_geometry()
	_apply_sail_material_settings()
	_update_sail_smoke()
	_update_sail_wind_visual()

func set_sail_angle(angle: float) -> void:
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
	MastVisualHelper.apply_sail_material_settings(self, SAIL_BURN_MASK_A, SAIL_BURN_MASK_B)

func add_sail_damage(amount: float) -> void:
	sail_damage = clamp(sail_damage + maxf(amount, 0.0), 0.0, 1.0)

func repair_sail_damage(amount: float) -> void:
	sail_damage = clamp(sail_damage - maxf(amount, 0.0), 0.0, 1.0)

func get_sail_damage() -> float:
	return sail_damage

func set_burn_amount(value: float) -> void:
	burn_amount = clamp(value, 0.0, 1.0)

func get_burn_amount() -> float:
	return burn_amount

func _ensure_sail_smoke() -> Node3D:
	return MastVisualHelper.ensure_sail_smoke(self, SAIL_SMOKE_SCENE)

func _update_sail_smoke() -> void:
	MastVisualHelper.update_sail_smoke(self, SAIL_SMOKE_SCENE)

func _update_sail_wind_visual() -> void:
	if not is_instance_valid(sail_visual):
		return
	sail_visual.rotation.y = deg_to_rad(-sail_angle)

	if not is_instance_valid(_cached_wind_manager):
		_cached_wind_manager = get_node_or_null("/root/WindManager")
	if not is_instance_valid(_cached_wind_manager) or not _cached_wind_manager.has_method("get_wind_direction"):
		_apply_wind_strength_to_sails(0.0)
		return

	var wind_dir: Vector2 = _cached_wind_manager.get_wind_direction()
	var sail_fwd := -sail_visual.global_transform.basis.z
	var sail_fwd_2d := Vector2(sail_fwd.x, sail_fwd.z).normalized()
	_current_wind_intake = max(0.0, wind_dir.dot(sail_fwd_2d)) * max_wind_intake
	_apply_wind_strength_to_sails(_current_wind_intake)

func _apply_wind_strength_to_sails(wind_strength_value: float) -> void:
	for mesh in _get_sail_meshes():
		mesh.set_instance_shader_parameter("wind_strength", wind_strength_value)

func _apply_mast_geometry() -> void:
	if is_instance_valid(mast_mesh) and mast_mesh.mesh is CylinderMesh:
		var mast_cylinder := mast_mesh.mesh as CylinderMesh
		var base_bottom_y := _base_mast_mesh_position.y - (mast_cylinder.height * _base_mast_mesh_scale.y * 0.5)
		var new_half_height := mast_cylinder.height * _base_mast_mesh_scale.y * mast_height_scale * 0.5
		mast_mesh.scale = Vector3(
			_base_mast_mesh_scale.x,
			_base_mast_mesh_scale.y * mast_height_scale,
			_base_mast_mesh_scale.z
		)
		mast_mesh.position = _base_mast_mesh_position
		mast_mesh.position.y = base_bottom_y + new_half_height
	if is_instance_valid(mast_model_root):
		mast_model_root.scale = Vector3(
			_base_mast_model_scale.x,
			_base_mast_model_scale.y * mast_height_scale,
			_base_mast_model_scale.z
		)
		mast_model_root.position = _base_mast_model_position
		if _has_mast_model_bounds:
			var base_bottom_y := _base_mast_model_position.y + (_base_mast_model_bounds.position.y * _base_mast_model_scale.y)
			mast_model_root.position.y = base_bottom_y - (_base_mast_model_bounds.position.y * mast_model_root.scale.y)
	var mast_top_delta := _get_current_mast_top_y(mast_height_scale) - _base_mast_top_y
	if is_instance_valid(sail_visual):
		sail_visual.position = _base_sail_visual_position
		sail_visual.position.y += mast_top_delta

func _apply_sail_geometry() -> void:
	var target_size := Vector2(max(sail_size.x, 0.1), max(sail_size.y, 0.1))
	if is_instance_valid(yardarm_mesh):
		yardarm_mesh.position = _base_yardarm_mesh_position + yardarm_offset
		yardarm_mesh.scale = Vector3(
			_base_yardarm_mesh_scale.x * yardarm_scale.x,
			_base_yardarm_mesh_scale.y * yardarm_scale.y,
			_base_yardarm_mesh_scale.z * yardarm_scale.z
		)
	var default_mesh := sail_mesh if is_instance_valid(sail_mesh) else get_node_or_null("SailVisual/SailMesh") as MeshInstance3D
	if is_instance_valid(default_mesh) and default_mesh.mesh is PlaneMesh:
		var plane_mesh := default_mesh.mesh.duplicate() as PlaneMesh
		plane_mesh.size = target_size
		default_mesh.mesh = plane_mesh
		var top_anchor_y := _base_sail_mesh_position.y + (BASE_SAIL_SIZE.y * 0.5)
		default_mesh.position = _base_sail_mesh_position
		default_mesh.position.y = top_anchor_y - (target_size.y * 0.5)
		default_mesh.position += sail_offset
	if is_instance_valid(flag):
		var top_anchor_y := _base_sail_mesh_position.y + (BASE_SAIL_SIZE.y * 0.5)
		var base_flag_offset := _base_flag_position.y - top_anchor_y
		flag.position = _base_flag_position
		flag.position.y = top_anchor_y + base_flag_offset
		flag.position += sail_offset
	var model_root := sail_model_root if is_instance_valid(sail_model_root) else get_node_or_null("SailVisual/sail2") as Node3D
	if is_instance_valid(model_root):
		model_root.scale = Vector3(
			_base_model_root_scale.x * (target_size.x / BASE_SAIL_SIZE.x),
			_base_model_root_scale.y * (target_size.y / BASE_SAIL_SIZE.y),
			_base_model_root_scale.z
		)
		model_root.position = _base_model_root_position
		model_root.position.y -= (target_size.y - BASE_SAIL_SIZE.y) * 0.5
		model_root.position += sail_offset
	var yardarm_root := yardarm_model_root if is_instance_valid(yardarm_model_root) else get_node_or_null("SailVisual/yardarm2") as Node3D
	if is_instance_valid(yardarm_root):
		yardarm_root.position = _base_yardarm_model_position + yardarm_offset
		yardarm_root.scale = Vector3(
			_base_yardarm_model_scale.x * yardarm_scale.x,
			_base_yardarm_model_scale.y * yardarm_scale.y,
			_base_yardarm_model_scale.z * yardarm_scale.z
		)
	for mesh in _get_sail_meshes():
		var mat := _ensure_sail_material(mesh)
		if mat != null:
			_apply_deform_bounds(mesh, mat)

func _get_current_mast_top_y(height_scale: float) -> float:
	if is_instance_valid(mast_mesh) and mast_mesh.mesh is CylinderMesh:
		var mast_cylinder := mast_mesh.mesh as CylinderMesh
		var base_bottom_y := _base_mast_mesh_position.y - (mast_cylinder.height * _base_mast_mesh_scale.y * 0.5)
		return base_bottom_y + (mast_cylinder.height * _base_mast_mesh_scale.y * height_scale)
	if _has_mast_model_bounds:
		var scaled_top := _base_mast_model_position.y + (_base_mast_model_bounds.position.y + _base_mast_model_bounds.size.y) * (_base_mast_model_scale.y * height_scale)
		return scaled_top
	return _base_sail_visual_position.y

func _get_sail_meshes() -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	var default_mesh := sail_mesh if is_instance_valid(sail_mesh) else get_node_or_null("SailVisual/SailMesh") as MeshInstance3D
	if is_instance_valid(default_mesh):
		meshes.append(default_mesh)
	var model_root := sail_model_root if is_instance_valid(sail_model_root) else get_node_or_null("SailVisual/sail2") as Node3D
	if is_instance_valid(model_root):
		var model_mesh := _find_first_mesh_instance(model_root)
		if is_instance_valid(model_mesh):
			meshes.append(model_mesh)
	return meshes

func _find_first_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_first_mesh_instance(child)
		if is_instance_valid(found):
			return found
	return null

func _compute_mesh_tree_aabb(root: Node3D) -> AABB:
	var found_any := false
	var combined := AABB()
	for child in _collect_mesh_instances(root):
		if child.mesh == null:
			continue
		var child_aabb := child.mesh.get_aabb()
		var global_corners := _aabb_corners(child_aabb)
		for i in range(global_corners.size()):
			var local_point := root.to_local(child.to_global(global_corners[i]))
			if not found_any:
				combined = AABB(local_point, Vector3.ZERO)
				found_any = true
			else:
				combined = combined.expand(local_point)
	return combined if found_any else AABB()

func _collect_mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		meshes.append(root as MeshInstance3D)
	for child in root.get_children():
		meshes.append_array(_collect_mesh_instances(child))
	return meshes

func _aabb_corners(aabb: AABB) -> Array[Vector3]:
	var p := aabb.position
	var s := aabb.size
	return [
		p,
		p + Vector3(s.x, 0, 0),
		p + Vector3(0, s.y, 0),
		p + Vector3(0, 0, s.z),
		p + Vector3(s.x, s.y, 0),
		p + Vector3(s.x, 0, s.z),
		p + Vector3(0, s.y, s.z),
		p + s,
	]

func _ensure_sail_material(mesh: MeshInstance3D) -> ShaderMaterial:
	return MastVisualHelper.ensure_sail_material(self, mesh)

func _apply_deform_bounds(mesh: MeshInstance3D, mat: ShaderMaterial) -> void:
	MastVisualHelper.apply_deform_bounds(mesh, mat)
