extends RefCounted
class_name AIShipLoadoutHelper


static func load_enemy_crew_composition_from_stats(ship, stats: Dictionary) -> void:
	ship.enemy_crew_composition = ShipBlueprintHelper.build_crew_composition(stats)
	ship._enemy_crew_spawn_index = 0
	if not ship.enemy_crew_composition.is_empty():
		ship.max_crew = maxi(ship.max_crew, ship.enemy_crew_composition.size())
		ship.initial_crew_count = clampi(ship.enemy_crew_composition.size(), 1, max(1, ship.max_crew))


static func get_next_enemy_soldier_type(ship) -> String:
	if ship.enemy_crew_composition.is_empty():
		return ship.preferred_soldier_type

	var composition_size: int = ship.enemy_crew_composition.size()
	var next_type: String = ship.enemy_crew_composition[ship._enemy_crew_spawn_index % composition_size]
	ship._enemy_crew_spawn_index = (ship._enemy_crew_spawn_index + 1) % composition_size
	return next_type


static func configure_spawned_soldier(soldier, soldier_type_name: String) -> void:
	if not is_instance_valid(soldier):
		return

	var normalized_type: String = soldier_type_name.strip_edges().to_lower()
	soldier.crew_role = "general"
	soldier.is_melee_only = false
	soldier.is_ranged_only = false

	match normalized_type:
		"melee":
			soldier.is_melee_only = true
		"ranged":
			soldier.is_ranged_only = true
		"daecheolpo":
			soldier.crew_role = "daecheolpo"
			soldier.is_ranged_only = true
		"fire_pot":
			soldier.crew_role = "fire_pot"

	if soldier.is_node_ready():
		soldier._apply_role_loadout()
		soldier._update_role_visual()


static func setup_soldiers(ship) -> void:
	if not ship.soldier_scene:
		return
	var soldiers_node = ship.get_soldiers_container()
	if not soldiers_node:
		return
	for child in soldiers_node.get_children():
		child.queue_free()

	var spawn_count: int = clampi(ship.initial_crew_count, 1, max(1, ship.max_crew))
	for i in range(spawn_count):
		spawn_one_soldier(ship, ship.team)


static func setup_soldiers_staggered(ship) -> void:
	if not ship.soldier_scene or not ship.is_inside_tree():
		return
	var soldiers_node = ship.get_soldiers_container()
	if not soldiers_node:
		return

	for child in soldiers_node.get_children():
		child.queue_free()

	await ship.get_tree().process_frame
	var spawn_count: int = clampi(ship.initial_crew_count, 1, max(1, ship.max_crew))
	for i in range(spawn_count):
		if not ship.is_inside_tree():
			return
		spawn_one_soldier(ship, ship.team)
		await ship.get_tree().process_frame


static func spawn_one_soldier(ship, s_team: String, soldier_type_override: String = "") -> void:
	var soldier = ship.soldier_scene.instantiate()
	var soldier_type_name: String = soldier_type_override.strip_edges().to_lower()
	if soldier_type_name.is_empty():
		soldier_type_name = get_next_enemy_soldier_type(ship) if s_team == "enemy" else ship.preferred_soldier_type

	soldier.team = s_team
	soldier.owned_ship = ship
	soldier.home_ship = ship
	configure_spawned_soldier(soldier, soldier_type_name)
	var soldiers_node: Node = ship.get_soldiers_container()
	if not is_instance_valid(soldiers_node):
		soldier.queue_free()
		return
	soldiers_node.add_child(soldier)
	soldier.set_team(s_team)
	configure_spawned_soldier(soldier, soldier_type_name)
	soldier.transform = get_next_crew_spawn_transform(ship, 1.0, 2.5)


static func get_next_crew_spawn_transform(ship, fallback_x: float, fallback_z: float) -> Transform3D:
	var fallback_deck_height: float = float(ship.get("deck_height")) if ship.get("deck_height") != null else 0.5
	var fallback := Transform3D(Basis.IDENTITY, Vector3(randf_range(-fallback_x, fallback_x), fallback_deck_height, randf_range(-fallback_z, fallback_z)))
	var soldiers_node := ship.get_soldiers_container() as Node3D
	if not is_instance_valid(soldiers_node):
		return fallback
	return ShipAuthoringHelper.get_least_occupied_crew_slot_transform(ship, soldiers_node, fallback)


static func equip_ship_weapons(ship, fallback_team: String = "", gate_by_fleet_upgrades: bool = false) -> void:
	remove_all_cannons(ship)

	var weapon_team := fallback_team.strip_edges()
	if weapon_team.is_empty():
		weapon_team = ship.team
	var fallback_loadout: Array[Dictionary] = []
	if weapon_team == "player":
		fallback_loadout = ShipWeaponLoadoutHelper.get_default_support_cannon_loadout()
	var stats := ShipBlueprintHelper.load_stats(ship.ship_type)
	var loadout := ShipWeaponLoadoutHelper.get_weapon_loadout(stats, fallback_loadout)
	loadout = ShipWeaponLoadoutHelper.apply_authored_weapon_slots(ship, ship, loadout)
	var current_upgrade_levels: Dictionary = {}
	var upgrade_manager = ship.get_node_or_null("/root/UpgradeManager")
	if is_instance_valid(upgrade_manager) and upgrade_manager.get("current_levels") is Dictionary:
		current_upgrade_levels = upgrade_manager.get("current_levels") as Dictionary

	var i := 0
	for spec in loadout:
		if ShipWeaponLoadoutHelper.get_kind(spec) != ShipWeaponLoadoutHelper.KIND_CANNON:
			continue
		var cannon = ShipWeaponLoadoutHelper.instantiate_weapon(spec, ship.cannon_scene)
		if not is_instance_valid(cannon):
			continue
		var fallback_name := "FleetCannon_" + str(i) if weapon_team == "player" else "EnemyCannon_" + str(i)
		cannon.name = ShipWeaponLoadoutHelper.get_node_name(spec, fallback_name)
		ship.add_child(cannon)
		if cannon is Node3D:
			var cannon_node := cannon as Node3D
			cannon_node.position = ShipWeaponLoadoutHelper.get_position(spec)
			if ShipWeaponLoadoutHelper.has_basis(spec):
				var authored_basis: Basis = ShipWeaponLoadoutHelper.get_basis(spec)
				cannon_node.rotation = authored_basis.get_euler()
			else:
				cannon_node.rotation_degrees.y = ShipWeaponLoadoutHelper.get_rotation_y(spec)
		ShipWeaponLoadoutHelper.apply_weapon_config(cannon, spec, weapon_team)

		if gate_by_fleet_upgrades and (ShipWeaponLoadoutHelper.get_required_level(spec, i + 1) > 1 or not ShipWeaponLoadoutHelper.is_unlocked_for_levels(spec, current_upgrade_levels)):
			cannon.visible = false
			cannon.set_process(false)
			cannon.set_physics_process(false)
		i += 1


static func update_children_team_for_capture(ship) -> void:
	ship._update_children_team()
	var soldiers_node: Node = ship.get_soldiers_container()
	if not is_instance_valid(soldiers_node):
		return
	for soldier in soldiers_node.get_children():
		if soldier.has_method("set_team"):
			soldier.set_team("player")
			soldier.owned_ship = ship


static func remove_all_cannons(ship) -> void:
	recursive_remove_cannons(ship)


static func recursive_remove_cannons(node: Node) -> void:
	for child in node.get_children():
		if child.has_method("fire") or "cannonball_scene" in child:
			child.queue_free()
		else:
			recursive_remove_cannons(child)
