extends RefCounted
class_name ProjectContractHudHelper

const LevelManagerProgressionHelper = preload("res://scripts/managers/level_manager_progression_helper.gd")
const AUTHORING_SCENARIO_TRIGGER_USER_PATH := "user://authoring_palette_scenario_trigger.json"
const AUTHORING_SCENARIO_PRESETS_USER_PATH := "user://authoring_palette_scenario_presets.json"
const AUTHORING_DATA_PATCH_USER_PATH := "user://authoring_palette_data_patch.json"
const ASSEMBLED_AUTHORING_PRESET_ID := "midgame_pressure_kobayabune_melee_stand_off_gunner_boarding_side_follow"
const LIGHT_RAIDERS_PRESET_ID := "light_raiders"


class MockXpHud:
	extends Node

	var xp_updates: Array = []
	var level_updates: Array[int] = []

	func update_xp(current: int, maximum: int) -> void:
		xp_updates.append([current, maximum])

	func update_level(level: int) -> void:
		level_updates.append(level)

	func update_score(_score: int) -> void:
		pass


class MockXpLevelManager:
	extends Node

	signal level_up(new_level: int)
	signal score_changed(new_score: int)

	var current_level: int = 1
	var current_xp: int = 6
	var xp_to_next_level: int = 7
	var xp_multiplier: float = 1.0
	var level_xp_base: float = 7.0
	var level_xp_exponent: float = 1.1
	var current_score: int = 0
	var enemies_killed: int = 0
	var ship_rerolls_available: int = 0
	var hud: Node = null

	func _show_upgrade_ui(_choice_count: int) -> void:
		pass


static func run_hud_contract_smoke(owner: Node, failures: Array[String], smoke_scene_path: String, wait_frames_after_attach: int, wait_frames_after_spawn: int) -> void:
	_run_level_progression_xp_bar_contract(owner, failures)
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

	var nearby_enemy_ship: Node3D = null
	if spawner.has_method("debug_spawn_ship"):
		nearby_enemy_ship = spawner.call("debug_spawn_ship", "kobayabune_melee", 7.0, 0.0) as Node3D
		await _wait_frames(owner, wait_frames_after_spawn)
	if not is_instance_valid(nearby_enemy_ship):
		failures.append("hud smoke nearby enemy spawn failed")
		smoke_root.queue_free()
		await _wait_frames(owner, 1)
		return

	target_ship.name = "HudDebugBoardingTarget"
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
	nearby_enemy_ship.name = "HudDebugCloserEnemy"
	nearby_enemy_ship.global_position = player_ship.global_position + Vector3(0.0, 0.0, 4.0)
	if nearby_enemy_ship.has_method("set_team"):
		nearby_enemy_ship.call("set_team", "enemy")
	elif nearby_enemy_ship.get("team") != null:
		nearby_enemy_ship.set("team", "enemy")
	nearby_enemy_ship.set("is_derelict", false)
	if nearby_enemy_ship.get("is_sinking") != null:
		nearby_enemy_ship.set("is_sinking", false)
	if nearby_enemy_ship.get("is_dying") != null:
		nearby_enemy_ship.set("is_dying", false)

	_run_hud_state_baselines(hud, player_ship, failures)
	_run_hud_support_respawn_slot_check(hud, player_ship, failures)
	_run_hud_boarding_state_check(hud, player_ship, target_ship, failures)
	_run_hud_capture_state_check(hud, player_ship, failures)
	var support_ship: Node3D = null
	if player_ship.has_method("_spawn_or_repair_ally") and player_ship.has_method("_get_support_fleet_ships"):
		if "support_fleet_limit" in player_ship:
			player_ship.set("support_fleet_limit", maxi(1, int(player_ship.get("support_fleet_limit"))))
		player_ship.call("_spawn_or_repair_ally")
		await _wait_frames(owner, wait_frames_after_spawn + 2)
		var support_ships: Array = player_ship.call("_get_support_fleet_ships")
		support_ship = support_ships[0] as Node3D if not support_ships.is_empty() else null
	_run_hud_debug_state_check(hud, player_ship, target_ship, nearby_enemy_ship, support_ship, failures)
	await _run_hud_authoring_palette_harness(owner, hud, smoke_root, failures, wait_frames_after_spawn)
	await _run_compass_site_marker_check(owner, failures, smoke_root, player_ship)

	smoke_root.queue_free()
	await _wait_frames(owner, 1)


static func _run_level_progression_xp_bar_contract(owner: Node, failures: Array[String]) -> void:
	var lm := MockXpLevelManager.new()
	var hud := MockXpHud.new()
	lm.hud = hud
	owner.add_child(lm)
	owner.add_child(hud)

	LevelManagerProgressionHelper.add_xp(lm, 5)

	if lm.current_level != 2:
		failures.append("xp bar contract expected level 2 after overflow XP, got %d" % lm.current_level)
	if lm.current_xp != 4:
		failures.append("xp bar contract expected XP remainder 4, got %d" % lm.current_xp)
	if lm.xp_to_next_level != 15:
		failures.append("xp bar contract expected next XP 15, got %d" % lm.xp_to_next_level)
	if hud.xp_updates.is_empty():
		failures.append("xp bar contract did not receive HUD XP updates")
	else:
		var last_update: Array = hud.xp_updates.back()
		if int(last_update[0]) != 4 or int(last_update[1]) != 15:
			failures.append("xp bar contract expected final HUD XP update [4, 15], got %s" % str(last_update))

	lm.queue_free()
	hud.queue_free()


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
	if player_ship.has_meta("sea_site_bonus_totals"):
		player_ship.remove_meta("sea_site_bonus_totals")
	if player_ship.has_meta("sea_site_bonus_counts"):
		player_ship.remove_meta("sea_site_bonus_counts")
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
	if hud.has_method("_update_player_status_overlay"):
		hud.call("_update_player_status_overlay", false)
	if hud.has_method("_update_boarding_display"):
		hud.call("_update_boarding_display")
	if hud.has_method("_update_ammo_mode_display"):
		hud.call("_update_ammo_mode_display")
	if hud.has_method("_update_ship_health_bars"):
		hud.call("_update_ship_health_bars", false)
	if hud.has_method("_sync_ship_debug_panel_from_player"):
		hud.call("_sync_ship_debug_panel_from_player")
	if hud.has_method("_update_stat_panel"):
		hud.show_stat_panel = true
		hud.call("_update_stat_panel")
	_validate_hud_message_api(hud, failures)
	_validate_hud_baseline_state(hud, failures)
	var random_site_bonus_button := _find_button_by_text(hud.sail_debug_panel, "해역 보너스")
	if not is_instance_valid(random_site_bonus_button):
		failures.append("hud smoke debug tools should include random sea-site bonus button")
	else:
		if random_site_bonus_button.focus_mode != Control.FOCUS_NONE:
			failures.append("hud smoke random sea-site bonus debug button should not keep keyboard focus")
		var previous_hull_hp := float(player_ship.get("hull_hp"))
		var previous_max_hull_hp := float(player_ship.get("max_hull_hp"))
		random_site_bonus_button.pressed.emit()
		var random_bonus_totals_variant: Variant = player_ship.get_meta("sea_site_bonus_totals", {})
		if not (random_bonus_totals_variant is Dictionary) or (random_bonus_totals_variant as Dictionary).is_empty():
			failures.append("hud smoke random sea-site bonus debug did not grant a bonus")
		if _find_label_by_text_prefix(hud.stat_site_bonus_panel, "누적 효과") == null:
			failures.append("hud smoke random sea-site bonus debug did not refresh stat bonus rail")
		if player_ship.has_meta("sea_site_bonus_totals"):
			player_ship.remove_meta("sea_site_bonus_totals")
		if player_ship.has_meta("sea_site_bonus_counts"):
			player_ship.remove_meta("sea_site_bonus_counts")
		player_ship.set("hull_hp", previous_hull_hp)
		player_ship.set("max_hull_hp", previous_max_hull_hp)
		SeaSiteRewardHelper._sync_site_bonus_consumers(hud, player_ship)
		SeaSiteRewardHelper._sync_site_bonuses_to_player_fleet(hud, player_ship)
		if "_last_stat_signature" in hud:
			hud.set("_last_stat_signature", "")
		if hud.has_method("_update_stat_panel"):
			hud.call("_update_stat_panel")
	player_ship.set_meta("sea_site_bonus_totals", {
		"cannon_damage_pct": 0.08,
		"hull_regen_add": 0.2,
	})
	player_ship.set_meta("sea_site_bonus_counts", {
		"cannon_damage_pct": 2,
		"hull_regen_add": 2,
	})
	if "_last_stat_signature" in hud:
		hud.set("_last_stat_signature", "")
	if hud.has_method("_update_stat_panel"):
		hud.call("_update_stat_panel")
	var site_bonus_panel := hud.get("stat_site_bonus_panel") as Control
	if not is_instance_valid(site_bonus_panel):
		failures.append("hud smoke stat modal should create a right-side site bonus rail")
	else:
		var cannon_bonus := _find_label_by_text_prefix(site_bonus_panel, "포격 피해")
		var cannon_bonus_value := _find_label_by_text_prefix(site_bonus_panel, "+8%")
		var repair_bonus := _find_label_by_text_prefix(site_bonus_panel, "선체 수리")
		if not is_instance_valid(cannon_bonus) or not is_instance_valid(cannon_bonus_value):
			failures.append("hud smoke site bonus panel did not show cumulative cannon damage bonus")
		if not is_instance_valid(repair_bonus):
			failures.append("hud smoke site bonus panel did not show hull repair site bonus")
	_validate_hud_upgrade_track_art(hud, failures)
	_validate_hud_stat_modal_toggle(hud, failures)


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


