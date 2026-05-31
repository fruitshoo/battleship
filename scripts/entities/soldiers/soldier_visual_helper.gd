extends RefCounted

const NavalUiTheme = preload("res://scripts/ui/naval_ui_theme.gd")

const ROLE_MARKER_NAME := "RoleMarker"
const CAPTAIN_MARKER_NAME := "CaptainMarker"
const LEVEL_MARKER_NAME := "LevelMarker"
const VISUAL_ROOT_NAME := "VisualRoot"
const CUSTOM_VISUAL_NAME := "CustomVisual"
const BODY_MESH_NAME := "Body"
const TEAM_MATERIAL_META := "team_material_instance"
const DEAD_BODY_MATERIAL_META := "dead_body_material_instance"
const BODY_MESH_META := "body_mesh_instance"
const BODY_MESH_REST_POSITION_META := "body_mesh_rest_position"
const BODY_MESH_REST_ROTATION_META := "body_mesh_rest_rotation"
const BODY_MESH_REST_SCALE_META := "body_mesh_rest_scale"
const POSE_NODE_META := "pose_node_instance"
const POSE_NODE_REST_POSITION_META := "pose_node_rest_position"
const POSE_NODE_REST_ROTATION_META := "pose_node_rest_rotation"
const POSE_NODE_REST_SCALE_META := "pose_node_rest_scale"
const ACTIVE_VISUAL_SCENE_ID_META := "active_visual_scene_id"


static func ensure_visual_root(soldier) -> Node3D:
	if soldier.has_method("ensure_visual_root_node"):
		var visual_root: Variant = soldier.call("ensure_visual_root_node")
		return visual_root as Node3D if visual_root is Node3D else null
	return soldier as Node3D


static func setup_visual_scene(soldier, visual_scene: PackedScene) -> void:
	var visual_root := ensure_visual_root(soldier)
	var custom_visual := _get_custom_visual_node(soldier, visual_root)
	var fallback_mesh := _get_fallback_visual_mesh(soldier, visual_root)

	if visual_scene == null:
		if custom_visual != null:
			visual_root.remove_child(custom_visual)
			custom_visual.queue_free()
		if fallback_mesh != null:
			fallback_mesh.visible = true
		_clear_body_mesh_cache(soldier)
		return

	var scene_id := visual_scene.get_instance_id()
	if custom_visual != null and int(custom_visual.get_meta(ACTIVE_VISUAL_SCENE_ID_META, -1)) == scene_id:
		if fallback_mesh != null:
			fallback_mesh.visible = false
		return

	if custom_visual != null:
		visual_root.remove_child(custom_visual)
		custom_visual.queue_free()

	var visual_instance := visual_scene.instantiate() as Node3D
	if visual_instance == null:
		if fallback_mesh != null:
			fallback_mesh.visible = true
		return

	visual_instance.name = CUSTOM_VISUAL_NAME
	visual_instance.set_meta(ACTIVE_VISUAL_SCENE_ID_META, scene_id)
	visual_root.add_child(visual_instance)
	if fallback_mesh != null:
		fallback_mesh.visible = false
	_clear_body_mesh_cache(soldier)


static func get_visual_root(soldier) -> Node3D:
	if soldier.has_method("get_visual_root_node"):
		var visual_root: Variant = soldier.call("get_visual_root_node")
		return visual_root as Node3D if visual_root is Node3D else soldier as Node3D
	return soldier as Node3D


static func get_body_mesh(soldier) -> MeshInstance3D:
	if soldier.has_meta(BODY_MESH_META):
		var cached_mesh := soldier.get_meta(BODY_MESH_META) as MeshInstance3D
		if is_instance_valid(cached_mesh):
			return cached_mesh

	var visual_root := get_visual_root(soldier)
	var custom_visual := _get_custom_visual_node(soldier, visual_root)
	var mesh := _find_body_mesh_instance(custom_visual) if custom_visual != null else null
	if mesh == null:
		mesh = _get_fallback_visual_mesh(soldier, visual_root)
	if mesh == null:
		mesh = _find_first_mesh_instance(visual_root)

	if mesh != null:
		soldier.set_meta(BODY_MESH_META, mesh)
		_cache_body_mesh_rest_transform(soldier, mesh)
	return mesh


