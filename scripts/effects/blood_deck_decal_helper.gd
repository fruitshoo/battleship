extends RefCounted
class_name BloodDeckDecalHelper

const BLOOD_STAIN_TEXTURES := [
	preload("res://assets/vfx/decals/blood/red/blood_splatter_red_01.png"),
	preload("res://assets/vfx/decals/blood/red/blood_splatter_red_02.png"),
	preload("res://assets/vfx/decals/blood/red/blood_splatter_red_03.png"),
	preload("res://assets/vfx/decals/blood/red/blood_splatter_red_04.png"),
	preload("res://assets/vfx/decals/blood/red/blood_splatter_red_05.png"),
	preload("res://assets/vfx/decals/blood/red/blood_splatter_red_06.png"),
	preload("res://assets/vfx/decals/blood/red/blood_splatter_red_07.png"),
	preload("res://assets/vfx/decals/blood/red/blood_splatter_red_08.png"),
]
const DECAL_ROOT_NAME := "__BloodDeckDecals"
const MAX_DECALS_PER_SHIP := 18
const MAX_SPAWNS_PER_FRAME := 4
const MAX_SPAWN_DISTANCE := 55.0
const DECK_EDGE_PADDING := 0.18
const DECK_RAW_PLACEMENT_MARGIN := 0.55
const DECK_Y_TOLERANCE_BELOW := 0.8
const DECK_Y_TOLERANCE_ABOVE := 1.35
const DECK_DECAL_Y_OFFSET := 0.18
const OWNED_SHIP_CHANGE_GRACE_MSEC := 260
const META_OWNED_SHIP_CHANGED_MSEC := "owned_ship_changed_msec"
const META_COMBAT_DECK_ZONE := "combat_deck_zone"
const ZONE_ROOF := "roof"
const DEBUG_BLOOD_DECAL_REJECTS := false
const USE_STAIN_PLANE := true
const STAIN_SIZE_MULTIPLIER := 1.2

const BLOOD_BLOCKED_DAMAGE_SOURCES := {
	"drowned": true,
	"overboard": true,
	"fire": true,
	"leak": true,
}


static func try_spawn_from_soldier_damage(soldier, damage_amount: float, hit_position: Vector3, damage_source: String) -> void:
	if not _should_spawn_for_source(damage_source):
		return
	if not is_instance_valid(soldier) or not (soldier is Node3D):
		return
	if damage_amount <= 0.0:
		return
	var ship := _resolve_owned_ship(soldier)
	if not is_instance_valid(ship) or not ship.is_inside_tree():
		_debug_reject("invalid_owned_ship", soldier, null)
		return
	if ship.get("is_sinking") == true or ship.get("is_dying") == true:
		_debug_reject("sinking_or_dying_ship", soldier, ship)
		return
	if ship.has_method("is_sinking_or_dying") and ship.call("is_sinking_or_dying") == true:
		_debug_reject("sinking_or_dying_ship_method", soldier, ship)
		return
	if _is_owned_ship_recently_changed(soldier):
		_debug_reject("recent_owned_ship_change", soldier, ship)
		return

	var tree := ship.get_tree()
	if not is_instance_valid(tree):
		return
	var soldier_node := soldier as Node3D
	if not soldier_node.is_inside_tree():
		_debug_reject("detached_soldier", soldier, ship)
		return
	if not _is_soldier_parented_to_owned_ship(soldier_node, ship):
		_debug_reject("soldier_not_under_owned_ship", soldier, ship)
		return
	var world_pos: Vector3 = soldier_node.global_position
	if not _is_valid_world_position(world_pos):
		_debug_reject("invalid_world_position", soldier, ship, world_pos)
		return

	var local_pos := ship.to_local(world_pos)
	var use_roof_surface := _is_roof_deck_soldier(soldier) and _can_use_roof_surface(ship)
	var deck_height := _get_deck_height(ship)
	if use_roof_surface:
		if not _is_near_roof_before_clamp(ship, local_pos):
			_debug_reject("off_roof_surface", soldier, ship, world_pos, local_pos)
			return
	else:
		if not _is_near_deck_before_clamp(ship, local_pos, deck_height):
			_debug_reject("off_owned_deck", soldier, ship, world_pos, local_pos)
			return
	if not VfxBudget.allow_spawn(tree, "blood_deck_decal", world_pos, MAX_SPAWNS_PER_FRAME, MAX_SPAWN_DISTANCE):
		return
	if randf() > _spawn_chance(damage_amount, damage_source):
		return

	if use_roof_surface:
		local_pos = _clamp_to_roof(ship, local_pos)
		local_pos.y += DECK_DECAL_Y_OFFSET
	else:
		local_pos = _clamp_to_deck(ship, local_pos)
		if not _is_inside_deck(ship, local_pos):
			return
		local_pos.y = deck_height + DECK_DECAL_Y_OFFSET

	var spill_offset := _get_spill_offset_local(ship, world_pos, hit_position)
	var random_offset := Vector3(randf_range(-0.12, 0.12), 0.0, randf_range(-0.12, 0.12))
	if use_roof_surface:
		local_pos = _clamp_to_roof(ship, local_pos + spill_offset + random_offset)
		local_pos.y += DECK_DECAL_Y_OFFSET
	else:
		local_pos = _clamp_to_deck(ship, local_pos + spill_offset + random_offset)
		local_pos.y = deck_height + DECK_DECAL_Y_OFFSET

	var root := _get_or_create_decal_root(ship)
	if not is_instance_valid(root):
		return
	var decal := _make_decal(damage_amount, not use_roof_surface)
	root.add_child(decal)
	decal.position = local_pos
	decal.rotation = Vector3(0.0, randf_range(-PI, PI), 0.0)
	_trim_old_decals(root)