static func _run_hud_support_respawn_slot_check(hud: Node, player_ship: Node3D, failures: Array[String]) -> void:
	if not is_instance_valid(hud) or not is_instance_valid(player_ship) or not is_instance_valid(hud.support_slot_container):
		return
	if not is_instance_valid(UpgradeManager) or "current_levels" not in UpgradeManager:
		return
	var previous_fleet_signal: int = int(UpgradeManager.current_levels.get("fleet_signal", 0))
	var previous_limit: int = int(player_ship.get("support_fleet_limit")) if player_ship.get("support_fleet_limit") != null else 0
	var previous_interval: float = float(player_ship.get("support_fleet_respawn_interval")) if player_ship.get("support_fleet_respawn_interval") != null else 30.0
	var previous_timer: float = float(player_ship.get("support_fleet_respawn_timer")) if player_ship.get("support_fleet_respawn_timer") != null else 0.0
	var current_support_count: int = 0
	if player_ship.has_method("_get_support_fleet_ships"):
		current_support_count = player_ship.call("_get_support_fleet_ships").size()

	UpgradeManager.current_levels["fleet_signal"] = max(1, previous_fleet_signal)
	player_ship.set("support_fleet_limit", current_support_count + 1)
	player_ship.set("support_fleet_respawn_interval", 30.0)
	player_ship.set("support_fleet_respawn_timer", 12.0)
	if hud.has_method("_update_force_panel"):
		hud.call("_update_force_panel")

	if hud.support_fleet_hud_slots.size() < current_support_count + 1:
		failures.append("hud smoke support respawn slots did not stay at fleet limit")
	else:
		var first_empty_index: int = min(current_support_count, hud.support_fleet_hud_slots.size() - 1)
		var slot: PanelContainer = hud.support_fleet_hud_slots[first_empty_index]
		var timer := slot.get_node_or_null("Root/Timer") as Label
		if not is_instance_valid(timer) or not timer.visible or timer.text != "18s":
			failures.append("hud smoke support respawn timer mismatch")
		var ship_icon := slot.get_node_or_null("Root/EmblemPlate/ShipIcon") as TextureRect
		if not is_instance_valid(ship_icon) or ship_icon.texture == null:
			failures.append("hud smoke support slot missing ship icon texture")

	UpgradeManager.current_levels["fleet_signal"] = previous_fleet_signal
	player_ship.set("support_fleet_limit", previous_limit)
	player_ship.set("support_fleet_respawn_interval", previous_interval)
	player_ship.set("support_fleet_respawn_timer", previous_timer)
	if hud.has_method("_update_force_panel"):
		hud.call("_update_force_panel")


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


static func _run_hud_debug_state_check(hud: Node, player_ship: Node3D, target_ship: Node3D, nearby_enemy_ship: Node3D, support_ship: Node3D, failures: Array[String]) -> void:
	if not is_instance_valid(hud) or not is_instance_valid(player_ship):
		return
	player_ship.set("is_sinking", true)
	if hud.has_method("_sync_ship_debug_panel_from_player"):
		hud.call("_sync_ship_debug_panel_from_player")
	if is_instance_valid(hud.debug_ship_status_value) and not hud.debug_ship_status_value.text.contains("선체"):
		failures.append("hud smoke ship debug status text mismatch")
	if is_instance_valid(hud.debug_ship_config_value) and not hud.debug_ship_config_value.text.contains("설정"):
		failures.append("hud smoke ship debug config text mismatch")
	if not is_instance_valid(hud.debug_ship_ai_value):
		failures.append("hud smoke ship debug AI label missing")
	elif not hud.debug_ship_ai_value.text.contains("플레이어 AI"):
		failures.append("hud smoke ship debug AI text mismatch")
	if not is_instance_valid(hud.debug_enemy_ai_value):
		failures.append("hud smoke enemy debug AI label missing")
	elif not hud.debug_enemy_ai_value.text.contains("적선 AI"):
		failures.append("hud smoke enemy debug AI text mismatch")
	if not is_instance_valid(hud.debug_ally_ai_value):
		failures.append("hud smoke ally debug AI label missing")
	elif not hud.debug_ally_ai_value.text.contains("아군 AI"):
		failures.append("hud smoke ally debug AI text mismatch")
	if not is_instance_valid(hud.debug_player_soldier_ai_value):
		failures.append("hud smoke player soldier debug AI label missing")
	elif not hud.debug_player_soldier_ai_value.text.contains("아군 병사 AI"):
		failures.append("hud smoke player soldier debug AI text mismatch")
	if not is_instance_valid(hud.debug_enemy_soldier_ai_value):
		failures.append("hud smoke enemy soldier debug AI label missing")
	elif not hud.debug_enemy_soldier_ai_value.text.contains("적 병사 AI"):
		failures.append("hud smoke enemy soldier debug AI text mismatch")
	var player_soldier: Node3D = null
	if is_instance_valid(player_ship):
		for candidate_variant in EntityRegistry.get_soldiers_by_ship(player_ship):
			var candidate := candidate_variant as Node3D
			if not is_instance_valid(candidate):
				continue
			if NodeContractHelper.get_team_tag(candidate) != "player":
				continue
			if SoldierStateHelper.is_dead_soldier(candidate):
				continue
			player_soldier = candidate
			break
	var enemy_soldier: Node3D = null
	if is_instance_valid(target_ship):
		for candidate_variant in EntityRegistry.get_soldiers_by_ship(target_ship):
			var candidate := candidate_variant as Node3D
			if not is_instance_valid(candidate):
				continue
			if NodeContractHelper.get_team_tag(candidate) != "enemy":
				continue
			if SoldierStateHelper.is_dead_soldier(candidate):
				continue
			enemy_soldier = candidate
			break
	if is_instance_valid(player_soldier):
		player_soldier.name = "HudDebugPlayerSoldier"
		player_soldier.global_position = player_ship.global_position + Vector3.ZERO
		player_soldier.set("limbo_ai_pilot_enabled", true)
		player_soldier.set_meta("soldier_limbo_ai_mode", "ship_duty")
		player_soldier.set_meta("soldier_limbo_ai_reason", "ship_duty")
		player_soldier.set_meta("soldier_limbo_ai_frame", Engine.get_physics_frames())
	if is_instance_valid(enemy_soldier):
		enemy_soldier.name = "HudDebugEnemySoldier"
		enemy_soldier.global_position = target_ship.global_position + Vector3.ZERO
		enemy_soldier.set("limbo_ai_pilot_enabled", true)
		enemy_soldier.set_meta("soldier_limbo_ai_mode", "attack_target")
		enemy_soldier.set_meta("soldier_limbo_ai_reason", "target_visible")
		enemy_soldier.set_meta("soldier_limbo_ai_target_distance", 3.5)
		enemy_soldier.set_meta("soldier_limbo_ai_frame", Engine.get_physics_frames())
		player_ship.set("boarding_target", target_ship)
	if hud.has_method("_sync_ship_debug_panel_from_player"):
		hud.call("_sync_ship_debug_panel_from_player")
	if is_instance_valid(player_soldier) and is_instance_valid(hud.debug_player_soldier_ai_value):
		if not hud.debug_player_soldier_ai_value.text.contains(player_soldier.name):
			failures.append("hud smoke player soldier AI did not surface player soldier")
		elif not hud.debug_player_soldier_ai_value.text.contains("mode ship_duty"):
			failures.append("hud smoke player soldier AI did not surface duty mode")
		elif not hud.debug_player_soldier_ai_value.text.contains("focus home deck"):
			failures.append("hud smoke player soldier AI did not label flagship deck focus")
	if is_instance_valid(enemy_soldier) and is_instance_valid(hud.debug_enemy_soldier_ai_value):
		if not hud.debug_enemy_soldier_ai_value.text.contains(enemy_soldier.name):
			failures.append("hud smoke enemy soldier AI did not surface enemy soldier")
		elif not hud.debug_enemy_soldier_ai_value.text.contains("focus crew on -> %s" % target_ship.name):
			failures.append("hud smoke enemy soldier AI did not label target ship focus")
		elif not hud.debug_enemy_soldier_ai_value.text.contains("mode attack_target"):
			failures.append("hud smoke enemy soldier AI did not surface attack mode")
	if is_instance_valid(target_ship) and is_instance_valid(nearby_enemy_ship):
		player_ship.set("boarding_target", target_ship)
		if "auto_raid_target" in player_ship:
			player_ship.set("auto_raid_target", null)
		if hud.has_method("_sync_ship_debug_panel_from_player"):
			hud.call("_sync_ship_debug_panel_from_player")
		if is_instance_valid(hud.debug_enemy_ai_value):
			if not hud.debug_enemy_ai_value.text.contains(target_ship.name):
				failures.append("hud smoke enemy AI did not prioritize boarding target")
			elif hud.debug_enemy_ai_value.text.contains(nearby_enemy_ship.name):
				failures.append("hud smoke enemy AI kept nearest enemy instead of boarding target")
			elif not hud.debug_enemy_ai_value.text.contains("focus boarding run -> %s" % target_ship.name):
				failures.append("hud smoke enemy AI did not label boarding focus")
		player_ship.set("boarding_target", null)
		if "auto_raid_target" in player_ship:
			player_ship.set("auto_raid_target", target_ship)
		if hud.has_method("_sync_ship_debug_panel_from_player"):
			hud.call("_sync_ship_debug_panel_from_player")
		if is_instance_valid(hud.debug_enemy_ai_value):
			if not hud.debug_enemy_ai_value.text.contains(target_ship.name):
				failures.append("hud smoke enemy AI did not use auto raid target fallback")
			elif not hud.debug_enemy_ai_value.text.contains("focus raid target -> %s" % target_ship.name):
				failures.append("hud smoke enemy AI did not label auto raid focus")
		if "auto_raid_target" in player_ship:
			player_ship.set("auto_raid_target", null)
	if is_instance_valid(player_soldier) and is_instance_valid(target_ship):
		player_soldier.owned_ship = target_ship
		player_soldier.home_ship = player_ship
		if player_soldier.has_method("set_boarding_status"):
			player_soldier.call("set_boarding_status", "boarding")
		else:
			player_soldier.set("boarding_status", "boarding")
		player_soldier.global_position = target_ship.global_position + Vector3(0.0, 0.0, 0.8)
		player_soldier.set("limbo_ai_pilot_enabled", true)
		player_soldier.set_meta("soldier_limbo_ai_mode", "muster_cross_ship")
		player_soldier.set_meta("soldier_limbo_ai_reason", "boarding_muster")
		player_soldier.set_meta("soldier_limbo_ai_frame", Engine.get_physics_frames())
		player_ship.set("boarding_target", target_ship)
		if hud.has_method("_sync_ship_debug_panel_from_player"):
			hud.call("_sync_ship_debug_panel_from_player")
		if is_instance_valid(hud.debug_player_soldier_ai_value):
			if not hud.debug_player_soldier_ai_value.text.contains("focus away team -> %s" % target_ship.name):
				failures.append("hud smoke player soldier AI did not prioritize away team focus")
			elif not hud.debug_player_soldier_ai_value.text.contains("boarding away team"):
				failures.append("hud smoke player soldier AI did not humanize away team boarding status")
			elif not hud.debug_player_soldier_ai_value.text.contains("why boarding lane"):
				failures.append("hud smoke player soldier AI did not humanize boarding muster reason")
		if player_soldier.has_method("set_boarding_status"):
			player_soldier.call("set_boarding_status", "returning")
		else:
			player_soldier.set("boarding_status", "returning")
		if hud.has_method("_sync_ship_debug_panel_from_player"):
			hud.call("_sync_ship_debug_panel_from_player")
		if is_instance_valid(hud.debug_player_soldier_ai_value) and not hud.debug_player_soldier_ai_value.text.contains("boarding returning home"):
			failures.append("hud smoke player soldier AI did not humanize returning boarding status")
		if player_soldier.has_method("set_boarding_status"):
			player_soldier.call("set_boarding_status", "stranded")
		else:
			player_soldier.set("boarding_status", "stranded")
		if hud.has_method("_sync_ship_debug_panel_from_player"):
			hud.call("_sync_ship_debug_panel_from_player")
		if is_instance_valid(hud.debug_player_soldier_ai_value) and not hud.debug_player_soldier_ai_value.text.contains("boarding cut off"):
			failures.append("hud smoke player soldier AI did not humanize stranded boarding status")
	if is_instance_valid(support_ship):
		if "limbo_ai_pilot_enabled" in support_ship:
			support_ship.set("limbo_ai_pilot_enabled", true)
		support_ship.set_meta(ShipAILimboKeys.META_SUPPORT_MODE, ShipAILimboKeys.SUPPORT_MODE_RESCUE_FLAGSHIP)
		support_ship.set_meta(ShipAILimboKeys.META_SUPPORT_TARGET_ID, player_ship.get_instance_id())
		support_ship.set_meta(ShipAILimboKeys.META_SUPPORT_REASON, "debug_rescue")
		if hud.has_method("_sync_ship_debug_panel_from_player"):
			hud.call("_sync_ship_debug_panel_from_player")
		if is_instance_valid(hud.debug_ally_ai_value):
			if not hud.debug_ally_ai_value.text.contains(support_ship.name):
				failures.append("hud smoke ally AI did not surface support ship")
			elif not hud.debug_ally_ai_value.text.contains("focus rescue run -> %s" % player_ship.name):
				failures.append("hud smoke ally AI did not label rescue focus")
			elif hud.debug_ally_ai_value.text.contains("debug_rescue"):
				failures.append("hud smoke ally AI leaked internal rescue reason")
	player_ship.set("is_sinking", false)
	player_ship.set("is_dying", false)
	player_ship.set("boarding_target", null)
	if hud.has_method("_update_ship_health_bars"):
		hud.call("_update_ship_health_bars", false)
	if is_instance_valid(hud.hp_text_label) and hud.hp_text_label.text != "HP 143 / 200":
		failures.append("hud smoke HP label mismatch")
	if is_instance_valid(hud.speed_bar_label) and hud.speed_bar_label.text != "3.5":
		failures.append("hud smoke speed label mismatch")