static func get_pose_node(soldier) -> Node3D:
	if soldier.has_meta(POSE_NODE_META):
		var cached_node := soldier.get_meta(POSE_NODE_META) as Node3D
		if is_instance_valid(cached_node):
			return cached_node

	var visual_root := get_visual_root(soldier)
	var pose_node := _get_custom_visual_node(soldier, visual_root)
	if pose_node == null:
		pose_node = get_body_mesh(soldier) as Node3D

	if pose_node != null:
		soldier.set_meta(POSE_NODE_META, pose_node)
		_cache_pose_node_rest_transform(soldier, pose_node)
	return pose_node


static func _find_body_mesh_instance(node: Node) -> MeshInstance3D:
	if node == null:
		return null
	var named_body := _find_named_mesh_instance(node, BODY_MESH_NAME)
	if named_body != null:
		return named_body
	return _find_first_mesh_instance(node)


static func _find_named_mesh_instance(node: Node, mesh_name: String) -> MeshInstance3D:
	if node == null:
		return null
	if node is MeshInstance3D and node.name == mesh_name:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_named_mesh_instance(child, mesh_name)
		if found != null:
			return found
	return null


static func _get_custom_visual_node(soldier, visual_root: Node = null) -> Node3D:
	if soldier.has_method("get_custom_visual_node"):
		var custom_visual: Variant = soldier.call("get_custom_visual_node", visual_root)
		return custom_visual as Node3D if custom_visual is Node3D else null
	return null


static func _get_fallback_visual_mesh(soldier, visual_root: Node = null) -> MeshInstance3D:
	if soldier.has_method("get_fallback_visual_mesh"):
		var mesh: Variant = soldier.call("get_fallback_visual_mesh", visual_root)
		return mesh as MeshInstance3D if mesh is MeshInstance3D else null
	return null


static func _get_soldier_hand_pivot(soldier) -> Node3D:
	if soldier.has_method("get_hand_pivot"):
		var pivot: Variant = soldier.call("get_hand_pivot")
		return pivot as Node3D if pivot is Node3D else null
	return null


static func _find_first_mesh_instance(node: Node) -> MeshInstance3D:
	if node == null:
		return null
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_first_mesh_instance(child)
		if found != null:
			return found
	return null


static func _cache_body_mesh_rest_transform(soldier, mesh: MeshInstance3D) -> void:
	if not soldier.has_meta(BODY_MESH_REST_POSITION_META):
		soldier.set_meta(BODY_MESH_REST_POSITION_META, mesh.position)
		soldier.set_meta(BODY_MESH_REST_ROTATION_META, mesh.rotation)
		soldier.set_meta(BODY_MESH_REST_SCALE_META, mesh.scale)


static func _cache_pose_node_rest_transform(soldier, pose_node: Node3D) -> void:
	if not soldier.has_meta(POSE_NODE_REST_POSITION_META):
		soldier.set_meta(POSE_NODE_REST_POSITION_META, pose_node.position)
		soldier.set_meta(POSE_NODE_REST_ROTATION_META, pose_node.rotation)
		soldier.set_meta(POSE_NODE_REST_SCALE_META, pose_node.scale)


static func _clear_body_mesh_cache(soldier) -> void:
	if soldier.has_meta(BODY_MESH_META):
		soldier.remove_meta(BODY_MESH_META)
	if soldier.has_meta(BODY_MESH_REST_POSITION_META):
		soldier.remove_meta(BODY_MESH_REST_POSITION_META)
	if soldier.has_meta(BODY_MESH_REST_ROTATION_META):
		soldier.remove_meta(BODY_MESH_REST_ROTATION_META)
	if soldier.has_meta(BODY_MESH_REST_SCALE_META):
		soldier.remove_meta(BODY_MESH_REST_SCALE_META)
	if soldier.has_meta(POSE_NODE_META):
		soldier.remove_meta(POSE_NODE_META)
	if soldier.has_meta(POSE_NODE_REST_POSITION_META):
		soldier.remove_meta(POSE_NODE_REST_POSITION_META)
	if soldier.has_meta(POSE_NODE_REST_ROTATION_META):
		soldier.remove_meta(POSE_NODE_REST_ROTATION_META)
	if soldier.has_meta(POSE_NODE_REST_SCALE_META):
		soldier.remove_meta(POSE_NODE_REST_SCALE_META)


