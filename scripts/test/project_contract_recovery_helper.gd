extends RefCounted
class_name ProjectContractRecoveryHelper

const SeaDecorSpawnerScript = preload("res://scripts/world/decor/sea_decor_spawner.gd")
const SeaSiteSpawnerScript = preload("res://scripts/world/sea_sites/sea_site_spawner.gd")


static func run_recovery_effect_contract_smoke(owner: Node, failures: Array[String], smoke_scene_path: String, wait_frames_after_attach: int) -> void:
	var packed := load(smoke_scene_path) as PackedScene
	if packed == null:
		failures.append("recovery effect smoke scene load failed: %s" % smoke_scene_path)
		return

	var smoke_root := packed.instantiate()
	if smoke_root == null:
		failures.append("recovery effect smoke scene instantiate failed: %s" % smoke_scene_path)
		return

	owner.add_child(smoke_root)
	PreviewHarnessHelper.setup_common(smoke_root, false, true)
	await _wait_frames(owner, wait_frames_after_attach)

	var player_ship: Node3D = smoke_root.get_node_or_null("PlayerShip") as Node3D
	var level_manager: Node = LevelManagerRegistry.get_level_manager(owner.get_tree())
	if not is_instance_valid(player_ship):
		failures.append("recovery effect smoke missing PlayerShip")
		smoke_root.queue_free()
		await _wait_frames(owner, 1)
		return
	if not is_instance_valid(level_manager):
		failures.append("recovery effect smoke missing LevelManager")
		smoke_root.queue_free()
		await _wait_frames(owner, 1)
		return

	await _run_floating_loot_smoke(owner, failures, smoke_root, player_ship, level_manager)
	await _run_survivor_smoke(owner, failures, smoke_root, player_ship, level_manager)
	await _run_drifting_supply_site_smoke(owner, failures, smoke_root, player_ship, level_manager)
	await _run_static_reward_site_smoke(owner, failures, smoke_root, player_ship, level_manager)
	await _run_static_sea_site_shape_contract(owner, failures, smoke_root)
	await _run_sea_site_spawner_contract(owner, failures, smoke_root, player_ship)
	await _run_sea_decor_contract(owner, failures, smoke_root, player_ship)
	await _run_treasure_chest_smoke(owner, failures, smoke_root, player_ship, level_manager)

	smoke_root.queue_free()
	await _wait_frames(owner, 1)


static func _run_floating_loot_smoke(owner: Node, failures: Array[String], smoke_root: Node, player_ship: Node3D, level_manager: Node) -> void:
	var loot_scene := load("res://scenes/effects/floating_loot.tscn") as PackedScene
	if loot_scene == null:
		failures.append("recovery loot smoke scene load failed")
		return
	var loot := loot_scene.instantiate()
	if loot == null:
		failures.append("recovery loot smoke instantiate failed")
		return
	smoke_root.add_child(loot)
	if loot is Node3D:
		(loot as Node3D).global_position = player_ship.global_position + Vector3(1.5, 0.0, 0.0)
	await _wait_frames(owner, 1)
	var loot_visual := loot.get_node_or_null("Visual") as Node3D
	if loot_visual == null:
		failures.append("recovery loot smoke missing Visual node")
	elif loot.get("visual_waterline_offset") != null and absf(loot_visual.position.y - float(loot.get("visual_waterline_offset"))) > 0.01:
		failures.append("recovery loot smoke does not use its shared waterline visual offset")

	var score_before: int = int(level_manager.get("current_score"))
	var xp_before: int = int(level_manager.get("current_xp"))
	var hull_before: float = float(player_ship.get("hull_hp")) if player_ship.get("hull_hp") != null else 0.0
	if player_ship.get("max_hull_hp") != null:
		player_ship.set("hull_hp", maxf(1.0, float(player_ship.get("max_hull_hp")) * 0.4))
		hull_before = float(player_ship.get("hull_hp"))
	if player_ship.get("rowing_stamina") != null:
		player_ship.set("rowing_stamina", 0.0)
	loot.set("hull_repair_amount", 12.0)
	loot.set("target_player", player_ship)
	loot.call("_collect_by_proximity")
	await _wait_frames(owner, 2)

	if loot.get("is_collected") != true:
		failures.append("recovery loot smoke did not mark loot collected")
	if int(level_manager.get("current_score")) <= score_before:
		failures.append("recovery loot smoke did not grant score")
	if int(level_manager.get("current_xp")) != xp_before:
		failures.append("recovery loot smoke should no longer grant XP")
	if player_ship.get("hull_hp") != null and float(player_ship.get("hull_hp")) <= hull_before:
		failures.append("recovery loot smoke did not repair player hull")