static func _run_hud_authoring_palette_harness(owner: Node, hud: Node, smoke_root: Node, failures: Array[String], wait_frames_after_spawn: int) -> void:
	if not is_instance_valid(hud) or not is_instance_valid(smoke_root):
		return
	if not is_instance_valid(hud.sail_debug_panel):
		failures.append("hud authoring palette harness missing debug panel")
		return
	var missing_palette_controls := false
	if not is_instance_valid(hud.debug_authoring_palette_preview_value):
		failures.append("hud authoring palette harness missing preview label")
		missing_palette_controls = true
	if not is_instance_valid(hud.debug_authoring_palette_selected_value):
		failures.append("hud authoring palette harness missing selected label")
		missing_palette_controls = true
	if not is_instance_valid(hud.debug_authoring_palette_assembly_value):
		failures.append("hud authoring palette harness missing assembly label")
		missing_palette_controls = true
	if not is_instance_valid(hud.debug_authoring_palette_execute_button):
		failures.append("hud authoring palette harness missing execute button")
		missing_palette_controls = true
	if not is_instance_valid(hud.debug_authoring_palette_queue_value):
		failures.append("hud authoring palette harness missing queue label")
		missing_palette_controls = true
	if not is_instance_valid(hud.debug_authoring_palette_preset_value):
		failures.append("hud authoring palette harness missing preset label")
		missing_palette_controls = true
	if not is_instance_valid(hud.debug_authoring_palette_preset_preview_value):
		failures.append("hud authoring palette harness missing preset preview label")
		missing_palette_controls = true
	if not is_instance_valid(hud.debug_authoring_palette_preset_select):
		failures.append("hud authoring palette harness missing preset select")
		missing_palette_controls = true
	if not is_instance_valid(hud.debug_authoring_palette_queue_add_button):
		failures.append("hud authoring palette harness missing queue add button")
		missing_palette_controls = true
	if not is_instance_valid(hud.debug_authoring_palette_queue_execute_button):
		failures.append("hud authoring palette harness missing queue execute button")
		missing_palette_controls = true
	if missing_palette_controls:
		return
	var debug_panel := hud.sail_debug_panel as Control
	if is_instance_valid(hud.bottom_right_container) and debug_panel.get_parent() == hud.bottom_right_container:
		failures.append("hud authoring palette harness debug panel should be a fixed overlay, not bottom-right container content")
	if not is_instance_valid(hud.debug_backdrop):
		failures.append("hud authoring palette harness missing debug modal backdrop")
	if is_instance_valid(hud.sail_debug_toggle_button):
		failures.append("hud authoring palette harness should not create an on-screen debug toggle button")
	var previous_debug_visible: bool = debug_panel.visible
	debug_panel.visible = true
	await _wait_frames(owner, 1)
	var debug_panel_size: Vector2 = debug_panel.size
	var debug_tabs := debug_panel.find_child("DebugToolsTabs", true, false) as TabContainer
	if not is_instance_valid(debug_tabs):
		failures.append("hud authoring palette harness missing debug tools tabs")
	else:
		if debug_tabs.focus_mode != Control.FOCUS_NONE:
			failures.append("hud authoring palette harness debug tabs should not keep keyboard focus")
		if debug_tabs.get_tab_count() < 6:
			failures.append("hud authoring palette harness expected debug tools to be split into tabs")
		var previous_tab: int = debug_tabs.current_tab
		var next_tab: int = previous_tab + 1
		if next_tab >= debug_tabs.get_tab_count():
			next_tab = 0
		debug_tabs.current_tab = next_tab
		await _wait_frames(owner, 1)
		if debug_panel.size.distance_to(debug_panel_size) > 0.5:
			failures.append("hud authoring palette harness debug panel should not resize when tabs change")
		debug_tabs.current_tab = previous_tab
		await _wait_frames(owner, 1)
	debug_panel.visible = previous_debug_visible
	var debug_shortcut_event := InputEventKey.new()
	debug_shortcut_event.pressed = true
	debug_shortcut_event.physical_keycode = KEY_BACKSLASH
	debug_shortcut_event.keycode = KEY_BACKSLASH
	hud.call("_unhandled_input", debug_shortcut_event)
	if debug_panel.visible == previous_debug_visible:
		failures.append("hud authoring palette harness won/backslash key should toggle debug panel")
	if is_instance_valid(hud.debug_backdrop) and hud.debug_backdrop.visible != debug_panel.visible:
		failures.append("hud authoring palette harness debug backdrop should follow debug panel visibility")
	hud.call("_unhandled_input", debug_shortcut_event)
	if debug_panel.visible != previous_debug_visible:
		failures.append("hud authoring palette harness won/backslash key should toggle debug panel back")

	var selected_label: Label = hud.debug_authoring_palette_selected_value
	var preview_label: Label = hud.debug_authoring_palette_preview_value
	var assembly_label: Label = hud.debug_authoring_palette_assembly_value
	var execute_button: Button = hud.debug_authoring_palette_execute_button
	var queue_label: Label = hud.debug_authoring_palette_queue_value
	var preset_label: Label = hud.debug_authoring_palette_preset_value
	var preset_preview_label: Label = hud.debug_authoring_palette_preset_preview_value
	var preset_select: OptionButton = hud.debug_authoring_palette_preset_select
	var queue_add_button: Button = hud.debug_authoring_palette_queue_add_button
	var queue_execute_button: Button = hud.debug_authoring_palette_queue_execute_button
	var queue_move_up_button := _find_button_by_text(hud.sail_debug_panel, "큐 위로")
	if not is_instance_valid(queue_move_up_button):
		failures.append("hud authoring palette harness missing queue move up button")
		return
	var queue_move_down_button := _find_button_by_text(hud.sail_debug_panel, "큐 아래")
	if not is_instance_valid(queue_move_down_button):
		failures.append("hud authoring palette harness missing queue move down button")
		return
	var queue_duplicate_button := _find_button_by_text(hud.sail_debug_panel, "큐 복제")
	if not is_instance_valid(queue_duplicate_button):
		failures.append("hud authoring palette harness missing queue duplicate button")
		return
	var queue_delete_button := _find_button_by_text(hud.sail_debug_panel, "큐 삭제")
	if not is_instance_valid(queue_delete_button):
		failures.append("hud authoring palette harness missing queue delete button")
		return
	var assembly_clear_button := _find_button_by_text(hud.sail_debug_panel, "카드 비우기")
	if not is_instance_valid(assembly_clear_button):
		failures.append("hud authoring palette harness missing assembly clear button")
		return
	if selected_label.text != "선택: -":
		failures.append("hud authoring palette harness expected empty selection")
	if assembly_label.text != "조립 카드: 전투=- / 이동=-":
		failures.append("hud authoring palette harness assembly should start empty")
	if not execute_button.disabled:
		failures.append("hud authoring palette harness execute should start disabled")
	if queue_label.text != "큐: -":
		failures.append("hud authoring palette harness queue should start empty")
	if not preset_label.text.begins_with("프리셋:"):
		failures.append("hud authoring palette harness preset label should start populated")
	if not preset_preview_label.text.begins_with("프리셋 내용:"):
		failures.append("hud authoring palette harness preset preview should start populated")
	if is_instance_valid(preset_select) and preset_select.disabled and preset_select.item_count > 0:
		failures.append("hud authoring palette harness preset select disabled with entries")
	if not queue_add_button.disabled:
		failures.append("hud authoring palette harness queue add should start disabled")
	if not queue_execute_button.disabled:
		failures.append("hud authoring palette harness queue execute should start disabled")
	if hud.debug_authoring_palette_selected_callback.is_valid():
		failures.append("hud authoring palette harness callback should start invalid")

	var combat_profile_button := _find_button_by_text(hud.sail_debug_panel, "Stand-Off Gunner")
	if not is_instance_valid(combat_profile_button):
		failures.append("hud authoring palette harness missing combat profile palette button")
		return
	combat_profile_button.mouse_entered.emit()
	if not preview_label.text.contains("role=gunner") or not preview_label.text.contains("boarding=N"):
		failures.append("hud authoring palette harness combat profile hover preview mismatch")
	combat_profile_button.pressed.emit()
	if not selected_label.text.contains("전투 모드: Stand-Off Gunner"):
		failures.append("hud authoring palette harness combat profile selection mismatch")
	if not assembly_label.text.contains("전투=Stand-Off Gunner") or not assembly_label.text.contains("이동=-"):
		failures.append("hud authoring palette harness combat profile did not update assembly")
	if not execute_button.disabled or not queue_add_button.disabled:
		failures.append("hud authoring palette harness combat profile reference should not enable actions")

	var movement_intent_button := _find_button_by_text(hud.sail_debug_panel, "Boarding Side Follow")
	if not is_instance_valid(movement_intent_button):
		failures.append("hud authoring palette harness missing movement intent palette button")
		return
	movement_intent_button.mouse_entered.emit()
	if not preview_label.text.contains("mode=side") or not preview_label.text.contains("sprint=Y") or not preview_label.text.contains("family=enemy_runtime"):
		failures.append("hud authoring palette harness movement intent hover preview mismatch")
	movement_intent_button.pressed.emit()
	if not selected_label.text.contains("이동 의도: Boarding Side Follow"):
		failures.append("hud authoring palette harness movement intent selection mismatch")
	if not assembly_label.text.contains("전투=Stand-Off Gunner") or not assembly_label.text.contains("이동=Boarding Side Follow") or not assembly_label.text.contains("enemy_runtime"):
		failures.append("hud authoring palette harness movement intent did not update assembly")
	if not execute_button.disabled or not queue_add_button.disabled:
		failures.append("hud authoring palette harness movement intent reference should not enable actions")

	var ship_button := _find_button_by_text(hud.sail_debug_panel, "Kobayabune Melee")
	if not is_instance_valid(ship_button):
		failures.append("hud authoring palette harness missing ship palette button")
		return
	ship_button.mouse_entered.emit()
	if not preview_label.text.contains("archetype=kobayabune_raider"):
		failures.append("hud authoring palette harness ship hover preview mismatch")
	ship_button.pressed.emit()
	if not selected_label.text.contains("함선: Kobayabune Melee"):
		failures.append("hud authoring palette harness ship selection mismatch")
	if not preview_label.text.contains("crew="):
		failures.append("hud authoring palette harness ship selection preview missing crew")
	if execute_button.disabled:
		failures.append("hud authoring palette harness execute did not enable after selection")
	if queue_add_button.disabled:
		failures.append("hud authoring palette harness queue add did not enable after selection")
	if not hud.debug_authoring_palette_selected_callback.is_valid():
		failures.append("hud authoring palette harness selected callback invalid after selection")
	var direct_enemy_ids_before := _collect_enemy_node_ids(owner)
	execute_button.pressed.emit()
	await _wait_frames(owner, max(1, wait_frames_after_spawn))
	var direct_spawn := _find_new_authoring_runtime_enemy(owner, direct_enemy_ids_before)
	_validate_authoring_runtime_enemy(direct_spawn, failures, "direct execute")

	var clear_button := _find_button_by_text(hud.sail_debug_panel, "비우기")
	if not is_instance_valid(clear_button):
		failures.append("hud authoring palette harness missing clear button")
		return
	clear_button.pressed.emit()
	if selected_label.text != "선택: -":
		failures.append("hud authoring palette harness clear did not reset selected label")
	if not execute_button.disabled:
		failures.append("hud authoring palette harness clear did not disable execute")
	if not queue_add_button.disabled:
		failures.append("hud authoring palette harness clear did not disable queue add")
	if hud.debug_authoring_palette_selected_callback.is_valid():
		failures.append("hud authoring palette harness clear did not reset callback")

	var recipe_button := _find_button_by_text(hud.sail_debug_panel, "Light Raiders")
	if not is_instance_valid(recipe_button):
		failures.append("hud authoring palette harness missing recipe palette button")
		return
	recipe_button.mouse_entered.emit()
	if not preview_label.text.contains("formation=column"):
		failures.append("hud authoring palette harness recipe hover preview mismatch")
	recipe_button.pressed.emit()
	if not selected_label.text.contains("편대: Light Raiders"):
		failures.append("hud authoring palette harness recipe selection mismatch")

	var profile_button := _find_button_by_text(hud.sail_debug_panel, "Midgame Pressure")
	if not is_instance_valid(profile_button):
		failures.append("hud authoring palette harness missing profile palette button")
		return
	profile_button.pressed.emit()
	if not selected_label.text.contains("전개: Midgame Pressure"):
		failures.append("hud authoring palette harness profile selection mismatch")
	var spawner := smoke_root.get_node_or_null("EnemySpawner")
	if not is_instance_valid(spawner):
		failures.append("hud authoring palette harness missing spawner")
		return

	queue_add_button.pressed.emit()
	if not queue_label.text.contains("1. 전개: Midgame Pressure"):
		failures.append("hud authoring palette harness queue did not record profile")
	if queue_execute_button.disabled:
		failures.append("hud authoring palette harness queue execute did not enable")

	ship_button.pressed.emit()
	queue_add_button.pressed.emit()
	if not queue_label.text.contains("2. 함선: Kobayabune Melee"):
		failures.append("hud authoring palette harness queue did not record ship")
	if not queue_label.text.contains("전투: Stand-Off Gunner") or not queue_label.text.contains("이동: Boarding Side Follow") or not queue_label.text.contains("enemy_runtime"):
		failures.append("hud authoring palette harness queue did not attach assembly meta")
	if int(hud.debug_authoring_palette_queue_selected_index) != 1:
		failures.append("hud authoring palette harness queue did not select appended entry")
	queue_move_up_button.pressed.emit()
	if not queue_label.text.contains("1. 함선: Kobayabune Melee") or not queue_label.text.contains("2. 전개: Midgame Pressure"):
		failures.append("hud authoring palette harness queue move up did not reorder entries")
	if int(hud.debug_authoring_palette_queue_selected_index) != 0:
		failures.append("hud authoring palette harness queue move up did not keep moved entry selected")
	queue_move_down_button.pressed.emit()
	if not queue_label.text.contains("1. 전개: Midgame Pressure") or not queue_label.text.contains("2. 함선: Kobayabune Melee"):
		failures.append("hud authoring palette harness queue move down did not restore order")
	if int(hud.debug_authoring_palette_queue_selected_index) != 1:
		failures.append("hud authoring palette harness queue move down did not keep moved entry selected")
	queue_duplicate_button.pressed.emit()
	if not preview_label.text.contains("큐 복제: 3. 함선: Kobayabune Melee"):
		failures.append("hud authoring palette harness queue duplicate status mismatch")
	if not queue_label.text.contains("3. 함선: Kobayabune Melee") or hud.debug_authoring_palette_queue_entries.size() != 3:
		failures.append("hud authoring palette harness queue duplicate did not insert copied entry")
	if int(hud.debug_authoring_palette_queue_selected_index) != 2:
		failures.append("hud authoring palette harness queue duplicate did not select duplicate")
	queue_delete_button.pressed.emit()
	if queue_label.text.contains("3. 함선: Kobayabune Melee") or hud.debug_authoring_palette_queue_entries.size() != 2:
		failures.append("hud authoring palette harness queue duplicate cleanup failed")
	if int(hud.debug_authoring_palette_queue_selected_index) != 1:
		failures.append("hud authoring palette harness queue duplicate cleanup did not keep adjacent selection")
	recipe_button.pressed.emit()
	queue_add_button.pressed.emit()
	if not queue_label.text.contains("3. 편대: Light Raiders"):
		failures.append("hud authoring palette harness queue did not record temporary recipe")
	queue_delete_button.pressed.emit()
	if not preview_label.text.contains("큐 삭제: 편대: Light Raiders"):
		failures.append("hud authoring palette harness queue delete status mismatch")
	if queue_label.text.contains("Light Raiders") or hud.debug_authoring_palette_queue_entries.size() != 2:
		failures.append("hud authoring palette harness queue delete did not remove selected entry")
	if int(hud.debug_authoring_palette_queue_selected_index) != 1:
		failures.append("hud authoring palette harness queue delete did not keep adjacent selection")

	var queue_save_button := _find_button_by_text(hud.sail_debug_panel, "큐 저장")
	if not is_instance_valid(queue_save_button):
		failures.append("hud authoring palette harness missing queue save button")
		return
	var queue_load_button := _find_button_by_text(hud.sail_debug_panel, "큐 불러오기")
	if not is_instance_valid(queue_load_button):
		failures.append("hud authoring palette harness missing queue load button")
		return
	queue_save_button.pressed.emit()
	if not preview_label.text.contains("큐 저장: 2개"):
		failures.append("hud authoring palette harness queue save status mismatch")

	var scenario_trigger_save_button := _find_button_by_text(hud.sail_debug_panel, "트리거 저장")
	if not is_instance_valid(scenario_trigger_save_button):
		failures.append("hud authoring palette harness missing scenario trigger save button")
		return
	scenario_trigger_save_button.pressed.emit()
	if not preview_label.text.contains("트리거 저장: 2개"):
		failures.append("hud authoring palette harness scenario trigger save status mismatch")
	_validate_authoring_palette_scenario_trigger_export(failures)

	var scenario_preset_save_button := _find_button_by_text(hud.sail_debug_panel, "프리셋 저장")
	if not is_instance_valid(scenario_preset_save_button):
		failures.append("hud authoring palette harness missing scenario preset save button")
		return
	var scenario_preset_load_button := _find_button_by_text(hud.sail_debug_panel, "프리셋 불러오기")
	if not is_instance_valid(scenario_preset_load_button):
		failures.append("hud authoring palette harness missing scenario preset load button")
		return
	var scenario_preset_execute_button := _find_button_by_text(hud.sail_debug_panel, "프리셋 실행")
	if not is_instance_valid(scenario_preset_execute_button):
		failures.append("hud authoring palette harness missing scenario preset execute button")
		return
	var scenario_preset_promote_button := _find_button_by_text(hud.sail_debug_panel, "데이터 승격")
	if not is_instance_valid(scenario_preset_promote_button):
		failures.append("hud authoring palette harness missing scenario preset promote button")
		return
	var scenario_patch_check_button := _find_button_by_text(hud.sail_debug_panel, "패치 점검")
	if not is_instance_valid(scenario_patch_check_button):
		failures.append("hud authoring palette harness missing scenario patch check button")
		return
	var scenario_patch_merge_button := _find_button_by_text(hud.sail_debug_panel, "패치 병합")
	if not is_instance_valid(scenario_patch_merge_button):
		failures.append("hud authoring palette harness missing scenario patch merge button")
		return
	var scenario_preset_delete_button := _find_button_by_text(hud.sail_debug_panel, "프리셋 삭제")
	if not is_instance_valid(scenario_preset_delete_button):
		failures.append("hud authoring palette harness missing scenario preset delete button")
		return
	scenario_preset_save_button.pressed.emit()
	if not preview_label.text.contains("프리셋 저장:"):
		failures.append("hud authoring palette harness scenario preset save status mismatch")
	if not preset_label.text.contains("Midgame Pressure") or not preset_label.text.contains("Kobayabune Melee"):
		failures.append("hud authoring palette harness scenario preset label mismatch")
	if not preset_preview_label.text.contains("Midgame Pressure") or not preset_preview_label.text.contains("Kobayabune Melee"):
		failures.append("hud authoring palette harness scenario preset preview mismatch")
	if not preset_preview_label.text.contains("midgame_pressure") or not preset_preview_label.text.contains("kobayabune_melee"):
		failures.append("hud authoring palette harness scenario preset preview missing action ids")
	_validate_authoring_palette_scenario_preset_store(failures)
	if not _option_button_has_metadata(preset_select, ASSEMBLED_AUTHORING_PRESET_ID):
		failures.append("hud authoring palette harness scenario preset select missing first preset")

	var queue_clear_button := _find_button_by_text(hud.sail_debug_panel, "큐 비우기")
	if not is_instance_valid(queue_clear_button):
		failures.append("hud authoring palette harness missing queue clear button")
		return
	queue_clear_button.pressed.emit()
	assembly_clear_button.pressed.emit()
	if assembly_label.text != "조립 카드: 전투=- / 이동=-":
		failures.append("hud authoring palette harness assembly clear did not reset label")
	recipe_button.pressed.emit()
	queue_add_button.pressed.emit()
	if not queue_label.text.contains("1. 편대: Light Raiders"):
		failures.append("hud authoring palette harness second preset queue did not record recipe")
	scenario_preset_save_button.pressed.emit()
	if not _option_button_has_metadata(preset_select, LIGHT_RAIDERS_PRESET_ID):
		failures.append("hud authoring palette harness scenario preset select missing second preset")
	if not preset_preview_label.text.contains("Light Raiders") or not preset_preview_label.text.contains(LIGHT_RAIDERS_PRESET_ID):
		failures.append("hud authoring palette harness scenario preset preview did not show second preset")
	if preset_select.item_count < 2:
		failures.append("hud authoring palette harness scenario preset select did not keep multiple presets")
	if not _select_option_by_metadata(preset_select, ASSEMBLED_AUTHORING_PRESET_ID):
		failures.append("hud authoring palette harness scenario preset select could not choose first preset")
	if not preview_label.text.contains("프리셋 선택:"):
		failures.append("hud authoring palette harness scenario preset select status mismatch")
	if not preset_preview_label.text.contains("Midgame Pressure") or not preset_preview_label.text.contains("Kobayabune Melee"):
		failures.append("hud authoring palette harness scenario preset select did not restore preview")
	scenario_preset_promote_button.pressed.emit()
	if not preview_label.text.contains("데이터 승격:"):
		failures.append("hud authoring palette harness scenario preset promote status mismatch")
	if not queue_label.text.contains("1. 편대: Light Raiders"):
		failures.append("hud authoring palette harness scenario preset promote should not mutate queue")
	_validate_authoring_palette_data_patch_export(failures)
	scenario_patch_check_button.pressed.emit()
	if not preview_label.text.contains("패치 점검: 병합 가능 1개 / 액션 2개"):
		failures.append("hud authoring palette harness scenario patch check status mismatch")
	if not queue_label.text.contains("1. 편대: Light Raiders"):
		failures.append("hud authoring palette harness scenario patch check should not mutate queue")
	if not _write_user_json_dictionary(AUTHORING_DATA_PATCH_USER_PATH, _make_conflicting_authoring_data_patch()):
		failures.append("hud authoring palette harness could not write conflicting data patch")
		return
	scenario_patch_merge_button.pressed.emit()
	if not preview_label.text.contains("패치 병합 차단: 충돌 1개"):
		failures.append("hud authoring palette harness scenario patch merge conflict status mismatch")
	if not queue_label.text.contains("1. 편대: Light Raiders"):
		failures.append("hud authoring palette harness scenario patch merge should not mutate queue")

	queue_clear_button.pressed.emit()
	if queue_label.text != "큐: -":
		failures.append("hud authoring palette harness queue clear did not reset label")
	if not queue_execute_button.disabled:
		failures.append("hud authoring palette harness queue clear did not disable execute")
	if not hud.debug_authoring_palette_queue_entries.is_empty():
		failures.append("hud authoring palette harness queue clear did not reset entries")

	var preset_enemy_ids_before := _collect_enemy_node_ids(owner)
	var preset_enemy_count_before := preset_enemy_ids_before.size()
	scenario_preset_execute_button.pressed.emit()
	await _wait_frames(owner, max(1, wait_frames_after_spawn))
	var preset_enemy_count_after := _count_enemy_nodes(owner)
	var preset_spawn := _find_new_authoring_runtime_enemy(owner, preset_enemy_ids_before)
	_validate_authoring_runtime_enemy(preset_spawn, failures, "scenario preset execute")
	if not preview_label.text.contains("프리셋 실행:"):
		failures.append("hud authoring palette harness scenario preset execute status mismatch")
	if queue_label.text != "큐: -":
		failures.append("hud authoring palette harness scenario preset execute should not mutate queue")
	if str(spawner.get("active_encounter_profile")) != "midgame_pressure":
		failures.append("hud authoring palette harness scenario preset execute did not update spawner")
	if preset_enemy_count_after <= preset_enemy_count_before:
		failures.append("hud authoring palette harness scenario preset execute did not spawn enemy")

	scenario_preset_load_button.pressed.emit()
	if not preview_label.text.contains("프리셋 불러오기:"):
		failures.append("hud authoring palette harness scenario preset load status mismatch")
	if not queue_label.text.contains("1. 전개: Midgame Pressure") or not queue_label.text.contains("2. 함선: Kobayabune Melee"):
		failures.append("hud authoring palette harness scenario preset load did not restore labels")
	if hud.debug_authoring_palette_queue_entries.size() != 2:
		failures.append("hud authoring palette harness scenario preset load did not restore entries")

	if not _select_option_by_metadata(preset_select, LIGHT_RAIDERS_PRESET_ID):
		failures.append("hud authoring palette harness scenario preset select could not choose second preset")
	scenario_preset_delete_button.pressed.emit()
	if not preview_label.text.contains("프리셋 삭제:"):
		failures.append("hud authoring palette harness scenario preset delete status mismatch")
	if _option_button_has_metadata(preset_select, LIGHT_RAIDERS_PRESET_ID):
		failures.append("hud authoring palette harness scenario preset delete did not remove preset")
	if not _option_button_has_metadata(preset_select, ASSEMBLED_AUTHORING_PRESET_ID):
		failures.append("hud authoring palette harness scenario preset delete removed wrong preset")
	if not preset_label.text.contains("1개") or not preset_label.text.contains("Midgame Pressure"):
		failures.append("hud authoring palette harness scenario preset delete did not fallback active preset")
	if not preset_preview_label.text.contains("Midgame Pressure") or preset_preview_label.text.contains("Light Raiders"):
		failures.append("hud authoring palette harness scenario preset delete preview mismatch")
	if not queue_label.text.contains("1. 전개: Midgame Pressure") or not queue_label.text.contains("2. 함선: Kobayabune Melee"):
		failures.append("hud authoring palette harness scenario preset delete should not mutate queue")
	_validate_authoring_palette_scenario_preset_deleted(failures)

	queue_clear_button.pressed.emit()
	queue_load_button.pressed.emit()
	if not preview_label.text.contains("큐 불러오기: 2개"):
		failures.append("hud authoring palette harness queue load status mismatch")
	if not queue_label.text.contains("1. 전개: Midgame Pressure") or not queue_label.text.contains("2. 함선: Kobayabune Melee"):
		failures.append("hud authoring palette harness queue load did not restore labels")
	if hud.debug_authoring_palette_queue_entries.size() != 2:
		failures.append("hud authoring palette harness queue load did not restore entries")
	if queue_execute_button.disabled:
		failures.append("hud authoring palette harness queue load did not enable execute")

	var queue_enemy_ids_before := _collect_enemy_node_ids(owner)
	var enemy_count_before := queue_enemy_ids_before.size()
	queue_execute_button.pressed.emit()
	await _wait_frames(owner, max(1, wait_frames_after_spawn))
	var enemy_count_after := _count_enemy_nodes(owner)
	var queue_spawn := _find_new_authoring_runtime_enemy(owner, queue_enemy_ids_before)
	_validate_authoring_runtime_enemy(queue_spawn, failures, "queue execute")
	if str(spawner.get("active_encounter_profile")) != "midgame_pressure":
		failures.append("hud authoring palette harness queue profile execute did not update spawner")
	if enemy_count_after <= enemy_count_before:
		failures.append("hud authoring palette harness queue ship execute did not spawn enemy")

	var trigger_button := _find_button_by_text(hud.sail_debug_panel, "Enter Late Battle Pressure")
	if not is_instance_valid(trigger_button):
		failures.append("hud authoring palette harness missing trigger palette button")
		return
	trigger_button.pressed.emit()
	if not selected_label.text.contains("트리거: Enter Late Battle Pressure"):
		failures.append("hud authoring palette harness trigger selection mismatch")
	execute_button.pressed.emit()
	await _wait_frames(owner, 1)
	if is_instance_valid(spawner):
		var triggered: Dictionary = spawner.get("triggered_scenario_ids") as Dictionary
		if not bool(triggered.get("enter_late_battle_pressure", false)):
			failures.append("hud authoring palette harness trigger execute did not mark trigger")
		if str(spawner.get("active_encounter_profile")) != "late_battle_pressure":
			failures.append("hud authoring palette harness trigger execute did not apply profile")


