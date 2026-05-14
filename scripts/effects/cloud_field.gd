@tool
extends Node3D

const CLOUD_TEXTURE_VARIANTS := [
	{
		"texture": preload("res://assets/vfx/cloud_puff_preview_01.png"),
	},
	{
		"texture": preload("res://assets/vfx/cloud_puff_preview_02.png"),
	},
	{
		"texture": preload("res://assets/vfx/cloud_puff_preview_03.png"),
	},
]

@export var target_path: NodePath = NodePath("../PlayerShip")
@export_range(1, 8, 1) var cloud_count: int = 4
@export_range(12.0, 42.0, 0.5, "suffix:m") var cloud_altitude: float = 24.0
@export_range(20.0, 120.0, 1.0, "suffix:m") var spawn_radius_min: float = 36.0
@export_range(40.0, 180.0, 1.0, "suffix:m") var spawn_radius_max: float = 92.0
@export_range(70.0, 220.0, 1.0, "suffix:m") var recycle_radius: float = 125.0
@export_range(0.2, 5.0, 0.05, "suffix:m/s") var drift_speed: float = 0.75
@export_range(4.0, 48.0, 0.5, "suffix:m") var cloud_size_min: float = 8.0
@export_range(4.0, 64.0, 0.5, "suffix:m") var cloud_size_max: float = 16.0
@export_range(0.0, 1.0, 0.01) var cloud_alpha: float = 0.42
@export var cloud_tint: Color = Color(0.94, 0.96, 0.97, 1.0)
@export_group("Editor Preview")
@export var preview_in_editor: bool = true
@export var preview_anchor: Vector3 = Vector3.ZERO

var _clouds: Array[Node3D] = []
var _target: Node3D = null


func _ready() -> void:
	_clear_clouds()
	if DisplayServer.get_name() == "headless":
		set_process(false)
		visible = false
		return
	if Engine.is_editor_hint():
		set_process(false)
		visible = preview_in_editor
		if preview_in_editor:
			_rebuild_clouds(true)
		return
	_target = get_node_or_null(target_path) as Node3D
	_rebuild_clouds(true)


func _exit_tree() -> void:
	_clear_clouds()


func _rebuild_clouds(initial: bool) -> void:
	_clear_clouds()
	for i in range(maxi(cloud_count, 0)):
		var cloud := _create_cloud(i)
		add_child(cloud)
		_clouds.append(cloud)
		_place_cloud(cloud, initial)


func _clear_clouds() -> void:
	for cloud in _clouds:
		if is_instance_valid(cloud):
			if cloud.get_parent() == self:
				remove_child(cloud)
			cloud.free()
	_clouds.clear()
	for child in get_children():
		if child is MeshInstance3D and child.has_meta("cloud_field_generated"):
			remove_child(child)
			child.free()


func _process(delta: float) -> void:
	if _clouds.is_empty():
		return
	if not is_instance_valid(_target):
		_target = get_node_or_null(target_path) as Node3D
	var center := _get_follow_center()
	var drift := _get_wind_direction_flat() * drift_speed * _get_wind_strength() * delta
	for cloud in _clouds:
		if not is_instance_valid(cloud):
			continue
		cloud.global_position += drift
		var flat_offset := cloud.global_position - center
		flat_offset.y = 0.0
		if flat_offset.length() > recycle_radius:
			_place_cloud(cloud, false)


func _create_cloud(index: int) -> Node3D:
	var cluster := Node3D.new()
	cluster.name = "CloudCluster%02d" % index
	cluster.set_meta("cloud_field_generated", true)
	var puff_count := randi_range(2, 3)
	var spread := randf_range(cloud_size_min * 0.34, cloud_size_max * 0.48)
	for puff_index in range(puff_count):
		var puff := _create_cloud_puff(index, puff_index)
		var side_offset := (float(puff_index) - float(puff_count - 1) * 0.5) * spread
		puff.position = Vector3(side_offset + randf_range(-spread * 0.18, spread * 0.18), randf_range(-1.4, 1.4), randf_range(-1.6, 1.6))
		cluster.add_child(puff)
	return cluster


func _create_cloud_puff(index: int, puff_index: int) -> MeshInstance3D:
	var puff := MeshInstance3D.new()
	puff.name = "Puff%02d_%02d" % [index, puff_index]
	puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var variant: Dictionary = CLOUD_TEXTURE_VARIANTS.pick_random()
	var texture := variant.get("texture") as Texture2D
	var size := randf_range(cloud_size_min * 0.72, maxf(cloud_size_min, cloud_size_max))
	var quad := QuadMesh.new()
	quad.size = Vector2(size * randf_range(0.9, 1.24), size * randf_range(0.82, 1.08))
	puff.mesh = quad

	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.albedo_texture = texture
	material.albedo_color = Color(cloud_tint.r, cloud_tint.g, cloud_tint.b, cloud_alpha * randf_range(0.58, 1.02))
	material.render_priority = 4
	puff.material_override = material
	return puff


func _place_cloud(cloud: Node3D, initial: bool) -> void:
	var center := _get_follow_center()
	var wind := _get_wind_direction_flat()
	var tangent := Vector3(-wind.z, 0.0, wind.x)
	var offset: Vector3
	if initial:
		var angle := randf_range(0.0, TAU)
		var radius := randf_range(spawn_radius_min, spawn_radius_max)
		offset = Vector3(cos(angle), 0.0, sin(angle)) * radius
	else:
		offset = (-wind * randf_range(spawn_radius_max * 0.72, spawn_radius_max)) + (tangent * randf_range(-spawn_radius_max * 0.55, spawn_radius_max * 0.55))
	cloud.global_position = Vector3(center.x + offset.x, cloud_altitude + randf_range(-3.0, 3.0), center.z + offset.z)


func _get_follow_center() -> Vector3:
	if is_instance_valid(_target):
		return _target.global_position
	if Engine.is_editor_hint():
		return global_position + preview_anchor
	return Vector3.ZERO


func _get_wind_direction_flat() -> Vector3:
	var wind_manager := get_node_or_null("/root/WindManager")
	if is_instance_valid(wind_manager) and wind_manager.has_method("get_wind_direction"):
		var wind_2d: Vector2 = wind_manager.call("get_wind_direction")
		if not wind_2d.is_zero_approx():
			return Vector3(wind_2d.x, 0.0, wind_2d.y).normalized()
	return Vector3(1.0, 0.0, 0.0)


func _get_wind_strength() -> float:
	var wind_manager := get_node_or_null("/root/WindManager")
	if is_instance_valid(wind_manager) and wind_manager.has_method("get_wind_strength"):
		return clampf(float(wind_manager.call("get_wind_strength")), 0.45, 1.15)
	return 0.75
