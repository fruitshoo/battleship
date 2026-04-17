extends RefCounted
class_name ShipAuthoringHelper

## Ship scene authoring utilities.
## These helpers make invisible runtime assumptions inspectable without forcing
## existing ships to move to a marker-only workflow all at once.

const AUTHORING_ROOT := "Authoring"
const BOARDING_ANCHORS := "BoardingAnchors"
const CANNON_SLOTS := "CannonSlots"
const WEAPON_SLOTS := "WeaponSlots"
const CREW_SLOTS := "CrewSlots"
const DECK_AREA := "DeckArea"
const SoldierStateHelper = preload("res://scripts/entities/soldiers/soldier_state_helper.gd")


static func build_summary(ship: Node) -> Dictionary:
	var summary := {
		"name": "",
		"has_authoring_node": false,
		"has_hull_source": false,
		"hull_sources": [],
		"has_soldiers_container": false,
		"contact_areas": {},
		"authoring_markers": {},
		"auto_fit_collision_to_hull": false,
		"auto_fit_contact_areas_to_hull": false,
	}
	if not is_instance_valid(ship):
		return summary

	summary["name"] = str(ship.name)
	summary["has_authoring_node"] = _find_child_named(ship, AUTHORING_ROOT) != null
	var hull_sources := _collect_hull_sources(ship)
	summary["hull_sources"] = hull_sources
	summary["has_hull_source"] = not hull_sources.is_empty()
	summary["has_soldiers_container"] = ship.get_node_or_null("Soldiers") != null
	summary["contact_areas"] = {
		"HitArea": _build_contact_area_summary(ship, "HitArea"),
		"ProximityArea": _build_contact_area_summary(ship, "ProximityArea"),
	}
	summary["authoring_markers"] = {
		BOARDING_ANCHORS: get_authoring_markers(ship, BOARDING_ANCHORS).size(),
		CANNON_SLOTS: get_authoring_markers(ship, CANNON_SLOTS).size(),
		WEAPON_SLOTS: get_authoring_markers(ship, WEAPON_SLOTS).size(),
		CREW_SLOTS: get_authoring_markers(ship, CREW_SLOTS).size(),
		DECK_AREA: 1 if _get_authoring_container(ship, DECK_AREA) != null else 0,
	}
	if "auto_fit_collision_to_hull" in ship and ship.get("auto_fit_collision_to_hull") != null:
		summary["auto_fit_collision_to_hull"] = ship.get("auto_fit_collision_to_hull") == true
	if "auto_fit_contact_areas_to_hull" in ship and ship.get("auto_fit_contact_areas_to_hull") != null:
		summary["auto_fit_contact_areas_to_hull"] = ship.get("auto_fit_contact_areas_to_hull") == true
	return summary


static func validate_ship_authoring(ship: Node, label: String, failures: Array[String]) -> void:
	if not is_instance_valid(ship):
		failures.append("%s authoring validation received invalid ship" % label)
		return
	if not (ship is Node3D):
		failures.append("%s authoring root should be Node3D" % label)
		return

	var summary := build_summary(ship)
	if not bool(summary["has_hull_source"]):
		failures.append("%s authoring missing hull source" % label)
	if not bool(summary["has_soldiers_container"]):
		failures.append("%s authoring missing Soldiers container" % label)

	var contact_areas: Dictionary = summary["contact_areas"]
	for area_name in ["HitArea", "ProximityArea"]:
		var area_summary: Dictionary = contact_areas.get(area_name, {})
		if not bool(area_summary.get("exists", false)):
			failures.append("%s authoring missing %s" % [label, area_name])
			continue
		if not bool(area_summary.get("has_collision_shape", false)):
			failures.append("%s authoring %s missing CollisionShape3D" % [label, area_name])
			continue
		if not bool(area_summary.get("has_box_shape", false)):
			failures.append("%s authoring %s should use BoxShape3D for auto-fit safety" % [label, area_name])
			continue
		var size: Vector3 = area_summary.get("box_size", Vector3.ZERO)
		if size.x <= 0.01 or size.y <= 0.01 or size.z <= 0.01:
			failures.append("%s authoring %s has invalid box size: %s" % [label, area_name, size])

	if bool(summary["auto_fit_contact_areas_to_hull"]) and not bool(summary["has_hull_source"]):
		failures.append("%s authoring auto-fit contact areas requires a hull source" % label)

	_validate_marker_container(ship, BOARDING_ANCHORS, label, failures)
	_validate_marker_container(ship, CANNON_SLOTS, label, failures)
	_validate_marker_container(ship, WEAPON_SLOTS, label, failures)
	_validate_marker_container(ship, CREW_SLOTS, label, failures)

	if ship.has_method("get_ship_authoring_summary"):
		var exposed_summary = ship.call("get_ship_authoring_summary")
		if typeof(exposed_summary) != TYPE_DICTIONARY:
			failures.append("%s authoring summary should be a Dictionary" % label)
	else:
		failures.append("%s authoring summary method missing" % label)


