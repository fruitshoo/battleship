extends RefCounted
class_name ShipDamageDecalHelper

const SCORCH_TEXTURES := [
	preload("res://assets/vfx/particles/alpha/scorch_01_a.png"),
	preload("res://assets/vfx/particles/alpha/scorch_02_a.png"),
	preload("res://assets/vfx/particles/alpha/scorch_03_a.png"),
]
const DECAL_ROOT_NAME := "__ShipDamageDecals"
const MAX_DECALS_PER_SHIP := 16
const MAX_SPAWNS_PER_FRAME := 5
const MAX_SPAWN_DISTANCE := 95.0
const DECK_EDGE_PADDING := 0.2
const DAMAGE_DECK_Y_OFFSET := 0.24
const MIN_DAMAGE_FOR_DECAL := 5.0
const DAMAGE_SIZE_MULTIPLIER := 1.45
const USE_DAMAGE_PROJECTION := true


static func try_spawn_from_ship_hit(ship: Node3D, damage_amount: float, impact_position: Vector3, damage_source: String = "") -> void:
	if not _should_spawn_ship_damage_for_source(damage_source):
		return
	if not is_instance_valid(ship) or not ship.is_inside_tree():
		return
	if damage_amount < MIN_DAMAGE_FOR_DECAL:
		return
	if not impact_position.is_finite():
		return
	if ship.get("is_sinking") == true or ship.get("is_dying") == true:
		return
	if ship.has_method("is_sinking_or_dying") and ship.call("is_sinking_or_dying") == true:
		return

	var tree := ship.get_tree()
	if not is_instance_valid(tree):
		return
	if not VfxBudget.allow_spawn(tree, "ship_damage_decal", impact_position, MAX_SPAWNS_PER_FRAME, MAX_SPAWN_DISTANCE):
		return

	var local_pos := ship.to_local(impact_position)
	local_pos = _clamp_ship_damage_to_deck(ship, local_pos)
	local_pos.y = _get_ship_decal_deck_height(ship) + DAMAGE_DECK_Y_OFFSET

	var root := _get_or_create_ship_damage_decal_root(ship)
	if not is_instance_valid(root):
		return
	var decal := _make_ship_damage_decal(damage_amount, damage_source)
	root.add_child(decal)
	decal.position = local_pos
	decal.rotation = Vector3(0.0, randf_range(-PI, PI), 0.0)
	_trim_old_ship_damage_decals(root)


static func _should_spawn_ship_damage_for_source(damage_source: String) -> bool:
	var normalized := damage_source.strip_edges().to_lower()
	if normalized == "fire" or normalized == "burn" or normalized == "leak":
		return false
	return true


static func _get_or_create_ship_damage_decal_root(ship: Node3D) -> Node3D:
	var root := ship.get_node_or_null(DECAL_ROOT_NAME) as Node3D
	if is_instance_valid(root):
		return root
	root = Node3D.new()
	root.name = DECAL_ROOT_NAME
	ship.add_child(root)
	return root


static func _make_ship_damage_decal(damage_amount: float, damage_source: String) -> Node3D:
	var root := Node3D.new()
	root.name = "ShipDamageStain"
	var texture := _pick_texture()
	var base_size := _get_decal_size(damage_amount, damage_source)
	var scorch_tint := Color(
		randf_range(0.18, 0.28),
		randf_range(0.11, 0.17),
		randf_range(0.065, 0.11),
		randf_range(0.84, 0.96)
	)
	var core_tint := Color(0.025, 0.018, 0.012, randf_range(0.9, 1.0))
	var projection_tint := Color(
		randf_range(0.13, 0.21),
		randf_range(0.075, 0.12),
		randf_range(0.038, 0.07),
		randf_range(0.9, 1.0)
	)

	root.add_child(_make_plane("Scorch", texture, scorch_tint, base_size * randf_range(1.08, 1.32), 9))
	root.add_child(_make_plane("HoleCore", texture, core_tint, base_size * randf_range(0.42, 0.62), 10, 0.012))
	if USE_DAMAGE_PROJECTION:
		root.add_child(_make_projection_decal(texture, projection_tint, base_size))
	return root


