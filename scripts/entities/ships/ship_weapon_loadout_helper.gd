extends RefCounted
class_name ShipWeaponLoadoutHelper


const KIND := "kind"
const KIND_CANNON := "cannon"
const KIND_SINGIGEON := "singigeon"
const WEAPON_PROFILES := "weapon_profiles"
const PROFILE := "profile"
const SCENE := "scene"
const TEAM := "team"
const SLOT := "slot"
const NAME := "name"
const POSITION := "position"
const ROTATION_Y := "rotation_y"
const BASIS := "basis"
const PROJECTILE_SCENE := "projectile_scene"
const FIRE_COOLDOWN := "fire_cooldown"
const REQUIRED_LEVEL := "required_level"
const DETECTION_RANGE := "detection_range"
const DETECTION_ARC := "detection_arc"
const UPGRADE_LEVEL := "upgrade_level"
const PROJECTILE_SPEED := "projectile_speed"


static func get_weapon_loadout(stats: Dictionary, fallback: Array = []) -> Array[Dictionary]:
	var source: Variant = stats.get("weapon_loadout", fallback)
	if typeof(source) != TYPE_ARRAY:
		source = fallback

	var profiles := get_weapon_profiles()
	var loadout: Array[Dictionary] = []
	for spec_variant in source:
		if typeof(spec_variant) != TYPE_DICTIONARY:
			continue
		loadout.append(_normalize_spec(resolve_weapon_profile(spec_variant as Dictionary, profiles)))
	return loadout


static func get_weapon_loadout_for_type(type_name: String, fallback: Array = []) -> Array[Dictionary]:
	var stats := ShipBlueprintHelper.load_stats(type_name)
	return get_weapon_loadout(stats, fallback)


static func get_weapon_profiles(all_stats: Dictionary = {}) -> Dictionary:
	var stats_source := all_stats
	if stats_source.is_empty():
		stats_source = ShipBlueprintHelper.load_all_stats()
	var profiles_variant: Variant = stats_source.get(WEAPON_PROFILES, {})
	return profiles_variant as Dictionary if typeof(profiles_variant) == TYPE_DICTIONARY else {}


static func resolve_weapon_profile(spec: Dictionary, profiles: Dictionary = {}) -> Dictionary:
	var profile_name := get_profile_name(spec)
	if profile_name.is_empty():
		return spec.duplicate()

	var profile_source := profiles
	if profile_source.is_empty():
		profile_source = get_weapon_profiles()
	var profile_variant: Variant = profile_source.get(profile_name, {})
	if typeof(profile_variant) != TYPE_DICTIONARY:
		return spec.duplicate()

	var resolved: Dictionary = (profile_variant as Dictionary).duplicate()
	for key in spec.keys():
		resolved[key] = spec[key]
	return resolved


static func load_scene(spec: Dictionary, fallback: PackedScene = null) -> PackedScene:
	var scene_path := get_scene_path(spec)
	if scene_path.is_empty():
		return fallback
	var loaded: Resource = load(scene_path)
	return loaded as PackedScene if loaded is PackedScene else fallback


static func instantiate_weapon(spec: Dictionary, fallback: PackedScene = null):
	var scene := load_scene(spec, fallback)
	return scene.instantiate() if scene != null else null


static func apply_weapon_config(weapon: Node, spec: Dictionary, fallback_team: String = "") -> void:
	if not is_instance_valid(weapon):
		return

	var team_name := get_team(spec, fallback_team)
	if not team_name.is_empty():
		if weapon.has_method("set_team"):
			weapon.call("set_team", team_name)
		elif TEAM in weapon:
			weapon.set(TEAM, team_name)

	_apply_packed_scene_property(weapon, get_projectile_scene_path(spec))
	_apply_float_property(weapon, FIRE_COOLDOWN, spec)
	_apply_float_property(weapon, DETECTION_RANGE, spec)
	_apply_float_property(weapon, DETECTION_ARC, spec)
	_apply_float_property(weapon, PROJECTILE_SPEED, spec)

	if spec.has(UPGRADE_LEVEL) and weapon.has_method("upgrade_to_level"):
		weapon.call("upgrade_to_level", get_upgrade_level(spec))


static func get_default_support_cannon_loadout() -> Array[Dictionary]:
	return [
		build_cannon_spec("FleetCannon_0", "CannonFront", Vector3(0.0, 0.8, -3.5), 0.0, 1),
		build_cannon_spec("FleetCannon_1", "CannonLeft", Vector3(-1.0, 0.8, -0.5), 90.0, 2),
		build_cannon_spec("FleetCannon_2", "CannonRight", Vector3(1.0, 0.8, -0.5), -90.0, 3),
	]