static func _validate_authoring_palette_scenario_trigger_export(failures: Array[String]) -> void:
	var root := _load_user_json_dictionary(AUTHORING_SCENARIO_TRIGGER_USER_PATH)
	if root.is_empty():
		failures.append("hud authoring palette harness scenario trigger export missing json")
		return
	var triggers_variant: Variant = root.get("scenario_triggers", [])
	if typeof(triggers_variant) != TYPE_ARRAY:
		failures.append("hud authoring palette harness scenario trigger export missing triggers")
		return
	var triggers: Array = triggers_variant as Array
	if triggers.is_empty() or typeof(triggers[0]) != TYPE_DICTIONARY:
		failures.append("hud authoring palette harness scenario trigger export empty triggers")
		return
	var trigger: Dictionary = triggers[0] as Dictionary
	if str(trigger.get("id", "")) != ASSEMBLED_AUTHORING_PRESET_ID:
		failures.append("hud authoring palette harness scenario trigger export id mismatch")
	var condition_variant: Variant = trigger.get("condition", {})
	if typeof(condition_variant) != TYPE_DICTIONARY:
		failures.append("hud authoring palette harness scenario trigger export condition missing")
	else:
		var condition: Dictionary = condition_variant as Dictionary
		if not is_equal_approx(float(condition.get("elapsed_time", -1.0)), 0.0):
			failures.append("hud authoring palette harness scenario trigger export condition mismatch")
	var actions_variant: Variant = trigger.get("actions", [])
	if typeof(actions_variant) != TYPE_ARRAY:
		failures.append("hud authoring palette harness scenario trigger export actions missing")
		return
	var actions: Array = actions_variant as Array
	if actions.size() != 2:
		failures.append("hud authoring palette harness scenario trigger export action count mismatch")
		return
	if typeof(actions[0]) != TYPE_DICTIONARY or typeof(actions[1]) != TYPE_DICTIONARY:
		failures.append("hud authoring palette harness scenario trigger export action shape mismatch")
		return
	var profile_action: Dictionary = actions[0] as Dictionary
	var ship_action: Dictionary = actions[1] as Dictionary
	if str(profile_action.get("type", "")) != "set_encounter_profile" or str(profile_action.get("profile", "")) != "midgame_pressure":
		failures.append("hud authoring palette harness scenario trigger export profile action mismatch")
	if str(ship_action.get("type", "")) != "spawn_ship" or str(ship_action.get("ship_type", "")) != "kobayabune_melee":
		failures.append("hud authoring palette harness scenario trigger export ship action mismatch")
	_validate_authoring_action_meta(ship_action, failures, "scenario trigger export ship")