static func _run_survivor_smoke(owner: Node, failures: Array[String], smoke_root: Node, player_ship: Node3D, level_manager: Node) -> void:
	var survivor_scene := load("res://scenes/effects/survivor.tscn") as PackedScene
	if survivor_scene == null:
		failures.append("recovery survivor smoke scene load failed")
		return
	var survivor := survivor_scene.instantiate()
	if survivor == null:
		failures.append("recovery survivor smoke instantiate failed")
		return
	smoke_root.add_child(survivor)
	if survivor is Node3D:
		(survivor as Node3D).global_position = player_ship.global_position + Vector3(-1.5, 0.0, 0.0)
	await _wait_frames(owner, 1)

	if player_ship.get("max_crew_count") != null and player_ship.has_method("get_debug_crew_snapshot"):
		var crew_snapshot: Dictionary = player_ship.call("get_debug_crew_snapshot")
		var alive_before_fill: int = int(crew_snapshot.get("alive_count", 0))
		player_ship.set("max_crew_count", max(alive_before_fill + 1, int(player_ship.get("max_crew_count"))))

	var alive_before: int = 0
	if player_ship.has_method("get_debug_crew_snapshot"):
		alive_before = int(player_ship.call("get_debug_crew_snapshot").get("alive_count", 0))
	var xp_before: int = int(level_manager.get("current_xp")) if is_instance_valid(level_manager) and level_manager.get("current_xp") != null else 0
	survivor.call("_try_collect", player_ship)
	await _wait_frames(owner, 2)
	var alive_after: int = alive_before
	if player_ship.has_method("get_debug_crew_snapshot"):
		alive_after = int(player_ship.call("get_debug_crew_snapshot").get("alive_count", 0))

	if survivor.get("is_collected") != true:
		failures.append("recovery survivor smoke did not mark survivor collected")
	if alive_after <= alive_before:
		failures.append("recovery survivor smoke did not add crew")
	if is_instance_valid(level_manager) and level_manager.get("current_xp") != null and int(level_manager.get("current_xp")) <= xp_before:
		failures.append("recovery survivor smoke did not grant rescue XP")

	await _run_survivor_full_crew_trains_existing_roster(owner, failures, smoke_root, player_ship)


static func _run_treasure_chest_smoke(owner: Node, failures: Array[String], smoke_root: Node, player_ship: Node3D, level_manager: Node) -> void:
	var chest_scene := load("res://scenes/effects/treasure_chest.tscn") as PackedScene
	if chest_scene == null:
		failures.append("recovery treasure smoke scene load failed")
		return
	var chest := chest_scene.instantiate()
	if chest == null:
		failures.append("recovery treasure smoke instantiate failed")
		return
	var original_levels: Dictionary = {}
	if is_instance_valid(UpgradeManager):
		original_levels = UpgradeManager.current_levels.duplicate(true)
		for upgrade_id in UpgradeManager.current_levels.keys():
			UpgradeManager.current_levels[upgrade_id] = 0
		UpgradeManager.current_levels["cannon"] = 5
		UpgradeManager.current_levels["cannon_damage"] = 1
		UpgradeManager.current_levels["crew_reserve"] = 1
	else:
		failures.append("recovery treasure smoke missing UpgradeManager")
	if chest.get("debug_forced_reward_count") != null:
		chest.set("debug_forced_reward_count", 3)
	smoke_root.add_child(chest)
	if chest.get_node_or_null("CollectionHint") != null:
		failures.append("recovery treasure smoke should not show a pickup range hint")
	var chest_visual := chest.get_node_or_null("MeshInstance3D") as Node3D
	if chest_visual == null:
		failures.append("recovery treasure smoke missing visual mesh")
	elif chest.get("visual_waterline_offset") != null and absf(chest_visual.position.y - float(chest.get("visual_waterline_offset"))) > 0.01:
		failures.append("recovery treasure smoke does not use its shared waterline visual offset")
	if chest.has_method("_get_effective_magnet_range"):
		var effective_magnet_range: float = float(chest.call("_get_effective_magnet_range", player_ship))
		if effective_magnet_range > 8.0:
			failures.append("recovery treasure smoke magnet range too large: %.2f" % effective_magnet_range)
	var collection_edge_distance: float = 0.35
	if chest.has_method("_get_effective_collection_range"):
		collection_edge_distance = maxf(0.1, float(chest.call("_get_effective_collection_range", player_ship)) * 0.5)
	if chest is Node3D:
		var direction := Vector3.RIGHT
		var ship_radius := 4.0
		if player_ship.has_method("get_directional_collision_radius"):
			ship_radius = float(player_ship.call("get_directional_collision_radius", direction))
		(chest as Node3D).global_position = player_ship.global_position + direction * (ship_radius + collection_edge_distance)
	await _wait_frames(owner, 3)

	if is_instance_valid(chest):
		if chest.get("_is_collected") != true:
			failures.append("recovery treasure smoke did not mark chest collected from reduced range")
		if not chest.is_queued_for_deletion():
			failures.append("recovery treasure smoke did not queue chest for deletion")
	if is_instance_valid(UpgradeManager):
		if int(UpgradeManager.current_levels.get("cannon_damage", 0)) < 4:
			failures.append("recovery treasure smoke did not auto-upgrade an owned upgrade")
		if int(UpgradeManager.current_levels.get("crew_reserve", 0)) != 1:
			failures.append("recovery treasure smoke should ignore disabled owned upgrades")
	var popup_found := false
	for popup in owner.get_tree().get_nodes_in_group("treasure_reward_popup"):
		popup_found = true
		if is_instance_valid(popup):
			popup.queue_free()
	if not popup_found:
		failures.append("recovery treasure smoke did not show reward result popup")
	elif not owner.get_tree().paused:
		failures.append("recovery treasure smoke should pause while reward result popup is visible")
	await _wait_frames(owner, 1)
	if owner.get_tree().paused:
		failures.append("recovery treasure smoke did not restore pause after reward result popup closed")
	var upgrade_ui: Variant = level_manager.get("_upgrade_ui_instance") if is_instance_valid(level_manager) else null
	if is_instance_valid(upgrade_ui):
		failures.append("recovery treasure smoke should not open upgrade choice UI")
		upgrade_ui.queue_free()
		level_manager.set("_upgrade_ui_instance", null)
	if is_instance_valid(UpgradeManager) and not original_levels.is_empty():
		UpgradeManager.current_levels = original_levels.duplicate(true)
		UpgradeManager.upgrade_applied.emit("cannon_damage", int(UpgradeManager.current_levels.get("cannon_damage", 0)))