static func ensure_role_marker(soldier) -> MeshInstance3D:
	var marker := soldier.get_node_or_null(ROLE_MARKER_NAME) as MeshInstance3D
	if marker != null:
		return marker
	marker = MeshInstance3D.new()
	marker.name = ROLE_MARKER_NAME
	marker.position = Vector3(0.0, 1.15, 0.0)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.18, 0.18, 0.18)
	marker.mesh = mesh
	soldier.add_child(marker)
	return marker


static func remove_captain_marker(soldier) -> void:
	var marker: Node = soldier.get_node_or_null(CAPTAIN_MARKER_NAME)
	if marker == null:
		return
	soldier.remove_child(marker)
	marker.queue_free()



static func ensure_level_marker(soldier) -> Label3D:
	var marker := soldier.get_node_or_null(LEVEL_MARKER_NAME) as Label3D
	if marker != null:
		return marker
	marker = Label3D.new()
	marker.name = LEVEL_MARKER_NAME
	marker.position = Vector3(0.0, 1.78, 0.0)
	NavalUiTheme.style_world_marker(marker, 24, Color(1.0, 0.9, 0.32, 1.0))
	soldier.add_child(marker)
	return marker


static func update_role_visual(soldier) -> void:
	var marker = ensure_role_marker(soldier)
	if marker == null:
		return
	remove_captain_marker(soldier)

	var material := StandardMaterial3D.new()
	material.resource_local_to_scene = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true

	match str(soldier.crew_role):
		"fire_pot":
			marker.visible = true
			marker.scale = Vector3.ONE
			marker.rotation_degrees = Vector3(0.0, 0.0, 45.0)
			material.albedo_color = Color(0.96, 0.42, 0.18, 1.0)
			material.emission = Color(1.0, 0.42, 0.16, 1.0)
			material.emission_energy_multiplier = 0.5
		"repeating_crossbow":
			marker.visible = true
			marker.scale = Vector3(1.0, 0.5, 1.8)
			marker.rotation_degrees = Vector3.ZERO
			material.albedo_color = Color(0.58, 0.95, 0.32, 1.0)
			material.emission = Color(0.58, 0.95, 0.32, 1.0)
			material.emission_energy_multiplier = 0.38
		"singigeon":
			marker.visible = true
			marker.scale = Vector3(0.9, 0.5, 2.2)
			marker.rotation_degrees = Vector3(0.0, 0.0, 18.0)
			material.albedo_color = Color(1.0, 0.42, 0.32, 1.0)
			material.emission = Color(1.0, 0.46, 0.28, 1.0)
			material.emission_energy_multiplier = 0.42
		"daecheolpo":
			marker.visible = true
			marker.scale = Vector3(0.55, 0.45, 2.4)
			marker.rotation_degrees = Vector3(0.0, 0.0, -12.0)
			material.albedo_color = Color(0.32, 0.34, 0.38, 1.0)
			material.emission = Color(0.68, 0.38, 0.22, 1.0)
			material.emission_energy_multiplier = 0.34
		"spearman":
			marker.visible = true
			marker.scale = Vector3(0.45, 2.1, 0.45)
			marker.rotation_degrees = Vector3.ZERO
			material.albedo_color = Color(0.5, 0.82, 1.0, 1.0)
			material.emission = Color(0.5, 0.82, 1.0, 1.0)
			material.emission_energy_multiplier = 0.32
		_:
			marker.visible = false
			marker.scale = Vector3.ONE
			marker.rotation_degrees = Vector3.ZERO
			material.albedo_color = Color.WHITE
			material.emission = Color.BLACK
			material.emission_energy_multiplier = 0.0

	marker.material_override = material