static func _validate_authoring_palette_scenario_preset_store(failures: Array[String]) -> void:
	var root := _load_user_json_dictionary(AUTHORING_SCENARIO_PRESETS_USER_PATH)
	if root.is_empty():
		failures.append("hud authoring palette harness scenario preset store missing json")
		return
	if str(root.get("active_preset", "")) != ASSEMBLED_AUTHORING_PRESET_ID:
		failures.append("hud authoring palette harness scenario preset active id mismatch")
	var presets_variant: Variant = root.get("presets", [])
	if typeof(presets_variant) != TYPE_ARRAY:
		failures.append("hud authoring palette harness scenario preset store missing presets")
		return
	var presets: Array = presets_variant as Array
	var preset: Dictionary = {}
	for preset_variant in presets:
		if typeof(preset_variant) != TYPE_DICTIONARY:
			continue
		var candidate: Dictionary = preset_variant as Dictionary
		if str(candidate.get("id", "")) == ASSEMBLED_AUTHORING_PRESET_ID:
			preset = candidate
			break
	if preset.is_empty():
		failures.append("hud authoring palette harness scenario preset store missing active preset")
		return
	var label_text := str(preset.get("label", ""))
	if not label_text.contains("Midgame Pressure") or not label_text.contains("Kobayabune Melee"):
		failures.append("hud authoring palette harness scenario preset store label mismatch")
	var queue_actions: Array = preset.get("queue_actions", []) as Array if typeof(preset.get("queue_actions", [])) == TYPE_ARRAY else []
	if queue_actions.size() != 2:
		failures.append("hud authoring palette harness scenario preset store queue action count mismatch")
	elif typeof(queue_actions[1]) == TYPE_DICTIONARY:
		_validate_authoring_action_meta(queue_actions[1] as Dictionary, failures, "scenario preset queue ship")
	var trigger: Dictionary = preset.get("trigger", {}) as Dictionary if typeof(preset.get("trigger", {})) == TYPE_DICTIONARY else {}
	if str(trigger.get("id", "")) != ASSEMBLED_AUTHORING_PRESET_ID:
		failures.append("hud authoring palette harness scenario preset trigger id mismatch")
	var trigger_actions: Array = trigger.get("actions", []) as Array if typeof(trigger.get("actions", [])) == TYPE_ARRAY else []
	if trigger_actions.size() != 2:
		failures.append("hud authoring palette harness scenario preset trigger action count mismatch")
	elif typeof(trigger_actions[1]) == TYPE_DICTIONARY:
		_validate_authoring_action_meta(trigger_actions[1] as Dictionary, failures, "scenario preset trigger ship")