static func _run_drifting_supply_site_smoke(owner: Node, failures: Array[String], smoke_root: Node, player_ship: Node3D, level_manager: Node) -> void:
	var site_scene := load("res://scenes/world/sea_sites/drifting_supply_site.tscn") as PackedScene
	if site_scene == null:
		failures.append("recovery drifting supply site scene load failed")
		return
	var site := site_scene.instantiate()
	if site == null:
		failures.append("recovery drifting supply site instantiate failed")
		return
	smoke_root.add_child(site)
	if site is Node3D:
		(site as Node3D).global_position = player_ship.global_position + Vector3(2.5, 0.0, 0.0)
	await _wait_frames(owner, 1)

	var hull_before: float = 0.0
	if player_ship.get("hull_hp") != null and player_ship.get("max_hull_hp") != null:
		player_ship.set("hull_hp", maxf(1.0, float(player_ship.get("max_hull_hp")) * 0.45))
		hull_before = float(player_ship.get("hull_hp"))
	if site.has_method("_collect"):
		site.call("_collect", player_ship)
	await _wait_frames(owner, 2)

	if site.get("is_collected") != true:
		failures.append("recovery drifting supply site did not mark collected")
	if player_ship.get("hull_hp") != null and float(player_ship.get("hull_hp")) <= hull_before:
		failures.append("recovery drifting supply site did not repair player hull")
	var unexpected_upgrade_ui: Variant = level_manager.get("_upgrade_ui_instance")
	if is_instance_valid(unexpected_upgrade_ui):
		failures.append("recovery drifting supply site should repair hull instead of opening upgrade choices")
		unexpected_upgrade_ui.queue_free()
		level_manager.set("_upgrade_ui_instance", null)
	owner.get_tree().paused = false


static func _run_static_reward_site_smoke(owner: Node, failures: Array[String], smoke_root: Node, player_ship: Node3D, level_manager: Node) -> void:
	var site_scene := load("res://scenes/world/sea_sites/reef_marker_site.tscn") as PackedScene
	if site_scene == null:
		failures.append("recovery static reward site scene load failed")
		return
	var site := site_scene.instantiate()
	if site == null:
		failures.append("recovery static reward site instantiate failed")
		return
	smoke_root.add_child(site)
	if site is Node3D:
		(site as Node3D).global_position = player_ship.global_position + Vector3(3.5, 0.0, 0.0)
	await _wait_frames(owner, 1)

	if site.has_method("_collect"):
		site.call("_collect", player_ship)
	await _wait_frames(owner, 2)

	if site.get("is_collected") != true:
		failures.append("recovery static reward site did not mark collected")
	var upgrade_ui: Variant = level_manager.get("_upgrade_ui_instance")
	if is_instance_valid(upgrade_ui):
		failures.append("recovery static reward site should grant a minor stat bonus instead of opening upgrade choices")
		upgrade_ui.queue_free()
		level_manager.set("_upgrade_ui_instance", null)
	var bonus_totals: Variant = player_ship.get_meta("sea_site_bonus_totals", {})
	if not (bonus_totals is Dictionary) or (bonus_totals as Dictionary).is_empty():
		failures.append("recovery static reward site did not grant a minor stat bonus")
	if site.is_queued_for_deletion():
		failures.append("recovery static reward site queued for deletion after reward")
	if site.get("reward_type") != "minor_stat_bonus":
		failures.append("recovery static reward reef should be a minor-stat-bonus site")
	site.queue_free()
	owner.get_tree().paused = false


