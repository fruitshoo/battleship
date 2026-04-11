extends RefCounted
class_name ProjectContractHudHelper

const EntityRegistry = preload("res://scripts/helpers/entity_registry.gd")
const PreviewHarnessHelper = preload("res://scripts/test/preview_harness_helper.gd")


static func run_hud_contract_smoke(owner: Node, failures: Array[String], smoke_scene_path: String, wait_frames_after_attach: int, wait_frames_after_spawn: int) -> void:
	var packed := load(smoke_scene_path) as PackedScene
	if packed == null:
		failures.append("hud smoke scene load failed: %s" % smoke_scene_path)
		return

	var smoke_root := packed.instantiate()
	if smoke_root == null:
		failures.append("hud smoke scene instantiate failed: %s" % smoke_scene_path)
		return

	owner.add_child(smoke_root)
	PreviewHarnessHelper.setup_common(smoke_root, false, true)
	await _wait_frames(owner, wait_frames_after_attach)

	var hud: Node = smoke_root.get_node_or_null("GameHUD")
	var player_ship: Node3D = smoke_root.get_node_or_null("PlayerShip") as Node3D
	var spawner: Node = smoke_root.get_node_or_null("EnemySpawner")
	if not is_instance_valid(hud):
		failures.append("preview base is missing GameHUD for hud smoke")
	if not is_instance_valid(player_ship):
		failures.append("preview base is missing PlayerShip for hud smoke")
	if not is_instance_valid(spawner):
		failures.append("preview base is missing EnemySpawner for hud smoke")
	if failures.size() > 0:
		smoke_root.queue_free()
		await _wait_frames(owner, 1)
		return

	var target_ship: Node3D = null
	if spawner.has_method("debug_spawn_ship"):
		target_ship = spawner.call("debug_spawn_ship", "kobayabune_melee", 12.0, 0.0) as Node3D
		await _wait_frames(owner, wait_frames_after_spawn)
	if not is_instance_valid(target_ship):
		failures.append("hud smoke target spawn failed")
		smoke_root.queue_free()
		await _wait_frames(owner, 1)
		return

	target_ship.global_position = player_ship.global_position + Vector3(0.0, 0.0, 9.0)
	if target_ship.has_method("set_team"):
		target_ship.call("set_team", "enemy")
	elif target_ship.get("team") != null:
		target_ship.set("team", "enemy")
	target_ship.set("is_derelict", false)
	if target_ship.get("is_sinking") != null:
		target_ship.set("is_sinking", false)
	if target_ship.get("is_dying") != null:
		target_ship.set("is_dying", false)

	_run_hud_state_baselines(hud, player_ship, failures)
	_run_hud_boarding_state_check(hud, player_ship, target_ship, failures)
	_run_hud_capture_state_check(hud, player_ship, failures)
	_run_hud_debug_state_check(hud, player_ship, failures)

	smoke_root.queue_free()
	await _wait_frames(owner, 1)


static func _run_hud_state_baselines(hud: Node, player_ship: Node3D, failures: Array[String]) -> void:
	if not is_instance_valid(hud) or not is_instance_valid(player_ship):
		return
	player_ship.set("is_boarding", false)
	player_ship.set("boarding_prep_timer", 0.0)
	player_ship.set("boarding_prep_duration", 2.5)
	player_ship.set("current_speed", 3.5)
	player_ship.set("max_speed", 8.0)
	player_ship.set("hull_hp", 143.0)
	player_ship.set("max_hull_hp", 200.0)
	player_ship.set("rowing_stamina", 44.0)
	player_ship.set("max_rowing_stamina", 100.0)
	if hud.has_method("update_level"):
		hud.call("update_level", 7)
	if hud.has_method("update_score"):
		hud.call("update_score", 99)
	if hud.has_method("update_crew_status"):
		hud.call("update_crew_status", 3, 6)
	if hud.has_method("_update_timer"):
		hud.call("_update_timer")
	if hud.has_method("_update_speed_display"):
		hud.call("_update_speed_display")
	if hud.has_method("_update_hull_display"):
		hud.call("_update_hull_display")
	if hud.has_method("_update_stamina_display"):
		hud.call("_update_stamina_display")
	if hud.has_method("_update_boarding_display"):
		hud.call("_update_boarding_display")
	if hud.has_method("_update_ship_health_bars"):
		hud.call("_update_ship_health_bars", false)
	if hud.has_method("_sync_ship_debug_panel_from_player"):
		hud.call("_sync_ship_debug_panel_from_player")
	if hud.has_method("_update_stat_panel"):
		hud.show_stat_panel = true
		hud.call("_update_stat_panel")
	_validate_hud_message_api(hud, failures)
	_validate_hud_baseline_state(hud, failures)