static func update_level_visual(soldier) -> void:
	var level := 1
	if soldier.has_method("get_soldier_level_value"):
		level = int(soldier.get_soldier_level_value())
	elif soldier.has_meta("soldier_level"):
		level = int(soldier.get_meta("soldier_level", 1))

	var should_show := str(soldier.get("team")) == "player" and level > 1 and SoldierStateHelper.is_alive_soldier(soldier)
	var marker := soldier.get_node_or_null(LEVEL_MARKER_NAME) as Label3D
	if marker == null and not should_show:
		return
	if marker == null:
		marker = ensure_level_marker(soldier)
	marker.text = "Lv.%d" % level
	marker.visible = should_show


static func update_team_color(soldier) -> void:
	var mesh_instance := get_body_mesh(soldier)
	if mesh_instance:
		mesh_instance.material_override = get_or_create_team_material(soldier)

static func get_or_create_team_material(soldier) -> StandardMaterial3D:
	var mesh_instance := get_body_mesh(soldier)
	if mesh_instance == null:
		return null

	var team_material: StandardMaterial3D = null
	if soldier.has_meta(TEAM_MATERIAL_META):
		team_material = soldier.get_meta(TEAM_MATERIAL_META) as StandardMaterial3D

	if team_material == null:
		team_material = StandardMaterial3D.new()
		team_material.resource_local_to_scene = true
		soldier.set_meta(TEAM_MATERIAL_META, team_material)

	team_material.albedo_color = get_team_color(soldier.team)
	return team_material


static func get_team_color(team_name: String) -> Color:
	if team_name == "player":
		return Color(0.2, 0.4, 0.8)
	return Color(0.8, 0.2, 0.2)


static func flash_hit(soldier, flash_color: Color = Color.WHITE) -> void:
	var mesh := get_body_mesh(soldier)
	if not mesh:
		return
	if mesh.material_override == null:
		return

	var tween = soldier.create_tween()
	mesh.material_override.emission_enabled = true
	mesh.material_override.emission = flash_color
	mesh.material_override.emission_energy_multiplier = 2.0

	tween.tween_property(mesh.material_override, "emission_energy_multiplier", 0.0, 0.16)
	var mesh_id: int = mesh.get_instance_id()
	tween.finished.connect(func():
		var flash_mesh := NodeContractHelper.get_instance_mesh_instance_3d(mesh_id)
		if is_instance_valid(flash_mesh) and flash_mesh.material_override:
			flash_mesh.material_override.emission_enabled = false
	)