static func _run_static_sea_site_shape_contract(owner: Node, failures: Array[String], smoke_root: Node) -> void:
	var checks := [
		{
			"path": "res://scenes/world/sea_sites/reef_marker_site.tscn",
			"label": "reef marker site",
			"min_scale": 1.25,
			"min_visual_y": 0.24,
			"min_radius": 9.0,
			"min_world_width": 3.8,
			"min_top_y": 2.5,
			"min_bottom_y": -0.3,
			"reward_type": "minor_stat_bonus",
		},
		{
			"path": "res://scenes/world/sea_sites/tiny_islet_site.tscn",
			"label": "tiny islet site",
			"min_scale": 1.35,
			"min_visual_y": 0.36,
			"min_radius": 10.0,
			"min_world_width": 7.0,
			"min_top_y": 1.0,
			"min_bottom_y": -0.3,
			"reward_type": "minor_stat_bonus",
		},
		{
			"path": "res://scenes/world/sea_sites/temporary_outpost_site.tscn",
			"label": "temporary outpost site",
			"min_scale": 1.25,
			"min_visual_y": 0.18,
			"min_radius": 9.5,
			"min_world_width": 4.5,
			"min_top_y": 3.0,
			"min_bottom_y": -0.3,
			"reward_type": "minor_stat_bonus",
		},
	]

	for check in checks:
		await _run_single_static_sea_site_shape_check(owner, failures, smoke_root, check)


static func _run_single_static_sea_site_shape_check(owner: Node, failures: Array[String], smoke_root: Node, check: Dictionary) -> void:
	var site_path := str(check.get("path", ""))
	var label := str(check.get("label", site_path))
	var site_scene := load(site_path) as PackedScene
	if site_scene == null:
		failures.append("recovery %s load failed" % label)
		return
	var site := site_scene.instantiate() as Node3D
	if site == null:
		failures.append("recovery %s instantiate failed" % label)
		return
	smoke_root.add_child(site)
	await _wait_frames(owner, 1)

	var visual := site.get_node_or_null("Visual") as Node3D
	if not is_instance_valid(visual):
		failures.append("recovery %s missing Visual node" % label)
	else:
		var visual_scale := visual.scale
		var smallest_axis := minf(visual_scale.x, minf(visual_scale.y, visual_scale.z))
		if smallest_axis < float(check.get("min_scale", 1.0)):
			failures.append("recovery %s visual scale too small: %.2f" % [label, smallest_axis])
		if visual.position.y < float(check.get("min_visual_y", 0.0)):
			failures.append("recovery %s visual is too low: %.2f" % [label, visual.position.y])
		var bounds := _compute_mesh_tree_aabb(visual)
		if bounds.size == Vector3.ZERO:
			failures.append("recovery %s has no visible mesh bounds" % label)
		else:
			var horizontal_width := maxf(bounds.size.x, bounds.size.z)
			if horizontal_width < float(check.get("min_world_width", 0.0)):
				failures.append("recovery %s visual bounds too narrow: %.2f" % [label, horizontal_width])
			if bounds.end.y < float(check.get("min_top_y", 0.0)):
				failures.append("recovery %s visual top is too low: %.2f" % [label, bounds.end.y])
			if bounds.position.y < float(check.get("min_bottom_y", -INF)):
				failures.append("recovery %s visual bottom is too submerged: %.2f" % [label, bounds.position.y])

	var collision := site.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if not is_instance_valid(collision):
		failures.append("recovery %s missing CollisionShape3D" % label)
	elif collision.shape is SphereShape3D:
		var sphere := collision.shape as SphereShape3D
		if sphere.radius < float(check.get("min_radius", 0.0)):
			failures.append("recovery %s interaction radius too small: %.2f" % [label, sphere.radius])
	else:
		failures.append("recovery %s interaction shape is not a sphere" % label)

	if not site.is_in_group("sea_site"):
		failures.append("recovery %s missing sea_site group" % label)
	if not site.is_in_group("static_reward_site"):
		failures.append("recovery %s missing static_reward_site group" % label)
	if site.get("is_collected") != null and site.get("is_collected") == true:
		failures.append("recovery %s should start uncollected" % label)
	if str(site.get("reward_type")) != str(check.get("reward_type", "")):
		failures.append("recovery %s reward type mismatch: %s" % [label, str(site.get("reward_type"))])

	site.queue_free()
	await _wait_frames(owner, 1)