static func _run_hud_boarding_state_check(hud: Node, player_ship: Node3D, target_ship: Node3D, failures: Array[String]) -> void:
	if not is_instance_valid(hud) or not is_instance_valid(player_ship) or not is_instance_valid(target_ship):
		return
	player_ship.set("is_boarding", true)
	player_ship.set("boarding_target", target_ship)
	player_ship.set("boarding_prep_timer", 0.5)
	player_ship.set("boarding_prep_duration", 2.0)
	if hud.has_method("_update_boarding_display"):
		hud.call("_update_boarding_display")
	if not is_instance_valid(hud.boarding_ui) or not hud.boarding_ui.visible:
		failures.append("hud smoke boarding ui was not visible")
	if not is_instance_valid(hud.boarding_label) or hud.boarding_label.text != "도선 준비 중 (밧줄 고정)...":
		failures.append("hud smoke boarding label mismatch")
	player_ship.set("boarding_prep_timer", 2.1)
	if hud.has_method("_update_boarding_display"):
		hud.call("_update_boarding_display")
	if is_instance_valid(hud.boarding_label) and hud.boarding_label.text != "도선 진행 중!":
		failures.append("hud smoke boarding progress label mismatch")


static func _run_hud_capture_state_check(hud: Node, player_ship: Node3D, failures: Array[String]) -> void:
	if not is_instance_valid(hud) or not is_instance_valid(player_ship):
		return
	player_ship.set("is_boarding", false)
	player_ship.set("boarding_target", null)
	var target_ship: Node3D = null
	if hud.get_tree():
		var all_enemies := EntityRegistry.get_ships_by_team("enemy")
		if not all_enemies.is_empty():
			target_ship = all_enemies[0] as Node3D
	if is_instance_valid(target_ship):
		target_ship.set("is_derelict", true)
	if hud.has_method("_update_capture_opportunity_display"):
		hud.call("_update_capture_opportunity_display")
	if not is_instance_valid(hud.capture_opportunity_label) or not hud.capture_opportunity_label.visible:
		failures.append("hud smoke capture label was not visible")
	if is_instance_valid(hud.capture_opportunity_label) and hud.capture_opportunity_label.text != "폐선 확보 가능":
		failures.append("hud smoke capture label mismatch")
	if hud.has_method("_update_distance_debug_display"):
		hud.call("_toggle_distance_debug")
		hud.call("_update_distance_debug_display")
	if not is_instance_valid(hud.debug_distance_label) or not hud.debug_distance_label.visible:
		failures.append("hud smoke distance label was not visible")
	elif not hud.debug_distance_label.text.contains("거리"):
		failures.append("hud smoke distance label mismatch")


static func _run_hud_debug_state_check(hud: Node, player_ship: Node3D, failures: Array[String]) -> void:
	if not is_instance_valid(hud) or not is_instance_valid(player_ship):
		return
	player_ship.set("is_sinking", true)
	if hud.has_method("_sync_ship_debug_panel_from_player"):
		hud.call("_sync_ship_debug_panel_from_player")
	if is_instance_valid(hud.debug_ship_status_value) and not hud.debug_ship_status_value.text.contains("선체"):
		failures.append("hud smoke ship debug status text mismatch")
	if is_instance_valid(hud.debug_ship_config_value) and not hud.debug_ship_config_value.text.contains("설정"):
		failures.append("hud smoke ship debug config text mismatch")
	player_ship.set("is_sinking", false)
	player_ship.set("is_dying", false)
	if hud.has_method("_update_ship_health_bars"):
		hud.call("_update_ship_health_bars", false)
	if is_instance_valid(hud.hp_text_label) and hud.hp_text_label.text != "HP 143 / 200":
		failures.append("hud smoke HP label mismatch")
	if is_instance_valid(hud.speed_bar_label) and hud.speed_bar_label.text != "3.5":
		failures.append("hud smoke speed label mismatch")


static func _validate_hud_baseline_state(hud: Node, failures: Array[String]) -> void:
	if is_instance_valid(hud.boarding_ui) and hud.boarding_ui.visible:
		failures.append("hud smoke baseline boarding ui should be hidden")
	if is_instance_valid(hud.capture_opportunity_label) and hud.capture_opportunity_label.visible:
		failures.append("hud smoke baseline capture label should be hidden")
	if is_instance_valid(hud.debug_distance_label) and hud.debug_distance_label.visible:
		failures.append("hud smoke baseline distance label should be hidden")
	if is_instance_valid(hud.debug_ship_status_value) and not hud.debug_ship_status_value.text.contains("선체"):
		failures.append("hud smoke ship debug status was not populated")
	if is_instance_valid(hud.debug_ship_config_value) and not hud.debug_ship_config_value.text.contains("설정"):
		failures.append("hud smoke ship debug config was not populated")
	if is_instance_valid(hud.stat_content) and hud.stat_content.get_child_count() <= 0:
		failures.append("hud smoke stat panel was not populated")


static func _validate_hud_message_api(hud: Node, failures: Array[String]) -> void:
	if not hud.has_method("show_gust_warning_message"):
		failures.append("hud smoke missing show_gust_warning_message")
	if not hud.has_method("show_message"):
		failures.append("hud smoke missing show_message")
		return
	hud.call("show_message", "하네스 메시지", 0.25)
	if not is_instance_valid(hud.gust_warning):
		failures.append("hud smoke missing gust warning label")
		return
	if not hud.gust_warning.visible or hud.gust_warning.text != "하네스 메시지":
		failures.append("hud smoke show_message did not update warning label")


static func _wait_frames(owner: Node, frames: int) -> void:
	if frames <= 0 or not is_instance_valid(owner):
		return
	for _index in range(frames):
		await owner.get_tree().process_frame