static func get_default_player_cannon_loadout() -> Array[Dictionary]:
	return [
		build_cannon_spec("CannonFront", "CannonFront", Vector3(0.0, 0.6, -3.1), 0.0, 1),
		build_cannon_spec("CannonLeft", "CannonLeft", Vector3(-1.3, 0.6, 0.0), 90.0, 1),
		build_cannon_spec("CannonRight", "CannonRight", Vector3(1.3, 0.6, 0.0), -90.0, 1),
		build_cannon_spec("CannonLeftExtra", "CannonLeftExtra", Vector3(-1.3, 0.6, -2.0), 90.0, 2),
		build_cannon_spec("CannonRightExtra", "CannonRightExtra", Vector3(1.3, 0.6, 2.0), -90.0, 3),
		build_cannon_spec("CannonLeftExtraRear", "CannonLeftExtraRear", Vector3(-1.3, 0.6, 2.0), 90.0, 4),
		build_cannon_spec("CannonRightExtraForward", "CannonRightExtraForward", Vector3(1.3, 0.6, -2.0), -90.0, 5),
	]


static func get_default_boss_loadout(tier: int) -> Array[Dictionary]:
	if tier == 1:
		return [
			build_cannon_spec("BossCannonFront", "CannonFront", Vector3(0.0, 0.8, -5.0), 0.0, 1, 23.0, 50.0),
			build_cannon_spec("BossCannonLeft", "CannonLeft", Vector3(-2.8, 0.8, 0.0), 90.0, 1, 23.0, 50.0),
			build_cannon_spec("BossCannonRight", "CannonRight", Vector3(2.8, 0.8, 0.0), -90.0, 1, 23.0, 50.0),
		]

	return [
		build_cannon_spec("BossCannonLeftForward", "CannonLeftExtra", Vector3(-2.8, 0.8, -2.0), 90.0, 1, 23.0, 50.0),
		build_cannon_spec("BossCannonRightForward", "CannonRightExtraForward", Vector3(2.8, 0.8, -2.0), -90.0, 1, 23.0, 50.0),
		build_cannon_spec("BossCannonLeftMid", "CannonLeft", Vector3(-2.8, 0.8, 0.0), 90.0, 1, 23.0, 50.0),
		build_cannon_spec("BossCannonRightMid", "CannonRight", Vector3(2.8, 0.8, 0.0), -90.0, 1, 23.0, 50.0),
		build_cannon_spec("BossCannonLeftRear", "CannonLeftExtraRear", Vector3(-2.8, 0.8, 2.0), 90.0, 1, 23.0, 50.0),
		build_cannon_spec("BossCannonRightRear", "CannonRightExtra", Vector3(2.8, 0.8, 2.0), -90.0, 1, 23.0, 50.0),
		build_singigeon_spec("BossSingigeonFront", "SingigeonFront", Vector3(0.0, 1.0, -5.0), 0.0, 36.0, 3),
	]


static func build_cannon_spec(
	node_name: String,
	slot_name: String,
	position: Vector3,
	rotation_y: float,
	required_level: int = 1,
	detection_range: float = 0.0,
	detection_arc: float = 0.0,
	scene_path: String = ""
) -> Dictionary:
	var spec := {
		KIND: KIND_CANNON,
		NAME: node_name,
		SLOT: slot_name,
		POSITION: position,
		ROTATION_Y: rotation_y,
		REQUIRED_LEVEL: required_level,
	}
	if detection_range > 0.0:
		spec[DETECTION_RANGE] = detection_range
	if detection_arc > 0.0:
		spec[DETECTION_ARC] = detection_arc
	if not scene_path.strip_edges().is_empty():
		spec[SCENE] = scene_path.strip_edges()
	return spec


static func build_singigeon_spec(
	node_name: String,
	slot_name: String,
	position: Vector3,
	rotation_y: float,
	detection_range: float,
	upgrade_level: int,
	scene_path: String = ""
) -> Dictionary:
	var spec := {
		KIND: KIND_SINGIGEON,
		NAME: node_name,
		SLOT: slot_name,
		POSITION: position,
		ROTATION_Y: rotation_y,
		DETECTION_RANGE: detection_range,
		UPGRADE_LEVEL: upgrade_level,
	}
	if not scene_path.strip_edges().is_empty():
		spec[SCENE] = scene_path.strip_edges()
	return spec


static func apply_authored_weapon_slots(ship: Node3D, relative_to: Node3D, loadout: Array[Dictionary]) -> Array[Dictionary]:
	var authored_slots := ShipAuthoringHelper.get_named_weapon_slot_transforms(ship, relative_to)
	if authored_slots.is_empty():
		return loadout

	var resolved: Array[Dictionary] = []
	for spec in loadout:
		var next_spec := spec.duplicate()
		var slot_name := get_slot_name(next_spec)
		if not slot_name.is_empty() and authored_slots.has(slot_name):
			var transform: Transform3D = authored_slots[slot_name]
			next_spec[POSITION] = transform.origin
			next_spec[BASIS] = transform.basis
		resolved.append(next_spec)
	return resolved


static func apply_authored_cannon_slots(ship: Node3D, relative_to: Node3D, loadout: Array[Dictionary]) -> Array[Dictionary]:
	return apply_authored_weapon_slots(ship, relative_to, loadout)