static func _validate_authoring_palette_scenario_preset_deleted(failures: Array[String]) -> void:
	var root := _load_user_json_dictionary(AUTHORING_SCENARIO_PRESETS_USER_PATH)
	if root.is_empty():
		failures.append("hud authoring palette harness scenario preset delete missing json")
		return
	if str(root.get("active_preset", "")) != ASSEMBLED_AUTHORING_PRESET_ID:
		failures.append("hud authoring palette harness scenario preset delete active id mismatch")
	var presets_variant: Variant = root.get("presets", [])
	if typeof(presets_variant) != TYPE_ARRAY:
		failures.append("hud authoring palette harness scenario preset delete missing presets")
		return
	var presets: Array = presets_variant as Array
	if presets.size() != 1:
		failures.append("hud authoring palette harness scenario preset delete count mismatch")
	for preset_variant in presets:
		if typeof(preset_variant) != TYPE_DICTIONARY:
			continue
		var preset: Dictionary = preset_variant as Dictionary
		if str(preset.get("id", "")) == LIGHT_RAIDERS_PRESET_ID:
			failures.append("hud authoring palette harness scenario preset delete kept deleted preset")


static func _validate_authoring_palette_data_patch_export(failures: Array[String]) -> void:
	var root := _load_user_json_dictionary(AUTHORING_DATA_PATCH_USER_PATH)
	if root.is_empty():
		failures.append("hud authoring palette harness data patch export missing json")
		return
	if str(root.get("format", "")) != "battleship_authoring_data_patch":
		failures.append("hud authoring palette harness data patch format mismatch")
	if str(root.get("target_path", "")) != "res://data/enemy_spawn_rules.json":
		failures.append("hud authoring palette harness data patch target mismatch")
	var source_preset: Dictionary = root.get("source_preset", {}) as Dictionary if typeof(root.get("source_preset", {})) == TYPE_DICTIONARY else {}
	if str(source_preset.get("id", "")) != ASSEMBLED_AUTHORING_PRESET_ID:
		failures.append("hud authoring palette harness data patch source preset mismatch")
	var patch: Dictionary = root.get("enemy_spawn_rules_patch", {}) as Dictionary if typeof(root.get("enemy_spawn_rules_patch", {})) == TYPE_DICTIONARY else {}
	var triggers: Array = patch.get("scenario_triggers", []) as Array if typeof(patch.get("scenario_triggers", [])) == TYPE_ARRAY else []
	if triggers.size() != 1 or typeof(triggers[0]) != TYPE_DICTIONARY:
		failures.append("hud authoring palette harness data patch trigger shape mismatch")
		return
	var trigger: Dictionary = triggers[0] as Dictionary
	if str(trigger.get("id", "")) != ASSEMBLED_AUTHORING_PRESET_ID:
		failures.append("hud authoring palette harness data patch trigger id mismatch")
	var actions: Array = trigger.get("actions", []) as Array if typeof(trigger.get("actions", [])) == TYPE_ARRAY else []
	if actions.size() != 2:
		failures.append("hud authoring palette harness data patch action count mismatch")
		return
	if typeof(actions[0]) != TYPE_DICTIONARY or typeof(actions[1]) != TYPE_DICTIONARY:
		failures.append("hud authoring palette harness data patch action shape mismatch")
		return
	var profile_action: Dictionary = actions[0] as Dictionary
	var ship_action: Dictionary = actions[1] as Dictionary
	if str(profile_action.get("type", "")) != "set_encounter_profile" or str(profile_action.get("profile", "")) != "midgame_pressure":
		failures.append("hud authoring palette harness data patch profile action mismatch")
	if str(ship_action.get("type", "")) != "spawn_ship" or str(ship_action.get("ship_type", "")) != "kobayabune_melee":
		failures.append("hud authoring palette harness data patch ship action mismatch")
	_validate_authoring_action_meta(ship_action, failures, "data patch ship")


static func _validate_authoring_action_meta(action: Dictionary, failures: Array[String], label: String) -> void:
	var authoring_variant: Variant = action.get("authoring", {})
	if typeof(authoring_variant) != TYPE_DICTIONARY:
		failures.append("hud authoring palette harness %s missing authoring meta" % label)
		return
	var authoring: Dictionary = authoring_variant as Dictionary
	if str(authoring.get("combat_profile", "")) != "stand_off_gunner":
		failures.append("hud authoring palette harness %s combat meta mismatch" % label)
	if str(authoring.get("movement_intent", "")) != "boarding_side_follow":
		failures.append("hud authoring palette harness %s movement meta mismatch" % label)
	if str(authoring.get("movement_family", "")) != "enemy_runtime":
		failures.append("hud authoring palette harness %s movement family mismatch" % label)
	if str(authoring.get("movement_mode", "")) != "side":
		failures.append("hud authoring palette harness %s movement mode mismatch" % label)
	if absf(float(authoring.get("movement_speed_min", 0.0)) - 0.56) > 0.001:
		failures.append("hud authoring palette harness %s movement speed min mismatch" % label)
	if absf(float(authoring.get("movement_speed_max", 0.0)) - 1.02) > 0.001:
		failures.append("hud authoring palette harness %s movement speed max mismatch" % label)
	if authoring.get("movement_sprint", false) != true:
		failures.append("hud authoring palette harness %s movement sprint mismatch" % label)