static func _compute_mesh_tree_aabb(root: Node3D) -> AABB:
	var found_any := false
	var combined := AABB()
	for child in _collect_mesh_instances(root):
		if not is_instance_valid(child.mesh):
			continue
		var child_aabb := child.mesh.get_aabb()
		for local_corner in _aabb_corners(child_aabb):
			var root_space_point := root.to_local(child.to_global(local_corner))
			if not found_any:
				combined = AABB(root_space_point, Vector3.ZERO)
				found_any = true
			else:
				combined = combined.expand(root_space_point)
	return combined if found_any else AABB()


static func _collect_mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		meshes.append(root as MeshInstance3D)
	for child in root.get_children():
		meshes.append_array(_collect_mesh_instances(child))
	return meshes


static func _has_collision_shape(root: Node) -> bool:
	if root is CollisionShape3D:
		return true
	for child in root.get_children():
		if _has_collision_shape(child):
			return true
	return false


static func _has_shader_material(root: Node) -> bool:
	if root is MeshInstance3D:
		var mesh_instance := root as MeshInstance3D
		if mesh_instance.material_override is ShaderMaterial:
			return true
		if mesh_instance.mesh != null:
			var material := mesh_instance.mesh.surface_get_material(0)
			if material is ShaderMaterial:
				return true
	for child in root.get_children():
		if _has_shader_material(child):
			return true
	return false


static func _get_first_instance_shader_float(root: Node, parameter_name: String) -> float:
	if root is MeshInstance3D:
		var mesh_instance := root as MeshInstance3D
		var value: Variant = mesh_instance.get_instance_shader_parameter(parameter_name)
		if value != null:
			return float(value)
	for child in root.get_children():
		var child_value := _get_first_instance_shader_float(child, parameter_name)
		if child_value >= 0.0:
			return child_value
	return -1.0


static func _shader_source_contains_any(shader_path: String, tokens: Array[String]) -> bool:
	var source := FileAccess.get_file_as_string(shader_path)
	if source.is_empty():
		return false
	for token in tokens:
		if source.contains(token):
			return true
	return false


static func _aabb_corners(aabb: AABB) -> Array[Vector3]:
	var p := aabb.position
	var s := aabb.size
	return [
		p,
		p + Vector3(s.x, 0.0, 0.0),
		p + Vector3(0.0, s.y, 0.0),
		p + Vector3(0.0, 0.0, s.z),
		p + Vector3(s.x, s.y, 0.0),
		p + Vector3(s.x, 0.0, s.z),
		p + Vector3(0.0, s.y, s.z),
		p + s,
	]


static func _run_sea_site_spawner_contract(owner: Node, failures: Array[String], smoke_root: Node, player_ship: Node3D) -> void:
	var spawner := Node.new()
	spawner.name = "SeaSiteSpawnerSmoke"
	spawner.set_script(SeaSiteSpawnerScript)
	spawner.set("enabled", false)
	spawner.set("_player", player_ship)
	smoke_root.add_child(spawner)
	await _wait_frames(owner, 1)

	if not spawner.has_method("debug_spawn_site"):
		failures.append("recovery sea site spawner missing debug_spawn_site")
		spawner.queue_free()
		await _wait_frames(owner, 1)
		return
	if not spawner.has_method("_is_spawn_direction_wind_friendly"):
		failures.append("recovery sea site spawner missing wind-friendly spawn policy")
	else:
		spawner.set("wind_spawn_bias_enabled", true)
		spawner.set("min_spawn_wind_alignment", -0.35)
		spawner.set("wind_bias_relax_attempts", 10)
		if bool(spawner.call("_is_spawn_direction_wind_friendly", Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, -1.0), 0)):
			failures.append("recovery sea site spawner allowed a direct headwind site before relax")
		if not bool(spawner.call("_is_spawn_direction_wind_friendly", Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, -1.0), 0)):
			failures.append("recovery sea site spawner rejected a crosswind site")
		if not bool(spawner.call("_is_spawn_direction_wind_friendly", Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, -1.0), 10)):
			failures.append("recovery sea site spawner did not relax headwind bias after fallback attempts")

	var site := spawner.call("debug_spawn_site", 32.0, 0.0) as Node3D
	await _wait_frames(owner, 1)
	if not is_instance_valid(site):
		failures.append("recovery sea site spawner debug spawn failed")
	else:
		if not site.is_in_group("sea_site"):
			failures.append("recovery sea site spawner spawned node missing sea_site group")
		if not site.is_in_group("static_reward_site"):
			failures.append("recovery sea site spawner did not spawn a static reward site by default")
		if site.is_in_group("drifting_supply_site"):
			failures.append("recovery sea site spawner default spawned drifting supply site")
		if absf(site.global_position.y) > 0.05:
			failures.append("recovery sea site spawner spawned site off waterline: %.2f" % site.global_position.y)
		site.queue_free()

	spawner.queue_free()
	await _wait_frames(owner, 1)


