extends RefCounted

const ROLE_MARKER_NAME := "RoleMarker"
const CAPTAIN_MARKER_NAME := "CaptainMarker"
const LEVEL_MARKER_NAME := "LevelMarker"
const TEAM_MATERIAL_META := "team_material_instance"
const DEAD_BODY_MATERIAL_META := "dead_body_material_instance"


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


static func ensure_captain_marker(soldier) -> MeshInstance3D:
	var marker := soldier.get_node_or_null(CAPTAIN_MARKER_NAME) as MeshInstance3D
	if marker != null:
		return marker
	marker = MeshInstance3D.new()
	marker.name = CAPTAIN_MARKER_NAME
	marker.position = Vector3(0.0, 1.5, 0.0)
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.16
	mesh.bottom_radius = 0.16
	mesh.height = 0.05
	mesh.radial_segments = 12
	marker.mesh = mesh
	soldier.add_child(marker)
	return marker


static func ensure_level_marker(soldier) -> Label3D:
	var marker := soldier.get_node_or_null(LEVEL_MARKER_NAME) as Label3D
	if marker != null:
		return marker
	marker = Label3D.new()
	marker.name = LEVEL_MARKER_NAME
	marker.position = Vector3(0.0, 1.78, 0.0)
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.font_size = 24
	marker.outline_size = 5
	marker.modulate = Color(1.0, 0.9, 0.32, 1.0)
	soldier.add_child(marker)
	return marker


static func update_role_visual(soldier) -> void:
	var marker = ensure_role_marker(soldier)
	if marker == null:
		return
	var captain_marker = ensure_captain_marker(soldier)

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

	if captain_marker != null:
		var captain_material := StandardMaterial3D.new()
		captain_material.resource_local_to_scene = true
		captain_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		captain_material.emission_enabled = true
		captain_material.albedo_color = Color(1.0, 0.82, 0.28, 0.95)
		captain_material.emission = Color(1.0, 0.76, 0.22, 1.0)
		captain_material.emission_energy_multiplier = 0.55
		captain_marker.visible = soldier.get("is_captain") == true
		captain_marker.rotation_degrees = Vector3.ZERO
		captain_marker.scale = Vector3(1.0, 1.0, 1.0)
		captain_marker.material_override = captain_material


static func update_level_visual(soldier) -> void:
	var level := 1
	if soldier.has_method("get_soldier_level_value"):
		level = int(soldier.get_soldier_level_value())
	elif soldier.has_meta("soldier_level"):
		level = int(soldier.get_meta("soldier_level", 1))

	var is_dead := false
	if soldier.has_method("is_dead_soldier"):
		is_dead = bool(soldier.is_dead_soldier())

	var should_show := str(soldier.get("team")) == "player" and level > 1 and not is_dead
	var marker := soldier.get_node_or_null(LEVEL_MARKER_NAME) as Label3D
	if marker == null and not should_show:
		return
	if marker == null:
		marker = ensure_level_marker(soldier)
	marker.text = "Lv.%d" % level
	marker.visible = should_show


static func update_team_color(soldier) -> void:
	var mesh_instance = soldier.get_node_or_null("MeshInstance3D")
	if mesh_instance:
		mesh_instance.material_override = get_or_create_team_material(soldier)

static func get_or_create_team_material(soldier) -> StandardMaterial3D:
	var mesh_instance = soldier.get_node_or_null("MeshInstance3D")
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
	var mesh = soldier.get_node_or_null("MeshInstance3D")
	if not mesh:
		return
	if mesh.material_override == null:
		return

	var tween = soldier.create_tween()
	mesh.material_override.emission_enabled = true
	mesh.material_override.emission = flash_color
	mesh.material_override.emission_energy_multiplier = 2.0

	tween.tween_property(mesh.material_override, "emission_energy_multiplier", 0.0, 0.1)
	var mesh_id: int = mesh.get_instance_id()
	tween.finished.connect(func():
		var flash_mesh := instance_from_id(mesh_id) as MeshInstance3D
		if is_instance_valid(flash_mesh) and flash_mesh.material_override:
			flash_mesh.material_override.emission_enabled = false
	)


static func play_death_pose(soldier) -> void:
	var mesh := soldier.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh == null:
		soldier.visible = false
		return

	soldier.visible = true
	mesh.visible = true

	var role_marker := soldier.get_node_or_null(ROLE_MARKER_NAME) as MeshInstance3D
	if role_marker != null:
		role_marker.visible = false
	var captain_marker := soldier.get_node_or_null(CAPTAIN_MARKER_NAME) as MeshInstance3D
	if captain_marker != null:
		captain_marker.visible = false
	var level_marker := soldier.get_node_or_null(LEVEL_MARKER_NAME) as Label3D
	if level_marker != null:
		level_marker.visible = false

	var hand_pivot := soldier.get_node_or_null("HandPivot") as Node3D
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
		tween.tween_property(mesh, "rotation", target_rotation, 0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_property(mesh, "position", target_position, 0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_property(mesh, "scale", target_scale, 0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		mesh.rotation = target_rotation
		mesh.position = target_position
		mesh.scale = target_scale


static func play_recovery_pose(soldier) -> void:
	var mesh := soldier.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh != null:
		mesh.visible = true
		mesh.rotation = Vector3.ZERO
		mesh.position = Vector3.ZERO
		mesh.scale = Vector3.ONE
		mesh.material_override = get_or_create_team_material(soldier)

	if soldier.get("crew_role") != null:
		update_role_visual(soldier)
	update_level_visual(soldier)
	var hand_pivot := soldier.get_node_or_null("HandPivot") as Node3D
	if hand_pivot != null:
		hand_pivot.visible = true
	soldier.visible = true