static func _make_plane(node_name: String, texture: Texture2D, tint: Color, size: float, render_priority: int, y_offset: float = 0.0) -> MeshInstance3D:
	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = Vector2(size * randf_range(0.82, 1.22), size * randf_range(0.82, 1.18))

	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = false
	material.albedo_color = tint
	material.albedo_texture = texture
	material.albedo_texture_force_srgb = true
	material.render_priority = render_priority

	var plane := MeshInstance3D.new()
	plane.name = node_name
	plane.mesh = plane_mesh
	plane.material_override = material
	plane.position.y = y_offset
	plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plane.extra_cull_margin = 0.4
	return plane


static func _make_projection_decal(texture: Texture2D, tint: Color, size: float) -> Decal:
	var decal := Decal.new()
	decal.name = "Projection"
	decal.texture_albedo = texture
	decal.modulate = tint
	decal.albedo_mix = 1.0
	decal.normal_fade = 0.24
	decal.upper_fade = 0.08
	decal.lower_fade = 0.08
	decal.distance_fade_enabled = true
	decal.distance_fade_begin = 70.0
	decal.distance_fade_length = 35.0
	decal.size = Vector3(size * randf_range(0.92, 1.22), size * randf_range(0.84, 1.18), 0.82)
	decal.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	return decal


static func _get_decal_size(damage_amount: float, damage_source: String) -> float:
	var source := damage_source.strip_edges().to_lower()
	var source_scale := 1.0
	if source.begins_with("janggun"):
		source_scale = 1.25
	elif source.contains("ramming"):
		source_scale = 1.35
	elif source.contains("small_cannonball"):
		source_scale = 0.78
	return clampf(0.46 + damage_amount * 0.018, 0.46, 1.45) * source_scale * randf_range(0.86, 1.18) * DAMAGE_SIZE_MULTIPLIER


static func _pick_texture() -> Texture2D:
	if SCORCH_TEXTURES.is_empty():
		return null
	return SCORCH_TEXTURES.pick_random() as Texture2D


static func _trim_old_ship_damage_decals(root: Node3D) -> void:
	while root.get_child_count() > MAX_DECALS_PER_SHIP:
		var oldest := root.get_child(0)
		root.remove_child(oldest)
		oldest.queue_free()


static func _get_ship_decal_deck_height(ship: Node3D) -> float:
	var deck_height_value: Variant = ship.get("deck_height")
	return float(deck_height_value) if deck_height_value != null else 0.4


static func _clamp_ship_damage_to_deck(ship: Node3D, local_pos: Vector3) -> Vector3:
	var half_ext := _get_ship_decal_deck_half_extents(ship)
	var z_limit := maxf(0.08, half_ext.y - DECK_EDGE_PADDING)
	local_pos.z = clampf(local_pos.z, -z_limit, z_limit)
	var half_width := _get_ship_decal_half_width_at_z(ship, local_pos.z, half_ext.x)
	var x_limit := maxf(0.08, half_width - DECK_EDGE_PADDING)
	local_pos.x = clampf(local_pos.x, -x_limit, x_limit)
	return local_pos


static func _get_ship_decal_deck_half_extents(ship: Node3D) -> Vector2:
	if ship.has_method("get_deck_half_extents"):
		var extents: Variant = ship.call("get_deck_half_extents")
		if extents is Vector2:
			return extents
	if ship.has_method("get_collision_half_extents"):
		var collision_extents: Variant = ship.call("get_collision_half_extents")
		if collision_extents is Vector2:
			return collision_extents
	return Vector2(1.5, 2.5)


static func _get_ship_decal_half_width_at_z(ship: Node3D, local_z: float, fallback_width: float) -> float:
	if ship.has_method("get_deck_half_width_at_z"):
		var width_value: Variant = ship.call("get_deck_half_width_at_z", local_z)
		if width_value != null:
			return maxf(0.08, float(width_value))
	return fallback_width