static func get_authoring_markers(ship: Node, container_name: String) -> Array[Node3D]:
	var markers: Array[Node3D] = []
	var container := _get_authoring_container(ship, container_name)
	if container == null:
		return markers
	_collect_marker_descendants(container, markers)
	return markers


static func get_boarding_anchor_local(ship: Node3D, side_sign: float, along_offset: float, fallback_local: Vector3) -> Vector3:
	if not is_instance_valid(ship):
		return fallback_local
	var markers := get_authoring_markers(ship, BOARDING_ANCHORS)
	if markers.is_empty():
		return fallback_local

	var side_markers: Array[Node3D] = []
	for marker in markers:
		if _anchor_matches_side(marker, side_sign):
			side_markers.append(marker)
	var candidates := side_markers if not side_markers.is_empty() else markers

	var best_marker: Node3D = null
	var best_score := INF
	for marker in candidates:
		if not is_instance_valid(marker):
			continue
		var local_pos := ship.to_local(marker.global_position)
		var score := absf(local_pos.z - along_offset)
		if score < best_score:
			best_score = score
			best_marker = marker
	if is_instance_valid(best_marker):
		return ship.to_local(best_marker.global_position)
	return fallback_local


static func get_nearest_boarding_anchor_global(ship: Node3D, reference_global: Vector3, fallback_global: Vector3) -> Vector3:
	if not is_instance_valid(ship):
		return fallback_global
	var markers := get_authoring_markers(ship, BOARDING_ANCHORS)
	if markers.is_empty():
		return fallback_global
	var reference_local := ship.to_local(reference_global)
	var best_marker: Node3D = null
	var best_score := INF
	for marker in markers:
		if not is_instance_valid(marker):
			continue
		var local_pos := ship.to_local(marker.global_position)
		var diff := Vector2(local_pos.x - reference_local.x, local_pos.z - reference_local.z)
		var score := diff.length_squared()
		if score < best_score:
			best_score = score
			best_marker = marker
	if is_instance_valid(best_marker):
		return best_marker.global_position
	return fallback_global


static func get_cannon_slot_transforms(ship: Node3D) -> Array[Transform3D]:
	var transforms: Array[Transform3D] = []
	if not is_instance_valid(ship):
		return transforms
	var named_slots := get_named_cannon_slot_transforms(ship)
	for slot_name in named_slots.keys():
		transforms.append(named_slots[slot_name])
	return transforms


static func get_named_cannon_slot_transforms(ship: Node3D, relative_to: Node3D = null) -> Dictionary:
	var transforms := {}
	if not is_instance_valid(ship):
		return transforms
	var base_inverse := ship.global_transform.affine_inverse()
	if is_instance_valid(relative_to):
		base_inverse = relative_to.global_transform.affine_inverse()
	for marker in get_authoring_markers(ship, CANNON_SLOTS):
		if is_instance_valid(marker):
			transforms[str(marker.name)] = base_inverse * marker.global_transform
	return transforms


static func get_weapon_slot_transforms(ship: Node3D, relative_to: Node3D = null) -> Array[Transform3D]:
	var transforms: Array[Transform3D] = []
	if not is_instance_valid(ship):
		return transforms
	var named_slots := get_named_weapon_slot_transforms(ship, relative_to)
	for slot_name in named_slots.keys():
		transforms.append(named_slots[slot_name])
	return transforms


static func get_named_weapon_slot_transforms(ship: Node3D, relative_to: Node3D = null) -> Dictionary:
	var transforms := get_named_cannon_slot_transforms(ship, relative_to)
	if not is_instance_valid(ship):
		return transforms
	var base_inverse := ship.global_transform.affine_inverse()
	if is_instance_valid(relative_to):
		base_inverse = relative_to.global_transform.affine_inverse()
	for marker in get_authoring_markers(ship, WEAPON_SLOTS):
		if is_instance_valid(marker):
			transforms[str(marker.name)] = base_inverse * marker.global_transform
	return transforms


static func get_crew_slot_transforms(ship: Node3D, relative_to: Node3D = null) -> Array[Transform3D]:
	var transforms: Array[Transform3D] = []
	if not is_instance_valid(ship):
		return transforms
	var base_inverse := ship.global_transform.affine_inverse()
	if is_instance_valid(relative_to):
		base_inverse = relative_to.global_transform.affine_inverse()
	for marker in get_authoring_markers(ship, CREW_SLOTS):
		if is_instance_valid(marker):
			transforms.append(base_inverse * marker.global_transform)
	return transforms


static func get_named_crew_slot_transforms(ship: Node3D, relative_to: Node3D = null) -> Dictionary:
	var transforms := {}
	if not is_instance_valid(ship):
		return transforms
	var base_inverse := ship.global_transform.affine_inverse()
	if is_instance_valid(relative_to):
		base_inverse = relative_to.global_transform.affine_inverse()
	for marker in get_authoring_markers(ship, CREW_SLOTS):
		if is_instance_valid(marker):
			transforms[str(marker.name)] = base_inverse * marker.global_transform
	return transforms