static func _should_spawn_for_source(damage_source: String) -> bool:
	return not BLOOD_BLOCKED_DAMAGE_SOURCES.has(damage_source)

static func _spawn_chance(damage_amount: float, damage_source: String) -> float:
	var base_chance := 0.68
	if damage_source == "sword" or damage_source == "spear" or damage_source == "trident" or damage_source == "harpoon":
		base_chance = 0.88
	elif damage_source == "daecheolpo" or damage_source == "small_cannonball":
		base_chance = 0.76
	return clampf(base_chance + damage_amount / 95.0, 0.35, 1.0)


static func _resolve_owned_ship(soldier) -> Node3D:
	var ship_value: Variant = soldier.get("owned_ship") if soldier.get("owned_ship") != null else null
	return ship_value as Node3D

static func _is_owned_ship_recently_changed(soldier) -> bool:
	if not soldier.has_meta(META_OWNED_SHIP_CHANGED_MSEC):
		return false
	var changed_msec := int(soldier.get_meta(META_OWNED_SHIP_CHANGED_MSEC, 0))
	if changed_msec <= 0:
		return false
	return Time.get_ticks_msec() - changed_msec <= OWNED_SHIP_CHANGE_GRACE_MSEC


static func _is_soldier_parented_to_owned_ship(soldier_node: Node3D, ship: Node3D) -> bool:
	var soldiers_container := NodeContractHelper.get_soldiers_container(ship)
	if not is_instance_valid(soldiers_container):
		return false
	var cursor := soldier_node.get_parent()
	while is_instance_valid(cursor):
		if cursor == soldiers_container:
			return true
		if cursor == ship:
			return true
			cursor = cursor.get_parent()
	return false

static func _is_valid_world_position(world_pos: Vector3) -> bool:
	return world_pos.is_finite()

static func _is_roof_deck_soldier(soldier) -> bool:
	return is_instance_valid(soldier) and str(soldier.get_meta(META_COMBAT_DECK_ZONE, "")) == ZONE_ROOF

static func _can_use_roof_surface(ship: Node3D) -> bool:
	if not is_instance_valid(ship):
		return false
	if not ship.has_method("is_roof_boarding_enabled") or ship.call("is_roof_boarding_enabled") != true:
		return false
	return ship.has_method("is_roof_local_position_in_bounds") and ship.has_method("clamp_roof_boarding_landing_local")

