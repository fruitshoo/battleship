extends RefCounted
class_name ProjectContractRuntimeHelper

const EntityRegistry = preload("res://scripts/helpers/entity_registry.gd")
const LevelManagerRegistry = preload("res://scripts/helpers/level_manager_registry.gd")
const PreviewHarnessHelper = preload("res://scripts/test/preview_harness_helper.gd")


static func run_runtime_smoke(owner: Node, failures: Array[String], smoke_scene_path: String, wait_frames_after_attach: int, wait_frames_after_spawn: int, smoke_spawn_boss: bool, smoke_spawn_final_boss: bool, smoke_spawn_ship_types: Array[String], smoke_spawn_launcher_scenes: Array[String], smoke_spawn_projectile_scenes: Array[String]) -> void:
	var packed := load(smoke_scene_path) as PackedScene
	if packed == null:
		failures.append("smoke scene load failed: %s" % smoke_scene_path)
		return

	if not smoke_spawn_boss and not smoke_spawn_final_boss and smoke_spawn_ship_types.is_empty() and smoke_spawn_launcher_scenes.is_empty() and smoke_spawn_projectile_scenes.is_empty():
		failures.append("no smoke mode enabled")
		return

	if smoke_spawn_boss:
		await _run_single_smoke_pass(owner, failures, packed, smoke_scene_path, wait_frames_after_attach, wait_frames_after_spawn, "debug_spawn_mid_boss", "mid boss")
	if smoke_spawn_final_boss:
		await _run_single_smoke_pass(owner, failures, packed, smoke_scene_path, wait_frames_after_attach, wait_frames_after_spawn, "debug_spawn_final_boss", "final boss")
	for ship_type_name in smoke_spawn_ship_types:
		await _run_ship_variant_smoke_pass(owner, failures, packed, smoke_scene_path, wait_frames_after_attach, wait_frames_after_spawn, str(ship_type_name))
	for launcher_scene_path in smoke_spawn_launcher_scenes:
		await _run_launcher_smoke_pass(owner, failures, packed, smoke_scene_path, wait_frames_after_attach, wait_frames_after_spawn, str(launcher_scene_path))
	for projectile_scene_path in smoke_spawn_projectile_scenes:
		await _run_projectile_smoke_pass(owner, failures, packed, smoke_scene_path, wait_frames_after_attach, wait_frames_after_spawn, str(projectile_scene_path))


static func _run_single_smoke_pass(owner: Node, failures: Array[String], packed: PackedScene, smoke_scene_path: String, wait_frames_after_attach: int, wait_frames_after_spawn: int, spawn_method: String, label: String) -> void:
	var smoke_root := packed.instantiate()
	if smoke_root == null:
		failures.append("smoke scene instantiate failed: %s" % smoke_scene_path)
		return

	owner.add_child(smoke_root)
	PreviewHarnessHelper.setup_common(smoke_root, false, true)
	await _wait_frames(owner, wait_frames_after_attach)

	var level_manager: Node = LevelManagerRegistry.get_level_manager(owner.get_tree())
	if not is_instance_valid(level_manager):
		failures.append("level manager registry lookup failed during %s smoke" % label)

	var player_ship: Node3D = smoke_root.get_node_or_null("PlayerShip") as Node3D
	if not is_instance_valid(player_ship):
		failures.append("preview base is missing PlayerShip for %s smoke" % label)

	var spawner: Node = smoke_root.get_node_or_null("EnemySpawner")
	if not is_instance_valid(spawner):
		failures.append("preview base is missing EnemySpawner for %s smoke" % label)
	else:
		var spawned_boss: Node3D = null
		if spawner.has_method(spawn_method):
			spawned_boss = spawner.call(spawn_method) as Node3D
			await _wait_frames(owner, wait_frames_after_spawn)
		_validate_spawned_boss(failures, spawned_boss, label)

	_validate_registry_smoke(failures, player_ship, label)

	smoke_root.queue_free()
	await _wait_frames(owner, 1)