static func play_death_pose(soldier) -> void:
	var mesh := get_body_mesh(soldier)
	var pose_node := get_pose_node(soldier)
	if mesh == null or pose_node == null:
		soldier.visible = false
		return

	soldier.visible = true
	mesh.visible = true
	pose_node.visible = true

	var role_marker := soldier.get_node_or_null(ROLE_MARKER_NAME) as MeshInstance3D
	if role_marker != null:
		role_marker.visible = false
	remove_captain_marker(soldier)
	var level_marker := soldier.get_node_or_null(LEVEL_MARKER_NAME) as Label3D
	if level_marker != null:
		level_marker.visible = false

	var hand_pivot := _get_soldier_hand_pivot(soldier)
	if hand_pivot != null:
		hand_pivot.visible = false

	var dead_material: StandardMaterial3D = null
	if soldier.has_meta(DEAD_BODY_MATERIAL_META):
		dead_material = soldier.get_meta(DEAD_BODY_MATERIAL_META) as StandardMaterial3D
	if dead_material == null:
		dead_material = StandardMaterial3D.new()
		dead_material.resource_local_to_scene = true
		soldier.set_meta(DEAD_BODY_MATERIAL_META, dead_material)
	dead_material.albedo_color = get_team_color(str(soldier.team)).darkened(0.38)
	dead_material.roughness = 0.9
	mesh.material_override = dead_material

	var fall_side: float = -1.0 if (soldier.get_instance_id() % 2) == 0 else 1.0
	var target_rotation := Vector3(0.0, 0.0, fall_side * PI * 0.5)
	var target_position := Vector3(0.0, 0.32, 0.0)
	var target_scale := Vector3(1.0, 0.82, 1.0)
	if soldier.is_inside_tree():
		var tween: Tween = soldier.create_tween()
		tween.set_parallel(true)
		tween.tween_property(pose_node, "rotation", target_rotation, 0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_property(pose_node, "position", target_position, 0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_property(pose_node, "scale", target_scale, 0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		pose_node.rotation = target_rotation
		pose_node.position = target_position
		pose_node.scale = target_scale


static func play_boarding_jump_pose(soldier) -> void:
	var pose_node := get_pose_node(soldier)
	if pose_node == null:
		return
	_cache_pose_node_rest_transform(soldier, pose_node)
	var rest_rotation: Vector3 = soldier.get_meta(POSE_NODE_REST_ROTATION_META, pose_node.rotation)
	var rest_position: Vector3 = soldier.get_meta(POSE_NODE_REST_POSITION_META, pose_node.position)
	var rest_scale: Vector3 = soldier.get_meta(POSE_NODE_REST_SCALE_META, pose_node.scale)
	pose_node.rotation = rest_rotation
	pose_node.position = rest_position
	pose_node.scale = rest_scale


static func play_knockback_pose(soldier, knockback_dir: Vector3, speed: float, allow_overboard: bool) -> void:
	var pose_node := get_pose_node(soldier)
	if pose_node == null or not soldier.is_inside_tree():
		return
	_cache_pose_node_rest_transform(soldier, pose_node)
	var rest_rotation: Vector3 = soldier.get_meta(POSE_NODE_REST_ROTATION_META, pose_node.rotation)
	var rest_position: Vector3 = soldier.get_meta(POSE_NODE_REST_POSITION_META, pose_node.position)
	var rest_scale: Vector3 = soldier.get_meta(POSE_NODE_REST_SCALE_META, pose_node.scale)
	var local_dir := knockback_dir
	if soldier is Node3D:
		local_dir = (soldier as Node3D).global_basis.inverse() * knockback_dir
	local_dir.y = 0.0
	if local_dir.length_squared() <= 0.0001:
		local_dir = Vector3.FORWARD
	local_dir = local_dir.normalized()
	var intensity := clampf(speed / 20.0, 0.45, 1.25)
	if allow_overboard:
		intensity = maxf(intensity, 1.0)
	var target_rotation := rest_rotation + Vector3(
		deg_to_rad(-18.0 * intensity),
		0.0,
		deg_to_rad(-local_dir.x * 20.0 * intensity)
	)
	var target_position := rest_position + Vector3(local_dir.x * 0.05, 0.08 if allow_overboard else 0.03, local_dir.z * 0.07)
	var squash := clampf(1.0 - 0.08 * intensity, 0.82, 0.96)
	var target_scale := Vector3(rest_scale.x * 1.06, rest_scale.y * squash, rest_scale.z * 1.04)
	var tween: Tween = soldier.create_tween()
	tween.set_parallel(true)
	tween.tween_property(pose_node, "rotation", target_rotation, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(pose_node, "position", target_position, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(pose_node, "scale", target_scale, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.chain().tween_property(pose_node, "rotation", rest_rotation, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(pose_node, "position", rest_position, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(pose_node, "scale", rest_scale, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


static func play_recovery_pose(soldier) -> void:
	var mesh := get_body_mesh(soldier)
	var pose_node := get_pose_node(soldier)
	if mesh != null:
		_cache_body_mesh_rest_transform(soldier, mesh)
		mesh.visible = true
		mesh.material_override = get_or_create_team_material(soldier)
	if pose_node != null:
		_cache_pose_node_rest_transform(soldier, pose_node)
		pose_node.visible = true
		pose_node.rotation = soldier.get_meta(POSE_NODE_REST_ROTATION_META, pose_node.rotation)
		pose_node.position = soldier.get_meta(POSE_NODE_REST_POSITION_META, pose_node.position)
		pose_node.scale = soldier.get_meta(POSE_NODE_REST_SCALE_META, pose_node.scale)

	if soldier.get("crew_role") != null:
		update_role_visual(soldier)
	update_level_visual(soldier)
	var hand_pivot := _get_soldier_hand_pivot(soldier)
	if hand_pivot != null:
		hand_pivot.visible = true
	soldier.visible = true