static func _is_near_roof_before_clamp(ship: Node3D, local_pos: Vector3) -> bool:
	if not _can_use_roof_surface(ship):
		return false
	if ship.call("is_roof_local_position_in_bounds", local_pos) == true:
		return true
	var clamped_variant: Variant = ship.call("clamp_roof_boarding_landing_local", local_pos)
	if not clamped_variant is Vector3:
		return false
	var clamped := clamped_variant as Vector3
	var planar_delta := Vector2(local_pos.x - clamped.x, local_pos.z - clamped.z)
	return planar_delta.length_squared() <= DECK_RAW_PLACEMENT_MARGIN * DECK_RAW_PLACEMENT_MARGIN \
		and absf(local_pos.y - clamped.y) <= DECK_Y_TOLERANCE_ABOVE

static func _is_near_deck_before_clamp(ship: Node3D, local_pos: Vector3, deck_height: float) -> bool:
	if local_pos.y < deck_height - DECK_Y_TOLERANCE_BELOW or local_pos.y > deck_height + DECK_Y_TOLERANCE_ABOVE:
		return false
	var half_ext := _get_deck_half_extents(ship)
	var z_limit := maxf(0.08, half_ext.y - DECK_EDGE_PADDING)
	if absf(local_pos.z) > z_limit + DECK_RAW_PLACEMENT_MARGIN:
		return false
	var width_sample_z := clampf(local_pos.z, -z_limit, z_limit)
	var half_width := _get_deck_half_width_at_z(ship, width_sample_z, half_ext.x)
	var x_limit := maxf(0.08, half_width - DECK_EDGE_PADDING)
	return absf(local_pos.x) <= x_limit + DECK_RAW_PLACEMENT_MARGIN


static func _debug_reject(reason: String, soldier, ship: Node3D = null, world_pos: Vector3 = Vector3.ZERO, local_pos: Vector3 = Vector3.ZERO) -> void:
	if not DEBUG_BLOOD_DECAL_REJECTS:
		return
	var soldier_name := str(soldier.name) if is_instance_valid(soldier) else "<invalid>"
	var ship_name := str(ship.name) if is_instance_valid(ship) else "<invalid>"
	print("[BloodDeckDecal] skipped=%s soldier=%s ship=%s world=%s local=%s" % [
		reason,
		soldier_name,
		ship_name,
		world_pos,
		local_pos,
	])


static func _get_or_create_decal_root(ship: Node3D) -> Node3D:
	var root := ship.get_node_or_null(DECAL_ROOT_NAME) as Node3D
	if is_instance_valid(root):
		return root
	root = Node3D.new()
	root.name = DECAL_ROOT_NAME
	ship.add_child(root)
	return root


static func _make_decal(damage_amount: float, use_stain_plane: bool = true) -> Node3D:
	var stain_root := Node3D.new()
	stain_root.name = "BloodDeckStain"

	var stain_tint := Color(
		randf_range(0.92, 1.0),
		randf_range(0.80, 0.92),
		randf_range(0.76, 0.88),
		randf_range(0.88, 1.0)
	)
	var stain_scale := clampf(0.52 + damage_amount * 0.016, 0.52, 1.08) * randf_range(0.9, 1.32) * STAIN_SIZE_MULTIPLIER
	var stain_texture := _pick_stain_texture()

	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = Vector2(
		stain_scale * randf_range(0.78, 1.28),
		stain_scale * randf_range(0.72, 1.18)
	)

	if USE_STAIN_PLANE and use_stain_plane:
		var plane_material := StandardMaterial3D.new()
		plane_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		plane_material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		plane_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		plane_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		plane_material.no_depth_test = false
		plane_material.albedo_color = stain_tint
		plane_material.albedo_texture = stain_texture
		plane_material.albedo_texture_force_srgb = true
		plane_material.render_priority = 8

		var stain_plane := MeshInstance3D.new()
		stain_plane.name = "StainPlane"
		stain_plane.mesh = plane_mesh
		stain_plane.material_override = plane_material
		stain_plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		stain_plane.extra_cull_margin = 0.2
		stain_root.add_child(stain_plane)

	var decal := Decal.new()
	decal.name = "Projection"
	decal.texture_albedo = stain_texture
	decal.modulate = stain_tint
	decal.albedo_mix = 1.0
	decal.normal_fade = 0.22
	decal.upper_fade = 0.08
	decal.lower_fade = 0.08
	decal.distance_fade_enabled = true
	decal.distance_fade_begin = 42.0
	decal.distance_fade_length = 18.0
	decal.size = Vector3(
		plane_mesh.size.x,
		plane_mesh.size.y,
		0.72
	)
	decal.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	stain_root.add_child(decal)
	return stain_root