static func get_least_occupied_crew_slot_transform(ship: Node3D, soldiers_node: Node3D, fallback: Transform3D) -> Transform3D:
	if not is_instance_valid(ship) or not is_instance_valid(soldiers_node):
		return fallback
	var slot_transforms := get_crew_slot_transforms(ship, soldiers_node)
	if slot_transforms.is_empty():
		return fallback
	var best_index := 0
	var best_score := INF
	for index in range(slot_transforms.size()):
		var slot_pos: Vector3 = slot_transforms[index].origin
		var score := 0.0
		for child in soldiers_node.get_children():
			var crew_node := child as Node3D
			if not is_instance_valid(crew_node):
				continue
			if _is_dead_soldier_node(crew_node):
				continue
			var diff := crew_node.position - slot_pos
			diff.y = 0.0
			var dist := diff.length()
			if dist < 0.45:
				score += 100.0
			score += maxf(0.0, 1.5 - dist)
		if score < best_score:
			best_score = score
			best_index = index
	return slot_transforms[best_index]


static func _build_contact_area_summary(ship: Node, area_name: String) -> Dictionary:
	var result := {
		"exists": false,
		"has_collision_shape": false,
		"has_box_shape": false,
		"box_size": Vector3.ZERO,
	}
	var area := ship.get_node_or_null(area_name)
	if not (area is Area3D):
		return result
	result["exists"] = true
	var shape_node := area.get_node_or_null("CollisionShape3D")
	if not (shape_node is CollisionShape3D):
		return result
	result["has_collision_shape"] = true
	if shape_node.shape is BoxShape3D:
		result["has_box_shape"] = true
		result["box_size"] = (shape_node.shape as BoxShape3D).size
	return result


static func _validate_marker_container(ship: Node, container_name: String, label: String, failures: Array[String]) -> void:
	var container := _get_authoring_container(ship, container_name)
	if container == null:
		return
	var leaf_nodes: Array[Node3D] = []
	_collect_node3d_leaf_descendants(container, leaf_nodes)
	for leaf in leaf_nodes:
		if not (leaf is Marker3D):
			failures.append("%s authoring %s leaf should be Marker3D: %s" % [label, container_name, leaf.name])
	var marker_names := {}
	for marker in get_authoring_markers(ship, container_name):
		var marker_name := str(marker.name)
		if marker_name.is_empty():
			failures.append("%s authoring %s marker has empty name" % [label, container_name])
			continue
		if marker_names.has(marker_name):
			failures.append("%s authoring %s duplicate marker name: %s" % [label, container_name, marker_name])
			continue
		marker_names[marker_name] = true


static func _collect_hull_sources(ship: Node) -> Array[String]:
	var sources: Array[String] = []
	if "hull_scene" in ship:
		var hull_scene = ship.get("hull_scene")
		if hull_scene is PackedScene:
			var path := (hull_scene as PackedScene).resource_path
			sources.append(path if not path.is_empty() else "PackedScene")
	_collect_hull_child_sources(ship, sources)
	return sources


static func _collect_hull_child_sources(node: Node, sources: Array[String]) -> void:
	for child in node.get_children():
		if str(child.name).contains("Hull"):
			sources.append(str(child.get_path()))
		if child.get_child_count() > 0:
			_collect_hull_child_sources(child, sources)


static func _get_authoring_container(ship: Node, container_name: String) -> Node:
	if not is_instance_valid(ship):
		return null
	var authoring := ship.get_node_or_null(AUTHORING_ROOT)
	if authoring == null:
		authoring = _find_child_named(ship, AUTHORING_ROOT)
	if authoring == null:
		return null
	var direct := authoring.get_node_or_null(container_name)
	if direct != null:
		return direct
	return _find_child_named(authoring, container_name)


static func _find_child_named(node: Node, target_name: String) -> Node:
	for child in node.get_children():
		if str(child.name) == target_name:
			return child
		var nested := _find_child_named(child, target_name)
		if nested != null:
			return nested
	return null


static func _collect_marker_descendants(node: Node, out: Array[Node3D]) -> void:
	for child in node.get_children():
		if child is Marker3D:
			out.append(child as Node3D)
		if child.get_child_count() > 0:
			_collect_marker_descendants(child, out)


static func _collect_node3d_leaf_descendants(node: Node, out: Array[Node3D]) -> void:
	for child in node.get_children():
		if child.get_child_count() > 0:
			_collect_node3d_leaf_descendants(child, out)
		elif child is Node3D:
			out.append(child as Node3D)


static func _anchor_matches_side(marker: Node3D, side_sign: float) -> bool:
	var name_lc := str(marker.name).to_lower()
	if side_sign >= 0.0:
		return name_lc.contains("right") or name_lc.contains("starboard")
	return name_lc.contains("left") or name_lc.contains("port")


static func _is_dead_soldier_node(soldier: Node) -> bool:
	return SoldierStateHelper.is_dead_soldier(soldier)