static func _run_ship_variant_smoke_pass(owner: Node, failures: Array[String], packed: PackedScene, smoke_scene_path: String, wait_frames_after_attach: int, wait_frames_after_spawn: int, ship_type_name: String) -> void:
	var smoke_root := packed.instantiate()
	if smoke_root == null:
		failures.append("smoke scene instantiate failed: %s" % smoke_scene_path)
		return

	owner.add_child(smoke_root)
	PreviewHarnessHelper.setup_common(smoke_root, false, true)
	await _wait_frames(owner, wait_frames_after_attach)

	var player_ship: Node3D = smoke_root.get_node_or_null("PlayerShip") as Node3D
	if not is_instance_valid(player_ship):
		failures.append("preview base is missing PlayerShip for %s smoke" % ship_type_name)

	var spawner: Node = smoke_root.get_node_or_null("EnemySpawner")
	if not is_instance_valid(spawner):
		failures.append("preview base is missing EnemySpawner for %s smoke" % ship_type_name)
	else:
		var spawned_ship: Node3D = null
		if spawner.has_method("debug_spawn_ship"):
			spawned_ship = spawner.call("debug_spawn_ship", ship_type_name) as Node3D
			await _wait_frames(owner, wait_frames_after_spawn)
		_validate_spawned_ship(failures, spawned_ship, ship_type_name)

	_validate_registry_smoke(failures, player_ship, ship_type_name)

	smoke_root.queue_free()
	await _wait_frames(owner, 1)


static func _run_launcher_smoke_pass(owner: Node, failures: Array[String], packed: PackedScene, smoke_scene_path: String, wait_frames_after_attach: int, wait_frames_after_spawn: int, launcher_scene_path: String) -> void:
	var smoke_root := packed.instantiate()
	if smoke_root == null:
		failures.append("smoke scene instantiate failed: %s" % smoke_scene_path)
		return

	owner.add_child(smoke_root)
	PreviewHarnessHelper.setup_common(smoke_root, false, true)
	await _wait_frames(owner, wait_frames_after_attach)

	var player_ship: Node3D = smoke_root.get_node_or_null("PlayerShip") as Node3D
	if not is_instance_valid(player_ship):
		failures.append("preview base is missing PlayerShip for launcher smoke: %s" % launcher_scene_path)
	else:
		var spawner: Node = smoke_root.get_node_or_null("EnemySpawner")
		var target_ship: Node3D = null
		if is_instance_valid(spawner) and spawner.has_method("debug_spawn_ship"):
			target_ship = spawner.call("debug_spawn_ship", "kobayabune_melee", 18.0, 0.0) as Node3D
			await _wait_frames(owner, wait_frames_after_spawn)
		if not is_instance_valid(target_ship):
			failures.append("launcher smoke target spawn failed: %s" % launcher_scene_path)
		else:
			var launcher_scene := load(launcher_scene_path) as PackedScene
			if launcher_scene == null:
				failures.append("launcher scene load failed: %s" % launcher_scene_path)
			else:
				var launcher := launcher_scene.instantiate()
				if launcher == null:
					failures.append("launcher scene instantiate failed: %s" % launcher_scene_path)
				else:
					if launcher.has_method("set_team"):
						launcher.set_team("player")
					elif launcher.get("team") != null:
						launcher.set("team", "player")
					player_ship.add_child(launcher)
					launcher.set_process(false)
					launcher.set_physics_process(false)
					await _wait_frames(owner, wait_frames_after_attach)
					var launcher_team_variant: Variant = launcher.get("team")
					var launcher_team: String = "player" if launcher_team_variant == null else str(launcher_team_variant)
					if launcher_team != "player":
						failures.append("launcher team contract failed: %s" % launcher_scene_path)

					var before_projectiles := EntityRegistry.count_projectiles()
					if launcher.has_method("fire"):
						if launcher_scene_path.contains("singigeon"):
							launcher.call("fire", target_ship, 0.0)
						else:
							launcher.call("fire", target_ship)
						await _wait_frames(owner, wait_frames_after_spawn)
						var after_projectiles := EntityRegistry.count_projectiles()
						if after_projectiles <= before_projectiles:
							failures.append("launcher did not spawn projectile: %s" % launcher_scene_path)
					else:
						failures.append("launcher is missing fire() method: %s" % launcher_scene_path)

	smoke_root.queue_free()
	await _wait_frames(owner, 1)