static func _run_sea_decor_contract(owner: Node, failures: Array[String], smoke_root: Node, player_ship: Node3D) -> void:
	var decor_scene := load("res://scenes/world/decor/sea_rock_cluster.tscn") as PackedScene
	if decor_scene == null:
		failures.append("recovery sea rock decor scene load failed")
		return
	var decor := decor_scene.instantiate() as Node3D
	if decor == null:
		failures.append("recovery sea rock decor instantiate failed")
		return
	smoke_root.add_child(decor)
	await _wait_frames(owner, 1)

	if not decor.is_in_group("sea_decor"):
		failures.append("recovery sea rock decor missing sea_decor group")
	if not decor.is_in_group("sea_rock_decor"):
		failures.append("recovery sea rock decor missing sea_rock_decor group")
	if decor.is_in_group("sea_site"):
		failures.append("recovery sea rock decor should not be a sea_site")
	if decor.is_in_group("static_reward_site"):
		failures.append("recovery sea rock decor should not be a reward site")
	var hazard_area := decor.get_node_or_null("RockHazardArea") as Area3D
	if not is_instance_valid(hazard_area):
		failures.append("recovery sea rock decor missing hazard area")
	elif hazard_area is Area3D and hazard_area.get_node_or_null("RockHazardShape") == null:
		failures.append("recovery sea rock decor missing hazard collision shape")
	if not decor.has_method("set_rock_view_fade_alpha"):
		failures.append("recovery sea rock decor missing view fade hook")
	var visual := decor.get_node_or_null("Visual") as Node3D
	if not is_instance_valid(visual):
		failures.append("recovery sea rock decor missing Visual node")
	else:
		if not _has_shader_material(visual):
			failures.append("recovery sea rock decor missing procedural shader material")
		if _shader_source_contains_any("res://assets/shaders/sea_rock_procedural.gdshader", ["edge_", "crack_", "voronoi", "strata", "blend_mix", "view_fade_alpha", "ALPHA"]):
			failures.append("recovery sea rock shader restored removed edge/crack/stripe/transparent pattern")
		if decor.has_method("set_rock_view_fade_alpha"):
			decor.call("set_rock_view_fade_alpha", 0.0)
		var bounds := _compute_mesh_tree_aabb(visual)
		if bounds.size == Vector3.ZERO:
			failures.append("recovery sea rock decor has no visible mesh bounds")
		else:
			var horizontal_width := maxf(bounds.size.x, bounds.size.z)
			if horizontal_width < 3.0:
				failures.append("recovery sea rock decor visual bounds too narrow: %.2f" % horizontal_width)
			if bounds.end.y < 1.2:
				failures.append("recovery sea rock decor visual top is too low: %.2f" % bounds.end.y)
			if bounds.position.y > 0.15:
				failures.append("recovery sea rock decor is not waterline-submerged enough: %.2f" % bounds.position.y)
			if bounds.position.y > -0.8:
				failures.append("recovery sea rock decor underwater depth is too shallow: %.2f" % bounds.position.y)
	decor.queue_free()

	var spawner := Node.new()
	spawner.name = "SeaDecorSpawnerSmoke"
	spawner.set_script(SeaDecorSpawnerScript)
	spawner.set("enabled", false)
	spawner.set("_player", player_ship)
	smoke_root.add_child(spawner)
	await _wait_frames(owner, 1)

	if float(spawner.get("despawn_distance")) < 300.0:
		failures.append("recovery sea decor spawner despawn distance too short: %.2f" % float(spawner.get("despawn_distance")))

	if not spawner.has_method("debug_spawn_decor"):
		failures.append("recovery sea decor spawner missing debug_spawn_decor")
	else:
		var contact_decor := spawner.call("debug_spawn_decor", 0.0, 0.0) as Node3D
		await _wait_frames(owner, 1)
		if not is_instance_valid(contact_decor):
			failures.append("recovery sea decor contact spawn failed")
		else:
			if contact_decor is Area3D:
				failures.append("recovery sea rock decor should not be collectible Area3D")
			if contact_decor.get("is_collected") != null:
				failures.append("recovery sea rock decor should not expose collectible state")
			if spawner.has_method("_cleanup_active_decor"):
				spawner.call("_cleanup_active_decor")
				await _wait_frames(owner, 2)
				if not is_instance_valid(contact_decor) or contact_decor.is_queued_for_deletion():
					failures.append("recovery sea rock decor was removed while touching player")
			if is_instance_valid(contact_decor):
				contact_decor.queue_free()

		var spawned_decor := spawner.call("debug_spawn_decor", 36.0, 0.0) as Node3D
		await _wait_frames(owner, 1)
		if not is_instance_valid(spawned_decor):
			failures.append("recovery sea decor spawner debug spawn failed")
		else:
			if not spawned_decor.is_in_group("sea_decor"):
				failures.append("recovery sea decor spawner spawned node missing sea_decor group")
			if spawned_decor.is_in_group("sea_site"):
				failures.append("recovery sea decor spawner spawned decor as sea_site")
			if absf(spawned_decor.global_position.y) > 0.05:
				failures.append("recovery sea decor spawner spawned decor off waterline: %.2f" % spawned_decor.global_position.y)
			spawned_decor.queue_free()

	spawner.queue_free()
	await _wait_frames(owner, 1)