static func get_kind(spec: Dictionary, fallback: String = KIND_CANNON) -> String:
	return str(spec.get(KIND, fallback))


static func get_node_name(spec: Dictionary, fallback: String = "") -> String:
	var value: Variant = spec.get(NAME, fallback)
	return str(value) if value != null else fallback


static func get_profile_name(spec: Dictionary, fallback: String = "") -> String:
	var value: Variant = spec.get(PROFILE, fallback)
	return str(value).strip_edges() if value != null else fallback


static func get_slot_name(spec: Dictionary, fallback: String = "") -> String:
	var value: Variant = spec.get(SLOT, fallback)
	return str(value) if value != null else fallback


static func get_team(spec: Dictionary, fallback: String = "") -> String:
	var value: Variant = spec.get(TEAM, fallback)
	return str(value).strip_edges() if value != null else fallback


static func get_scene_path(spec: Dictionary, fallback: String = "") -> String:
	var value: Variant = spec.get(SCENE, fallback)
	return str(value).strip_edges() if value != null else fallback


static func get_projectile_scene_path(spec: Dictionary, fallback: String = "") -> String:
	var value: Variant = spec.get(PROJECTILE_SCENE, fallback)
	return str(value).strip_edges() if value != null else fallback


static func get_position(spec: Dictionary, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	return _get_vector(spec, POSITION, fallback)


static func has_basis(spec: Dictionary) -> bool:
	return spec.get(BASIS, null) is Basis


static func get_basis(spec: Dictionary, fallback: Basis = Basis.IDENTITY) -> Basis:
	var value: Variant = spec.get(BASIS, fallback)
	return value if value is Basis else fallback


static func get_rotation_y(spec: Dictionary, fallback: float = 0.0) -> float:
	return _get_float(spec, ROTATION_Y, fallback)


static func get_required_level(spec: Dictionary, fallback: int = 1) -> int:
	return int(_get_float(spec, REQUIRED_LEVEL, float(fallback)))


static func get_detection_range(spec: Dictionary, fallback: float = 0.0) -> float:
	return _get_float(spec, DETECTION_RANGE, fallback)


static func get_detection_arc(spec: Dictionary, fallback: float = 0.0) -> float:
	return _get_float(spec, DETECTION_ARC, fallback)


static func get_upgrade_level(spec: Dictionary, fallback: int = 1) -> int:
	return int(_get_float(spec, UPGRADE_LEVEL, float(fallback)))


static func _normalize_spec(spec: Dictionary) -> Dictionary:
	var normalized := spec.duplicate()
	normalized[POSITION] = _coerce_vector3(normalized.get(POSITION, Vector3.ZERO))
	if normalized.has(SCENE):
		normalized[SCENE] = str(normalized[SCENE]).strip_edges()
	if normalized.has(PROFILE):
		normalized[PROFILE] = str(normalized[PROFILE]).strip_edges()
	if normalized.has(PROJECTILE_SCENE):
		normalized[PROJECTILE_SCENE] = str(normalized[PROJECTILE_SCENE]).strip_edges()
	if normalized.has(TEAM):
		normalized[TEAM] = str(normalized[TEAM]).strip_edges()
	if normalized.has(ROTATION_Y):
		normalized[ROTATION_Y] = float(normalized[ROTATION_Y])
	return normalized


static func _coerce_vector3(value: Variant, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	if value is Vector3:
		return value
	if typeof(value) == TYPE_ARRAY:
		var values: Array = value as Array
		if values.size() >= 3:
			return Vector3(float(values[0]), float(values[1]), float(values[2]))
	if typeof(value) == TYPE_DICTIONARY:
		var dict: Dictionary = value as Dictionary
		return Vector3(
			float(dict.get("x", fallback.x)),
			float(dict.get("y", fallback.y)),
			float(dict.get("z", fallback.z))
		)
	return fallback


static func _get_vector(spec: Dictionary, key: String, fallback: Vector3) -> Vector3:
	var value: Variant = spec.get(key, fallback)
	return value if value is Vector3 else fallback


static func _get_float(spec: Dictionary, key: String, fallback: float) -> float:
	var value: Variant = spec.get(key, fallback)
	return float(value) if value != null else fallback


static func _apply_float_property(node: Node, property_name: String, spec: Dictionary) -> void:
	if not spec.has(property_name):
		return
	if not (property_name in node):
		return
	node.set(property_name, _get_float(spec, property_name, float(node.get(property_name))))


static func _apply_packed_scene_property(node: Node, scene_path: String) -> void:
	if scene_path.is_empty():
		return
	var loaded: Resource = load(scene_path)
	if not (loaded is PackedScene):
		return
	for property_name in ["cannonball_scene", "rocket_scene", "projectile_scene", "bolt_scene", "missile_scene"]:
		if property_name in node:
			node.set(property_name, loaded)
			return