static func _pick_stain_texture() -> Texture2D:
	if BLOOD_STAIN_TEXTURES.is_empty():
		return null
	return BLOOD_STAIN_TEXTURES.pick_random() as Texture2D


static func _trim_old_decals(root: Node3D) -> void:
	while root.get_child_count() > MAX_DECALS_PER_SHIP:
		var oldest := root.get_child(0)
		root.remove_child(oldest)
		oldest.queue_free()


static func _get_deck_height(ship: Node3D) -> float:
	var deck_height_value: Variant = ship.get("deck_height")
	return float(deck_height_value) if deck_height_value != null else 0.4


static func _get_deck_half_extents(ship: Node3D) -> Vector2:
	if ship.has_method("get_deck_half_extents"):
		var extents: Variant = ship.call("get_deck_half_extents")
		if extents is Vector2:
			return extents
	if ship.has_method("get_collision_half_extents"):
		var collision_extents: Variant = ship.call("get_collision_half_extents")
		if collision_extents is Vector2:
			return collision_extents
	return Vector2(1.5, 2.5)


static func _get_deck_half_width_at_z(ship: Node3D, local_z: float, fallback_width: float) -> float:
	if ship.has_method("get_deck_half_width_at_z"):
		var width_value: Variant = ship.call("get_deck_half_width_at_z", local_z)
		if width_value != null:
			return maxf(0.08, float(width_value))
	return fallback_width


static func _clamp_to_deck(ship: Node3D, local_pos: Vector3) -> Vector3:
	var half_ext := _get_deck_half_extents(ship)
	var z_limit := maxf(0.08, half_ext.y - DECK_EDGE_PADDING)
	local_pos.z = clampf(local_pos.z, -z_limit, z_limit)
	var half_width := _get_deck_half_width_at_z(ship, local_pos.z, half_ext.x)
	var x_limit := maxf(0.08, half_width - DECK_EDGE_PADDING)
	local_pos.x = clampf(local_pos.x, -x_limit, x_limit)
	return local_pos


static func _clamp_to_roof(ship: Node3D, local_pos: Vector3) -> Vector3:
	if not _can_use_roof_surface(ship):
		return local_pos
	var clamped_variant: Variant = ship.call("clamp_roof_boarding_landing_local", local_pos)
	return clamped_variant as Vector3 if clamped_variant is Vector3 else local_pos


static func _is_inside_deck(ship: Node3D, local_pos: Vector3) -> bool:
	var half_ext := _get_deck_half_extents(ship)
	if absf(local_pos.z) > maxf(0.08, half_ext.y - DECK_EDGE_PADDING):
		return false
	var half_width := _get_deck_half_width_at_z(ship, local_pos.z, half_ext.x)
	return absf(local_pos.x) <= maxf(0.08, half_width - DECK_EDGE_PADDING)


static func _get_spill_offset_local(ship: Node3D, world_pos: Vector3, hit_position: Vector3) -> Vector3:
	if hit_position == Vector3.ZERO:
		return Vector3.ZERO
	var spill_dir := world_pos - hit_position
	spill_dir.y = 0.0
	if spill_dir.length_squared() <= 0.001:
		return Vector3.ZERO
	spill_dir = spill_dir.normalized()
	var local_dir := ship.global_transform.basis.inverse() * spill_dir
	local_dir.y = 0.0
	if local_dir.length_squared() <= 0.001:
		return Vector3.ZERO
	return local_dir.normalized() * randf_range(0.08, 0.32)