static func _run_survivor_full_crew_trains_existing_roster(owner: Node, failures: Array[String], smoke_root: Node, player_ship: Node3D) -> void:
	var survivor_scene := load("res://scenes/effects/survivor.tscn") as PackedScene
	if survivor_scene == null:
		failures.append("recovery survivor full crew scene load failed")
		return
	var survivor := survivor_scene.instantiate()
	if survivor == null:
		failures.append("recovery survivor full crew instantiate failed")
		return
	smoke_root.add_child(survivor)
	if survivor is Node3D:
		(survivor as Node3D).global_position = player_ship.global_position + Vector3(-2.5, 0.0, 0.0)
	await _wait_frames(owner, 1)

	var alive_before: int = 0
	if player_ship.has_method("get_debug_crew_snapshot"):
		alive_before = int(player_ship.call("get_debug_crew_snapshot").get("alive_count", 0))
	var training_before := _get_player_crew_training_total(player_ship)
	var original_max_crew_count = null
	if player_ship.get("max_crew_count") != null:
		original_max_crew_count = player_ship.get("max_crew_count")
		player_ship.set("max_crew_count", alive_before)

	survivor.call("_try_collect", player_ship)
	await _wait_frames(owner, 2)

	if original_max_crew_count != null:
		player_ship.set("max_crew_count", original_max_crew_count)

	var alive_after: int = alive_before
	if player_ship.has_method("get_debug_crew_snapshot"):
		alive_after = int(player_ship.call("get_debug_crew_snapshot").get("alive_count", 0))
	var training_after := _get_player_crew_training_total(player_ship)
	if survivor.get("is_collected") != true:
		failures.append("recovery survivor full crew did not collect for overflow training")
	if alive_after != alive_before:
		failures.append("recovery survivor full crew changed roster size instead of training existing crew")
	if training_after <= training_before:
		failures.append("recovery survivor full crew did not train an existing soldier")
	await _run_survivor_overcap_does_not_expand_respawn_target(owner, failures, player_ship)


static func _get_player_crew_training_total(player_ship: Node3D) -> float:
	var total := 0.0
	for soldier in EntityRegistry.get_soldiers_by_ship(player_ship):
		if not is_instance_valid(soldier):
			continue
		if soldier.has_method("is_player_team_soldier") and soldier.call("is_player_team_soldier") != true:
			continue
		if not soldier.has_method("is_player_team_soldier") and str(soldier.get("team")) != "player":
			continue
		var level := 1
		if soldier.has_method("get_soldier_level_value"):
			level = int(soldier.call("get_soldier_level_value"))
		else:
			level = int(soldier.get_meta("soldier_level", 1))
		var xp := 0.0
		if soldier.has_method("get_soldier_xp_value"):
			xp = float(soldier.call("get_soldier_xp_value"))
		else:
			xp = float(soldier.get_meta("soldier_xp", 0.0))
		total += float(level * 1000) + xp
	return total


