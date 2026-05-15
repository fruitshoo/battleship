extends RefCounted
class_name SoldierCaptainGuardHelper


const WARNING_ROOT_NAME := "CaptainGuardWarningRing"
const WARNING_RING_NAME := "Ring"
const GUARDED_HEALTH_FLOOR_RATIO := 0.5
const CAPTAIN_DAMAGE_MULTIPLIER := 0.5
const RING_INNER_RADIUS := 0.64
const RING_OUTER_RADIUS := 0.82
const RING_SEGMENTS := 40
const RING_Y := 0.075


static func apply_damage_protection(soldier, damage: float) -> float:
	if not _is_player_captain(soldier):
		return damage
	var reduced_damage := maxf(0.0, damage * CAPTAIN_DAMAGE_MULTIPLIER)
	if not has_living_guard(soldier):
		return reduced_damage
	var floor_health := maxf(1.0, float(soldier.get("max_health"))) * GUARDED_HEALTH_FLOOR_RATIO
	var current_health := float(soldier.get("current_health"))
	if current_health <= floor_health + 0.001:
		return 0.0
	return minf(reduced_damage, maxf(0.0, current_health - floor_health))


static func update_warning_ring(soldier, _delta: float) -> void:
	if not _should_show_warning_ring(soldier):
		hide_warning_ring(soldier)
		return
	var root := _ensure_warning_root(soldier)
	if root == null:
		return
	root.visible = true
	root.position = Vector3(0.0, RING_Y, 0.0)
	var time_sec := float(Time.get_ticks_msec()) * 0.001
	var pulse := 0.5 + 0.5 * sin(time_sec * TAU * 1.35)
	var scale_value := 0.96 + pulse * 0.11
	root.scale = Vector3(scale_value, 1.0, scale_value)
	var ring := root.get_node_or_null(WARNING_RING_NAME) as MeshInstance3D
	if ring == null:
		return
	var material := ring.material_override as StandardMaterial3D
	if material != null:
		material.albedo_color = Color(1.0, 0.08, 0.035, 0.34 + pulse * 0.24)


static func hide_warning_ring(soldier) -> void:
	if not is_instance_valid(soldier):
		return
	var root := soldier.get_node_or_null(WARNING_ROOT_NAME) as Node3D
	if root != null:
		root.visible = false


static func has_living_guard(soldier) -> bool:
	if not _is_player_captain(soldier):
		return false
	if not is_instance_valid(soldier.get("owned_ship")):
		return false
	var ship = soldier.get("owned_ship")
	for other in EntityRegistry.get_soldiers_by_ship(ship):
		if other == soldier or not is_instance_valid(other):
			continue
		if _is_captain_flag_enabled(other):
			continue
		if str(other.get("team")) != str(soldier.get("team")):
			continue
		if SoldierStateHelper.is_alive_soldier(other):
			return true
	return false


static func _should_show_warning_ring(soldier) -> bool:
	if not _is_player_captain(soldier):
		return false
	if SoldierStateHelper.is_dead_soldier(soldier):
		return false
	if has_living_guard(soldier):
		return false
	return true


static func _is_player_captain(soldier) -> bool:
	return is_instance_valid(soldier) and str(soldier.get("team")) == "player" and _is_captain_flag_enabled(soldier)


static func _is_captain_flag_enabled(soldier) -> bool:
	if not is_instance_valid(soldier):
		return false
	var value = soldier.get("is_captain")
	if value == null:
		return soldier.get_meta("is_captain", false) == true
	return value == true


static func _ensure_warning_root(soldier) -> Node3D:
	var root := soldier.get_node_or_null(WARNING_ROOT_NAME) as Node3D
	if root != null:
		return root
	root = Node3D.new()
	root.name = WARNING_ROOT_NAME
	root.visible = false
	soldier.add_child(root)

	var ring := MeshInstance3D.new()
	ring.name = WARNING_RING_NAME
	ring.mesh = _make_ring_mesh()
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.material_override = _make_ring_material()
	root.add_child(ring)
	return root


static func _make_ring_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for i in range(RING_SEGMENTS):
		var a0 := TAU * float(i) / float(RING_SEGMENTS)
		var a1 := TAU * float(i + 1) / float(RING_SEGMENTS)
		var base_index := vertices.size()
		vertices.append(Vector3(cos(a0) * RING_OUTER_RADIUS, 0.0, sin(a0) * RING_OUTER_RADIUS))
		vertices.append(Vector3(cos(a0) * RING_INNER_RADIUS, 0.0, sin(a0) * RING_INNER_RADIUS))
		vertices.append(Vector3(cos(a1) * RING_OUTER_RADIUS, 0.0, sin(a1) * RING_OUTER_RADIUS))
		vertices.append(Vector3(cos(a1) * RING_INNER_RADIUS, 0.0, sin(a1) * RING_INNER_RADIUS))
		for _j in range(4):
			normals.append(Vector3.UP)
		indices.append_array(PackedInt32Array([
			base_index,
			base_index + 2,
			base_index + 1,
			base_index + 1,
			base_index + 2,
			base_index + 3,
		]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _make_ring_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.08, 0.035, 0.42)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	return material