static func _run_projectile_smoke_pass(owner: Node, failures: Array[String], packed: PackedScene, smoke_scene_path: String, wait_frames_after_attach: int, wait_frames_after_spawn: int, projectile_scene_path: String) -> void:
	var smoke_root := packed.instantiate()
	if smoke_root == null:
		failures.append("smoke scene instantiate failed: %s" % smoke_scene_path)
		return

	owner.add_child(smoke_root)
	PreviewHarnessHelper.setup_common(smoke_root, false, true)
	await _wait_frames(owner, wait_frames_after_attach)

	var player_ship: Node3D = smoke_root.get_node_or_null("PlayerShip") as Node3D
	if not is_instance_valid(player_ship):
		failures.append("preview base is missing PlayerShip for projectile smoke: %s" % projectile_scene_path)
	else:
		var spawner: Node = smoke_root.get_node_or_null("EnemySpawner")
		var target_ship: Node3D = null
		if is_instance_valid(spawner) and spawner.has_method("debug_spawn_ship"):
			target_ship = spawner.call("debug_spawn_ship", "kobayabune_melee", 18.0, 0.0) as Node3D
			await _wait_frames(owner, wait_frames_after_spawn)
		if not is_instance_valid(target_ship):
			failures.append("projectile smoke target spawn failed: %s" % projectile_scene_path)
		else:
			var projectile_scene := load(projectile_scene_path) as PackedScene
			if projectile_scene == null:
				failures.append("projectile scene load failed: %s" % projectile_scene_path)
			else:
				var projectile := projectile_scene.instantiate()
				if projectile == null:
					failures.append("projectile scene instantiate failed: %s" % projectile_scene_path)
				else:
					if projectile_scene_path.ends_with("fire_pot.tscn"):
						projectile.team = "player"
						projectile.start_pos = player_ship.global_position + Vector3(0.0, 1.0, 0.0)
						projectile.target_pos = target_ship.global_position
					elif projectile_scene_path.ends_with("ballista_bolt.tscn"):
						projectile.team = "player"
						projectile.direction = (target_ship.global_position - player_ship.global_position).normalized()
						if projectile.direction.length_squared() <= 0.0001:
							projectile.direction = Vector3.FORWARD
						projectile.position = player_ship.global_position + Vector3(0.0, 1.0, 0.0)
					elif projectile_scene_path.ends_with("janggun_missile.tscn"):
						projectile.start_pos = player_ship.global_position + Vector3(0.0, 1.0, 0.0)
						projectile.target_pos = target_ship.global_position
						projectile.team = "player"
						projectile.janggun_lv = 1
					elif projectile_scene_path.ends_with("singigeon_rocket.tscn"):
						projectile.start_pos = player_ship.global_position + Vector3(0.0, 1.0, 0.0)
						projectile.target_pos = target_ship.global_position
						projectile.launch_direction = (target_ship.global_position - player_ship.global_position).normalized()
						projectile.team = "player"
						projectile.shooter = player_ship

					var before_projectiles := EntityRegistry.count_projectiles()
					smoke_root.add_child(projectile)
					await _wait_frames(owner, wait_frames_after_attach)
					if projectile.has_method("set_team"):
						projectile.set_team("player")
					elif projectile.get("team") != null:
						projectile.set("team", "player")
					var projectile_team_variant: Variant = projectile.get("team")
					var projectile_team: String = "player" if projectile_team_variant == null else str(projectile_team_variant)
					if projectile_team != "player":
						failures.append("projectile team contract failed: %s" % projectile_scene_path)
					_configure_projectile_smoke(projectile, projectile_scene_path, player_ship, target_ship)
					await _wait_frames(owner, wait_frames_after_spawn)
					var after_projectiles := EntityRegistry.count_projectiles()
					if after_projectiles <= before_projectiles:
						failures.append("projectile did not register in entity registry: %s" % projectile_scene_path)

	smoke_root.queue_free()
	await _wait_frames(owner, 1)