static func _run_survivor_overcap_does_not_expand_respawn_target(owner: Node, failures: Array[String], player_ship: Node3D) -> void:
	if not player_ship.has_method("add_respawn_crew") or not player_ship.has_method("get_debug_crew_snapshot"):
		return
	var alive_before: int = int(player_ship.call("get_debug_crew_snapshot").get("alive_count", 0))
	if alive_before <= 1 or player_ship.get("max_crew_count") == null:
		return
	var original_max_crew_count = player_ship.get("max_crew_count")
	player_ship.set("max_crew_count", alive_before - 1)
	var added: bool = bool(player_ship.call("add_respawn_crew"))
	await _wait_frames(owner, 2)
	var alive_after: int = int(player_ship.call("get_debug_crew_snapshot").get("alive_count", 0))
	player_ship.set("max_crew_count", original_max_crew_count)
	if added:
		failures.append("recovery respawn added crew while survivor overcap roster was still above max")
	if alive_after != alive_before:
		failures.append("recovery respawn changed crew count while survivor overcap roster was still above max")
	await _run_incapacitated_captain_blocks_duplicate_respawn(owner, failures, player_ship)


static func _run_incapacitated_captain_blocks_duplicate_respawn(owner: Node, failures: Array[String], player_ship: Node3D) -> void:
	if not player_ship.has_method("add_respawn_crew") or player_ship.get("max_crew_count") == null:
		return
	var captain := _find_player_captain(player_ship)
	if not is_instance_valid(captain):
		return

	var original_max_crew_count = player_ship.get("max_crew_count")
	var before_roster_ids := _get_player_roster_instance_ids(player_ship)
	var before_roster_count: int = before_roster_ids.size()
	player_ship.set("max_crew_count", before_roster_count + 1)

	SoldierLifecycleHelper.incapacitate(captain)
	await _wait_frames(owner, 2)
	var captains_after_incapacitate := _count_player_captains_in_roster(player_ship)
	var added: bool = bool(player_ship.call("add_respawn_crew"))
	await _wait_frames(owner, 2)
	var captains_after_respawn := _count_player_captains_in_roster(player_ship)
	SoldierLifecycleHelper.heal_full(captain)
	await _wait_frames(owner, 2)
	var captains_after_recovery := _count_player_captains_in_roster(player_ship)
	var spawned_replacement := _find_new_player_roster_soldier(player_ship, before_roster_ids)
	if is_instance_valid(spawned_replacement):
		EntityRegistry.unregister_soldier(spawned_replacement)
		spawned_replacement.queue_free()
	player_ship.set("max_crew_count", original_max_crew_count)
	await _wait_frames(owner, 1)

	if captains_after_incapacitate != 1:
		failures.append("recovery incapacitated captain did not remain reserved in captain roster: %d" % captains_after_incapacitate)
	if not added:
		failures.append("recovery respawn did not add regular crew with incapacitated captain reserved")
	if captains_after_respawn != 1:
		failures.append("recovery respawn created duplicate captain while original captain was incapacitated: %d" % captains_after_respawn)
	if captains_after_recovery != 1:
		failures.append("recovery captain count was not normalized after incapacitated captain recovered: %d" % captains_after_recovery)


static func _find_player_captain(player_ship: Node3D) -> Node:
	for soldier in EntityRegistry.get_soldiers_by_ship(player_ship):
		if not _counts_as_player_roster_member(soldier):
			continue
		if _is_captain_node(soldier):
			return soldier
	return null


static func _count_player_captains_in_roster(player_ship: Node3D) -> int:
	var count := 0
	for soldier in EntityRegistry.get_soldiers_by_ship(player_ship):
		if not _counts_as_player_roster_member(soldier):
			continue
		if _is_captain_node(soldier):
			count += 1
	return count


static func _get_player_roster_instance_ids(player_ship: Node3D) -> Dictionary:
	var ids := {}
	for soldier in EntityRegistry.get_soldiers_by_ship(player_ship):
		if _counts_as_player_roster_member(soldier):
			ids[soldier.get_instance_id()] = true
	return ids


static func _find_new_player_roster_soldier(player_ship: Node3D, known_ids: Dictionary) -> Node:
	for soldier in EntityRegistry.get_soldiers_by_ship(player_ship):
		if not _counts_as_player_roster_member(soldier):
			continue
		if not known_ids.has(soldier.get_instance_id()):
			return soldier
	return null


static func _counts_as_player_roster_member(soldier: Node) -> bool:
	if not is_instance_valid(soldier):
		return false
	if soldier.has_method("is_player_team_soldier"):
		if soldier.call("is_player_team_soldier") != true:
			return false
	elif str(soldier.get("team")) != "player":
		return false
	return SoldierStateHelper.is_alive_soldier(soldier) or SoldierStateHelper.is_incapacitated_soldier(soldier)


static func _is_captain_node(soldier: Node) -> bool:
	if not is_instance_valid(soldier):
		return false
	if soldier.get("is_captain") != null:
		return soldier.get("is_captain") == true
	return soldier.get_meta("is_captain", false) == true


static func _wait_frames(owner: Node, frames: int) -> void:
	if frames <= 0 or not is_instance_valid(owner):
		return
	for _index in range(frames):
		await owner.get_tree().process_frame