static func _validate_authoring_runtime_enemy(ship: Node3D, failures: Array[String], label: String) -> void:
	if not is_instance_valid(ship):
		failures.append("hud authoring palette harness %s did not produce an authored runtime enemy" % label)
		return
	var action := {
		"authoring": ship.get_meta(EnemySpawnerFleetHelper.AUTHORING, {})
	}
	_validate_authoring_action_meta(action, failures, "%s runtime ship" % label)
	if ship.get_meta(EnemySpawnerFleetHelper.META_AUTHORING_RUNTIME_APPLIED, false) != true:
		failures.append("hud authoring palette harness %s runtime override marker missing" % label)
	if str(ship.get_meta(EnemySpawnerFleetHelper.META_AUTHORING_COMBAT_PROFILE, "")) != "stand_off_gunner":
		failures.append("hud authoring palette harness %s combat runtime meta mismatch" % label)
	if str(ship.get_meta(EnemySpawnerFleetHelper.META_AUTHORING_MOVEMENT_INTENT, "")) != "boarding_side_follow":
		failures.append("hud authoring palette harness %s movement runtime meta mismatch" % label)
	if str(ship.get_meta(EnemySpawnerFleetHelper.META_AUTHORING_MOVEMENT_FAMILY, "")) != "enemy_runtime":
		failures.append("hud authoring palette harness %s movement family runtime meta mismatch" % label)
	if ShipCombatModeHelper.is_gunner(ship) != true:
		failures.append("hud authoring palette harness %s did not apply gunner combat role" % label)
	if ShipCombatModeHelper.can_board(ship):
		failures.append("hud authoring palette harness %s did not disable boarding" % label)
	if absf(ShipCombatModeHelper.preferred_range(ship) - 14.0) > 0.05:
		failures.append("hud authoring palette harness %s preferred range mismatch" % label)
	if absf(ShipCombatModeHelper.range_tolerance(ship) - 2.5) > 0.05:
		failures.append("hud authoring palette harness %s range tolerance mismatch" % label)
	if absf(ShipCombatModeHelper.retreat_distance(ship) - 8.5) > 0.05:
		failures.append("hud authoring palette harness %s retreat distance mismatch" % label)
	var target := ship.get("target") as Node3D
	if is_instance_valid(target):
		var nav := ChaserShipNavigationHelper.build_navigation(ship, target)
		if ShipMovementIntent.get_mode(nav) != "side":
			failures.append("hud authoring palette harness %s navigation mode mismatch: %s" % [label, ShipMovementIntent.get_mode(nav)])
		var desired_speed := ShipMovementIntent.get_desired_speed_mult(nav)
		if desired_speed < 0.56 - 0.001 or desired_speed > 1.02 + 0.001:
			failures.append("hud authoring palette harness %s navigation speed mismatch: %.3f" % [label, desired_speed])


static func _find_new_authoring_runtime_enemy(owner: Node, before_ids: Dictionary) -> Node3D:
	for ship in _collect_enemy_nodes(owner):
		if before_ids.has(ship.get_instance_id()):
			continue
		if str(ship.get_meta(EnemySpawnerFleetHelper.META_AUTHORING_COMBAT_PROFILE, "")) != "stand_off_gunner":
			continue
		if str(ship.get_meta(EnemySpawnerFleetHelper.META_AUTHORING_MOVEMENT_INTENT, "")) != "boarding_side_follow":
			continue
		return ship
	return null


static func _collect_enemy_node_ids(owner: Node) -> Dictionary:
	var ids: Dictionary = {}
	for ship in _collect_enemy_nodes(owner):
		ids[ship.get_instance_id()] = true
	return ids


static func _collect_enemy_nodes(owner: Node) -> Array[Node3D]:
	var ships: Array[Node3D] = []
	if not is_instance_valid(owner) or owner.get_tree() == null:
		return ships
	for node in owner.get_tree().get_nodes_in_group("enemy"):
		var ship := node as Node3D
		if is_instance_valid(ship):
			ships.append(ship)
	return ships


static func _make_conflicting_authoring_data_patch() -> Dictionary:
	var trigger := {
		"id": "enter_midgame_pressure",
		"label": "Enter Midgame Pressure",
		"condition": {"elapsed_time": 0.0},
		"one_shot": true,
		"enabled": true,
		"actions": [
			{"type": "set_encounter_profile", "profile": "midgame_pressure", "label": "Midgame Pressure"}
		]
	}
	return {
		"format": "battleship_authoring_data_patch",
		"version": 1,
		"target_path": "res://data/enemy_spawn_rules.json",
		"merge_key": "scenario_triggers",
		"source_preset": {
			"id": "enter_midgame_pressure",
			"label": "Enter Midgame Pressure",
			"queue_actions": []
		},
		"enemy_spawn_rules_patch": {
			"scenario_triggers": [trigger]
		},
		"scenario_triggers": [trigger]
	}


static func _run_compass_site_marker_check(owner: Node, failures: Array[String], smoke_root: Node, player_ship: Node3D) -> void:
	var panel_scene := load("res://scenes/ui/ship_control_panel.tscn") as PackedScene
	if panel_scene == null:
		failures.append("hud smoke ship control panel load failed")
		return
	var ui_layer := CanvasLayer.new()
	ui_layer.name = "CompassMarkerSmokeUI"
	smoke_root.add_child(ui_layer)
	var control_panel := panel_scene.instantiate()
	if control_panel == null:
		failures.append("hud smoke ship control panel instantiate failed")
		ui_layer.queue_free()
		return
	ui_layer.add_child(control_panel)

	var near_site := Node3D.new()
	near_site.name = "CompassNearSiteSmoke"
	near_site.add_to_group("sea_site")
	smoke_root.add_child(near_site)
	near_site.global_position = player_ship.global_position + Vector3(3.0, 0.0, 0.0)
	var second_site := Node3D.new()
	second_site.name = "CompassSecondSiteSmoke"
	second_site.add_to_group("sea_site")
	smoke_root.add_child(second_site)
	second_site.global_position = player_ship.global_position + Vector3(0.0, 0.0, -72.0)
	await _wait_frames(owner, 5)

	var marker := control_panel.get_node_or_null("WindPanel/WindIndicator/CompassWheel/SiteMarker") as Node2D
	if not is_instance_valid(marker):
		failures.append("hud smoke compass site marker missing")
	elif not marker.visible:
		failures.append("hud smoke compass site marker did not become visible")
	elif marker.position.length() > 10.0:
		failures.append("hud smoke compass near site marker should stay near center: %.2f" % marker.position.length())
	var second_marker := control_panel.get_node_or_null("WindPanel/WindIndicator/CompassWheel/SiteMarkerExtra1") as Node2D
	if not is_instance_valid(second_marker):
		failures.append("hud smoke compass should create an extra marker when multiple sites are visible")
	elif not second_marker.visible:
		failures.append("hud smoke compass extra site marker did not become visible")
	elif second_marker.position.length() < 48.0:
		failures.append("hud smoke compass extra far site marker was not near the rim: %.2f" % second_marker.position.length())

	near_site.queue_free()
	second_site.queue_free()
	await _wait_frames(owner, 15)

	var site := Node3D.new()
	site.name = "CompassFarSiteSmoke"
	site.add_to_group("sea_site")
	smoke_root.add_child(site)
	site.global_position = player_ship.global_position + Vector3(0.0, 0.0, -72.0)
	await _wait_frames(owner, 15)

	if not is_instance_valid(marker):
		failures.append("hud smoke compass site marker missing after far site spawn")
	elif not marker.visible:
		failures.append("hud smoke compass far site marker did not become visible")
	elif marker.position.length() < 48.0:
		failures.append("hud smoke compass far site marker was not near the rim: %.2f" % marker.position.length())

	site.queue_free()

	var decoy_site := Node3D.new()
	decoy_site.name = "CompassTreasureDecoySiteSmoke"
	decoy_site.add_to_group("sea_site")
	smoke_root.add_child(decoy_site)
	decoy_site.global_position = player_ship.global_position + Vector3(3.0, 0.0, 0.0)

	var chest := Node3D.new()
	chest.name = "CompassTreasureChestSmoke"
	chest.add_to_group("treasure_chest")
	smoke_root.add_child(chest)
	chest.global_position = player_ship.global_position + Vector3(-72.0, 0.0, 0.0)
	await _wait_frames(owner, 15)

	if not is_instance_valid(marker):
		failures.append("hud smoke compass treasure marker missing after chest spawn")
	elif not marker.visible:
		failures.append("hud smoke compass treasure marker did not become visible")
	elif marker.position.length() < 48.0:
		failures.append("hud smoke compass treasure marker was not near the rim: %.2f" % marker.position.length())

	chest.queue_free()
	await _wait_frames(owner, 8)
	if not is_instance_valid(marker):
		failures.append("hud smoke compass marker missing after treasure freed")
	elif not marker.visible:
		failures.append("hud smoke compass marker should recover to the remaining sea site after treasure freed")
	decoy_site.queue_free()
	control_panel.queue_free()
	ui_layer.queue_free()
	await _wait_frames(owner, 1)