static func _configure_projectile_smoke(projectile: Node, projectile_scene_path: String, player_ship: Node3D, target_ship: Node3D) -> void:
	if projectile_scene_path.ends_with("cannonball.tscn"):
		if projectile.has_method("launch"):
			projectile.call(
				"launch",
				player_ship.global_position + Vector3(0.0, 1.2, 0.0),
				"player",
				-target_ship.global_transform.basis.z,
				target_ship,
				12.0,
				1.0,
				"roundshot"
			)
	elif projectile_scene_path.ends_with("arrow.tscn"):
		if projectile.has_method("launch"):
			projectile.call(
				"launch",
				player_ship.global_position + Vector3(0.0, 1.0, 0.0),
				target_ship.global_position,
				target_ship,
				"player",
				9.0,
				"bow",
				24.0,
				2.0
			)
	elif projectile_scene_path.ends_with("fire_pot.tscn"):
		if projectile.has_method("setup_flight"):
			projectile.call("setup_flight", projectile.start_pos, projectile.target_pos, 0.8, 3.5)


static func _validate_registry_smoke(failures: Array[String], player_ship: Node3D, label: String) -> void:
	if not is_instance_valid(player_ship):
		return

	var player_lookup: Node = EntityRegistry.get_first_ship_by_team("player")
	if player_lookup != player_ship:
		failures.append("%s smoke player ship registry lookup mismatch" % label)

	if EntityRegistry.count_ships_by_team("player") <= 0:
		failures.append("%s smoke player ship team bucket is empty" % label)

	if EntityRegistry.count_soldiers_by_team("player") <= 0:
		failures.append("%s smoke player soldier bucket is empty" % label)

	var enemy_ships: Array = EntityRegistry.get_ships_by_team("enemy")
	if enemy_ships.is_empty():
		failures.append("%s smoke enemy ship team bucket is empty" % label)
		return

	var boss_count := 0
	for ship in enemy_ships:
		if is_instance_valid(ship) and ship.is_in_group("boss"):
			boss_count += 1
	if boss_count <= 0:
		failures.append("%s smoke boss ship did not enter the enemy team bucket" % label)


static func _validate_spawned_boss(failures: Array[String], spawned_boss: Node3D, label: String) -> void:
	if not is_instance_valid(spawned_boss):
		failures.append("%s spawn returned null" % label)
		return
	var boss_team := str(spawned_boss.get("team"))
	if boss_team != "enemy":
		failures.append("%s team contract failed: %s" % [label, boss_team])
	if not spawned_boss.is_in_group("boss"):
		failures.append("%s is missing boss group tag" % label)
	var registered_enemy := EntityRegistry.get_ships_by_team("enemy").has(spawned_boss)
	if not registered_enemy:
		failures.append("%s instance was not registered in enemy team bucket" % label)


static func _validate_spawned_ship(failures: Array[String], spawned_ship: Node3D, label: String) -> void:
	if not is_instance_valid(spawned_ship):
		failures.append("%s spawn returned null" % label)
		return
	var ship_team := str(spawned_ship.get("team"))
	if ship_team != "enemy":
		failures.append("%s team contract failed: %s" % [label, ship_team])
	if not spawned_ship.is_in_group("ships"):
		failures.append("%s is missing ships group tag" % label)
	var registered_enemy := EntityRegistry.get_ships_by_team("enemy").has(spawned_ship)
	if not registered_enemy:
		failures.append("%s instance was not registered in enemy team bucket" % label)


static func _wait_frames(owner: Node, count: int) -> void:
	for _index in range(max(0, count)):
		await owner.get_tree().process_frame
