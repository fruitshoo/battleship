extends RefCounted

const ROLE_MARKER_NAME := "RoleMarker"
const TEAM_MATERIAL_META := "team_material_instance"


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


static func update_role_visual(soldier) -> void:
	var marker = ensure_role_marker(soldier)
	if marker == null:
		return

	var material := StandardMaterial3D.new()
	material.resource_local_to_scene = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true

	match String(soldier.crew_role):
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
	tween.finished.connect(func():
		if mesh.material_override:
			mesh.material_override.emission_enabled = false
	)