static func _validate_hud_baseline_state(hud: Node, failures: Array[String]) -> void:
	if is_instance_valid(hud.boarding_ui) and hud.boarding_ui.visible:
		failures.append("hud smoke baseline boarding ui should be hidden")
	if is_instance_valid(hud.capture_opportunity_label) and hud.capture_opportunity_label.visible:
		failures.append("hud smoke baseline capture label should be hidden")
	if is_instance_valid(hud.debug_distance_label) and hud.debug_distance_label.visible:
		failures.append("hud smoke baseline distance label should be hidden")
	if is_instance_valid(hud.ammo_mode_label) and hud.ammo_mode_label.visible:
		failures.append("hud smoke ammo mode label should be hidden")
	if is_instance_valid(hud.debug_ship_status_value) and not hud.debug_ship_status_value.text.contains("선체"):
		failures.append("hud smoke ship debug status was not populated")
	if is_instance_valid(hud.debug_ship_config_value) and not hud.debug_ship_config_value.text.contains("설정"):
		failures.append("hud smoke ship debug config was not populated")
	if is_instance_valid(hud.stat_content) and hud.stat_content.get_child_count() <= 0:
		failures.append("hud smoke stat panel was not populated")
	if is_instance_valid(hud.stat_scroll) and is_instance_valid(hud.stat_content):
		var stat_gutter := hud.stat_content.get_parent() as MarginContainer
		if not is_instance_valid(stat_gutter) or stat_gutter.get_parent() != hud.stat_scroll:
			failures.append("hud smoke stat panel content should sit inside a scrollbar gutter")
		elif stat_gutter.get_theme_constant("margin_right") < 14:
			failures.append("hud smoke stat panel scrollbar gutter should reserve right-side reading space")
	var stat_title := _find_label_by_text_prefix(hud.stat_panel, "전투 수치")
	if not is_instance_valid(stat_title) or not stat_title.text.contains("Tab"):
		failures.append("hud smoke stat panel title should advertise Tab shortcut")
	if is_instance_valid(hud.stat_content) and hud.stat_content.get_child_count() > 0:
		var core_section := hud.stat_content.get_child(0) as Control
		if not is_instance_valid(core_section) or _find_label_by_text_prefix(core_section, "핵심") == null:
			failures.append("hud smoke stat panel should put core summary before detailed stat sections")
		if core_section is PanelContainer:
			failures.append("hud smoke stat panel core summary should use report-style rows instead of an inner card")
		if is_instance_valid(core_section) and _find_label_by_text_prefix(core_section, "전과") != null:
			failures.append("hud smoke stat panel should not put combat records first")
		var stat_grid: GridContainer = null
		if hud.stat_content.get_child_count() > 1:
			stat_grid = hud.stat_content.get_child(1) as GridContainer
		if not is_instance_valid(stat_grid):
			failures.append("hud smoke stat panel should use a dense grid layout for detailed stats")
		else:
			if stat_grid.columns < 2:
				failures.append("hud smoke stat panel should show dense two-column stats on desktop")
			var first_section := stat_grid.get_child(0) if stat_grid.get_child_count() > 0 else null
			if not is_instance_valid(first_section) or _find_label_by_text_prefix(first_section, "선체") == null:
				failures.append("hud smoke stat panel should put ship body details directly after core summary")
			if first_section is PanelContainer:
				failures.append("hud smoke stat panel detail sections should use report-style rows instead of inner cards")
	var site_bonus_panel := hud.get("stat_site_bonus_panel") as Control
	if not is_instance_valid(site_bonus_panel):
		failures.append("hud smoke stat panel should include a right-side site bonus rail")
	else:
		if site_bonus_panel is PanelContainer:
			failures.append("hud smoke site bonus rail should not use a card panel container")
		var site_title := _find_label_by_text_prefix(site_bonus_panel, "해역 보너스")
		if not is_instance_valid(site_title):
			failures.append("hud smoke site bonus rail title missing")
		if _find_label_by_text_prefix(site_bonus_panel, "포격 피해") != null:
			failures.append("hud smoke empty site bonus panel should not list bonuses before rewards")
	if is_instance_valid(hud.get("stat_site_bonus_scroll")) and is_instance_valid(hud.get("stat_site_bonus_content")):
		var site_bonus_scroll := hud.get("stat_site_bonus_scroll") as ScrollContainer
		var site_bonus_content := hud.get("stat_site_bonus_content") as VBoxContainer
		var site_bonus_gutter := site_bonus_content.get_parent() as MarginContainer
		if not is_instance_valid(site_bonus_gutter) or site_bonus_gutter.get_parent() != site_bonus_scroll:
			failures.append("hud smoke site bonus content should sit inside a scrollbar gutter")
		elif site_bonus_gutter.get_theme_constant("margin_right") < 10:
			failures.append("hud smoke site bonus scrollbar gutter should reserve right-side reading space")
	if not is_instance_valid(hud.player_status_root) or not hud.player_status_root.visible:
		failures.append("hud smoke player status overlay was not visible")
	if is_instance_valid(hud.hp_bar):
		if hud.hp_bar.get_parent() == hud.bottom_left_container:
			failures.append("hud smoke player hp bar should not live in bottom-left hud")
		if not is_instance_valid(hud.player_status_root) or not hud.player_status_root.is_ancestor_of(hud.hp_bar):
			failures.append("hud smoke player hp bar should live under player status overlay")
	if is_instance_valid(hud.stamina_bar):
		if hud.stamina_bar.get_parent() == hud.bottom_left_container:
			failures.append("hud smoke player stamina bar should not live in bottom-left hud")
		if not is_instance_valid(hud.player_status_root) or not hud.player_status_root.is_ancestor_of(hud.stamina_bar):
			failures.append("hud smoke player stamina bar should live under player status overlay")


static func _validate_hud_upgrade_track_art(hud: Node, failures: Array[String]) -> void:
	if not is_instance_valid(hud) or not hud.has_method("update_ship_upgrade_ui"):
		return
	hud.call("update_ship_upgrade_ui", "cannon", 1)
	if not is_instance_valid(hud.weapon_track):
		failures.append("hud smoke weapon upgrade track missing")
		return
	var art_slot: PanelContainer = null
	for slot_variant in hud.weapon_track.slots:
		var slot := slot_variant as PanelContainer
		if is_instance_valid(slot) and str(slot.get_meta("upgrade_id", "")) == "cannon":
			art_slot = slot
			break
	if not is_instance_valid(art_slot):
		failures.append("hud smoke upgrade track did not create cannon slot")
		return
	var icon_texture := art_slot.get_node_or_null("IconTexture") as TextureRect
	if not is_instance_valid(icon_texture) or icon_texture.texture == null or not icon_texture.visible:
		failures.append("hud smoke upgrade track should show card art texture when available")
	var icon_label := art_slot.get_node_or_null("Icon") as Label
	if is_instance_valid(icon_label) and icon_label.visible:
		failures.append("hud smoke upgrade track text icon should hide when card art is available")


static func _validate_hud_stat_modal_toggle(hud: Node, failures: Array[String]) -> void:
	if not is_instance_valid(hud) or not hud.has_method("toggle_stat_panel"):
		return
	var tree := hud.get_tree()
	if tree == null:
		return
	var previous_show: bool = bool(hud.get("show_stat_panel"))
	var previous_paused: bool = tree.paused
	var previous_layer: int = int(hud.get("layer"))
	hud.set("show_stat_panel", false)
	if hud.has_method("_update_stat_panel"):
		hud.call("_update_stat_panel")
	hud.call("toggle_stat_panel")
	if not bool(hud.get("show_stat_panel")):
		failures.append("hud smoke stat modal did not open")
	if not tree.paused:
		failures.append("hud smoke stat modal should pause the tree")
	var backdrop := hud.get("stat_backdrop") as ColorRect
	if not is_instance_valid(backdrop) or not backdrop.visible:
		failures.append("hud smoke stat modal backdrop should be visible")
	if int(hud.get("layer")) <= previous_layer:
		failures.append("hud smoke stat modal should raise GameHUD above later UI canvas layers")
	var site_bonus_panel := hud.get("stat_site_bonus_panel") as Control
	if not is_instance_valid(site_bonus_panel) or not site_bonus_panel.visible:
		failures.append("hud smoke stat modal site bonus rail should be visible while open")
	hud.call("toggle_stat_panel")
	if bool(hud.get("show_stat_panel")):
		failures.append("hud smoke stat modal did not close")
	if tree.paused != previous_paused:
		failures.append("hud smoke stat modal did not restore previous pause state")
	if int(hud.get("layer")) != previous_layer:
		failures.append("hud smoke stat modal did not restore previous canvas layer")
	if is_instance_valid(backdrop) and backdrop.visible:
		failures.append("hud smoke stat modal backdrop should hide after closing")
	if is_instance_valid(site_bonus_panel) and site_bonus_panel.visible:
		failures.append("hud smoke stat modal site bonus rail should hide after closing")
	hud.set("show_stat_panel", previous_show)
	if previous_show and hud.has_method("_update_stat_panel"):
		hud.call("_update_stat_panel")


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
	_validate_hud_message_does_not_overlap_timer(hud, failures)


static func _validate_hud_message_does_not_overlap_timer(hud: Node, failures: Array[String]) -> void:
	if not is_instance_valid(hud.gust_warning) or not is_instance_valid(hud.timer_label):
		return
	var timer_panel := hud.timer_label.get_parent() as Control
	if not is_instance_valid(timer_panel):
		return
	var timer_rect: Rect2 = timer_panel.get_global_rect()
	var message_rect: Rect2 = hud.gust_warning.get_global_rect()
	if message_rect.position.y < timer_rect.end.y + 8.0:
		failures.append("hud smoke warning message overlaps timer: message_y %.1f timer_bottom %.1f" % [message_rect.position.y, timer_rect.end.y])


static func _find_button_by_text(root: Node, button_text: String) -> Button:
	if not is_instance_valid(root):
		return null
	if root is Button and str(root.get("text")) == button_text:
		return root as Button
	for child in root.get_children():
		var found := _find_button_by_text(child, button_text)
		if is_instance_valid(found):
			return found
	return null


static func _find_label_by_text_prefix(root: Node, text_prefix: String) -> Label:
	if not is_instance_valid(root):
		return null
	if root is Label and str(root.get("text")).begins_with(text_prefix):
		return root as Label
	for child in root.get_children():
		var found := _find_label_by_text_prefix(child, text_prefix)
		if is_instance_valid(found):
			return found
	return null


static func _option_button_has_metadata(option_button: OptionButton, metadata: String) -> bool:
	if not is_instance_valid(option_button):
		return false
	for index in range(option_button.item_count):
		if str(option_button.get_item_metadata(index)) == metadata:
			return true
	return false


static func _select_option_by_metadata(option_button: OptionButton, metadata: String) -> bool:
	if not is_instance_valid(option_button):
		return false
	for index in range(option_button.item_count):
		if str(option_button.get_item_metadata(index)) != metadata:
			continue
		option_button.select(index)
		option_button.item_selected.emit(index)
		return true
	return false


static func _count_enemy_nodes(owner: Node) -> int:
	return _collect_enemy_nodes(owner).size()


static func _load_user_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}


static func _write_user_json_dictionary(path: String, root: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(root, "\t"))
	return true


static func _wait_frames(owner: Node, frames: int) -> void:
	if frames <= 0 or not is_instance_valid(owner):
		return
	for _index in range(frames):
		await owner.get_tree().process_frame
