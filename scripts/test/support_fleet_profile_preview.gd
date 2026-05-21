extends Node3D

const SUPPORT_SHIP_SCENE := preload("res://scenes/ships/support_ship.tscn")
const PlayerShipSupportHelper = preload("res://scripts/entities/ships/player_ship_support_helper.gd")

const PREVIEW_META := "support_fleet_profile_preview_spawn"
const FLEET_UPGRADES := {
	"fleet_signal": {
		"stats": {
			"limit_add_level": 2,
			"limit_add": 1,
		},
	},
	"panokseon_upgrade": {
		"stats": {
			"panokseon_upgrade_id": "panokseon_upgrade",
			"panokseon_level": 1,
			"panokseon_squadron_limit_add": 1,
		},
	},
	"geobukseon_upgrade": {
		"disabled": true,
		"stats": {
			"geobukseon_upgrade_id": "geobukseon_upgrade",
			"geobukseon_level": 1,
			"geobukseon_squadron_limit_add": 1,
		},
	},
}
const LEGACY_FLEET_HULL_UPGRADES := {
	"fleet_hull": {
		"stats": {
			"panokseon_level": 5,
			"panokseon_squadron_limit_add": 1,
		},
	},
}

@export var auto_open_debug_panel: bool = true
@export var stop_regular_spawns: bool = true

var _assertion_failures: Array[String] = []


func _ready() -> void:
	call_deferred("_configure_preview")


func _configure_preview() -> void:
	PreviewHarnessHelper.setup_common(self, auto_open_debug_panel, stop_regular_spawns)
	_clear_preview_nodes()
	_assert_profile_resolution()
	_assert_profile_application()
	_assert_upgrade_manager_limit()
	_add_preview_labels()
	_report_assertions()


func _clear_preview_nodes() -> void:
	for child in get_children():
		if is_instance_valid(child) and child.has_meta(PREVIEW_META):
			child.queue_free()


func _assert_profile_resolution() -> void:
	var base_profile := PlayerShipSupportSquadronHelper.resolve_support_fleet_profile_for_levels({}, FLEET_UPGRADES, 0)
	_assert_equal("base_slot0_profile", base_profile.get("ship_type", ""), "maengseon_ally")
	_assert_equal("base_slot0_role", base_profile.get("slot_role", ""), "screen_lead")

	var base_rear_profile := PlayerShipSupportSquadronHelper.resolve_support_fleet_profile_for_levels({}, FLEET_UPGRADES, 2)
	_assert_equal("base_slot2_profile", base_rear_profile.get("ship_type", ""), "maengseon_ally")
	_assert_equal("base_slot2_role", base_rear_profile.get("slot_role", ""), "rescue_rear")

	var pre_unlock_profile := PlayerShipSupportSquadronHelper.resolve_support_fleet_profile_for_levels({"fleet_signal": 1}, FLEET_UPGRADES, 1)
	_assert_equal("pre_unlock_slot1_profile", pre_unlock_profile.get("ship_type", ""), "maengseon_ally")

	var unlocked_screen_profile := PlayerShipSupportSquadronHelper.resolve_support_fleet_profile_for_levels({"fleet_signal": 1, "panokseon_upgrade": 1}, FLEET_UPGRADES, 0)
	_assert_equal("unlocked_slot0_profile", unlocked_screen_profile.get("ship_type", ""), "maengseon_ally")
	_assert_equal("unlocked_slot0_squadron", unlocked_screen_profile.get("squadron_id", ""), "flagship_screen")
	_assert_equal("unlocked_slot0_role", unlocked_screen_profile.get("slot_role", ""), "screen_lead")

	var unlocked_profile := PlayerShipSupportSquadronHelper.resolve_support_fleet_profile_for_levels({"fleet_signal": 1, "panokseon_upgrade": 1}, FLEET_UPGRADES, 1)
	_assert_equal("unlocked_slot1_profile", unlocked_profile.get("ship_type", ""), "panokseon_ally")
	_assert_equal("unlocked_slot1_squadron", unlocked_profile.get("squadron_id", ""), "panokseon_artillery")
	_assert_equal("unlocked_slot1_role", unlocked_profile.get("slot_role", ""), "artillery_lead")

	var geobuk_profile := PlayerShipSupportSquadronHelper.resolve_support_fleet_profile_for_levels({"fleet_signal": 1, "geobukseon_upgrade": 1}, FLEET_UPGRADES, 1)
	_assert_equal("disabled_geobuk_slot1_profile", geobuk_profile.get("ship_type", ""), "maengseon_ally")
	_assert_equal("disabled_geobuk_slot1_squadron", geobuk_profile.get("squadron_id", ""), "flagship_screen")
	_assert_equal("disabled_geobuk_slot1_role", geobuk_profile.get("slot_role", ""), "screen_flank")

	var mixed_profile := PlayerShipSupportSquadronHelper.resolve_support_fleet_profile_for_levels({"fleet_signal": 1, "panokseon_upgrade": 1, "geobukseon_upgrade": 1}, FLEET_UPGRADES, 2)
	_assert_equal("mixed_slot2_profile", mixed_profile.get("ship_type", ""), "maengseon_ally")

	var legacy_profile := PlayerShipSupportSquadronHelper.resolve_support_fleet_profile_for_levels({"fleet_hull": 5}, LEGACY_FLEET_HULL_UPGRADES, 0)
	_assert_equal("legacy_hull_unlock_slot0_profile", legacy_profile.get("ship_type", ""), "maengseon_ally")


func _assert_profile_application() -> void:
	var support_ship := SUPPORT_SHIP_SCENE.instantiate()
	if not is_instance_valid(support_ship):
		_record_failure("cannot_instantiate_support_ship")
		return

	var profile := PlayerShipSupportSquadronHelper.resolve_support_fleet_profile_for_levels({"fleet_signal": 1, "panokseon_upgrade": 1}, FLEET_UPGRADES, 1)
	PlayerShipSupportSquadronHelper.apply_support_fleet_profile(support_ship, profile)
	_assert_equal("applied_ship_type", support_ship.get("ship_type"), "panokseon_ally")
	_assert_equal("applied_hull_scene", _scene_path(support_ship.get("hull_scene")), "res://scenes/ships/hulls/panok_hull.tscn")
	_assert_equal("applied_cannon_scene", _scene_path(support_ship.get("cannon_scene")), "res://scenes/entities/launchers/cannon_joseon.tscn")
	support_ship.free()


func _assert_upgrade_manager_limit() -> void:
	var player := get_node_or_null("PlayerShip")
	var upgrade_manager := get_node_or_null("/root/UpgradeManager")
	if not is_instance_valid(player) or not is_instance_valid(upgrade_manager):
		_record_failure("missing_limit_bonus_context")
		return
	if not ("current_levels" in upgrade_manager) or not upgrade_manager.current_levels is Dictionary:
		_record_failure("missing_current_levels")
		return
	if not upgrade_manager.has_method("reconcile_support_fleet"):
		_record_failure("missing_reconcile_support_fleet")
		return

	var original_levels: Dictionary = upgrade_manager.current_levels.duplicate(true)
	var original_limit: int = int(player.get("support_fleet_limit")) if "support_fleet_limit" in player else 0
	var original_base_limit: Variant = player.get_meta("base_support_fleet_limit") if player.has_meta("base_support_fleet_limit") else null
	var original_choyogi: Variant = player.get_meta("item_choyogi_applied") if player.has_meta("item_choyogi_applied") else null

	player.set("support_fleet_limit", 1)
	player.set_meta("base_support_fleet_limit", 1)
	if player.has_meta("item_choyogi_applied"):
		player.remove_meta("item_choyogi_applied")
	upgrade_manager.current_levels["fleet_crew"] = 0
	upgrade_manager.current_levels["fleet_signal"] = 0
	upgrade_manager.current_levels["panokseon_upgrade"] = 0
	player.set_meta("item_choyogi_applied", true)
	upgrade_manager.call("reconcile_support_fleet", player, "preview_choyogi_meta_limit", {})
	_assert_equal("choyogi_meta_does_not_add_raw_support_slot", int(player.get("support_fleet_limit")), 1)
	player.remove_meta("item_choyogi_applied")

	upgrade_manager.current_levels["fleet_signal"] = 1
	upgrade_manager.current_levels["panokseon_upgrade"] = 1
	upgrade_manager.call("reconcile_support_fleet", player, "preview_limit", {})
	_assert_equal("panokseon_upgrade_adds_support_slot", int(player.get("support_fleet_limit")), 2)

	upgrade_manager.current_levels = original_levels
	player.set("support_fleet_limit", original_limit)
	if original_base_limit == null:
		if player.has_meta("base_support_fleet_limit"):
			player.remove_meta("base_support_fleet_limit")
	else:
		player.set_meta("base_support_fleet_limit", original_base_limit)
	if original_choyogi == null:
		if player.has_meta("item_choyogi_applied"):
			player.remove_meta("item_choyogi_applied")
	else:
		player.set_meta("item_choyogi_applied", original_choyogi)


func _scene_path(value: Variant) -> String:
	if value is PackedScene:
		return (value as PackedScene).resource_path
	return ""


func _assert_equal(case_id: String, actual: Variant, expected: Variant) -> void:
	if actual != expected:
		_record_failure("%s expected %s got %s" % [case_id, str(expected), str(actual)])


func _record_failure(message: String) -> void:
	_assertion_failures.append(message)


func _report_assertions() -> void:
	if _assertion_failures.is_empty():
		print("[SupportFleetProfilePreview] support profile assertions OK")
		return
	push_error("[SupportFleetProfilePreview] assertion failures: %s" % ", ".join(_assertion_failures))
	get_tree().quit(1)


func _add_preview_labels() -> void:
	var player := get_node_or_null("PlayerShip") as Node3D
	var anchor := Vector3.ZERO
	if is_instance_valid(player):
		anchor = player.global_position + Vector3(0.0, 8.0, 0.0)
	var label := PreviewHarnessHelper.add_billboard_label(
		self,
		"Support squadron slots\nMaengseon screen + Panokseon artillery\nGeobukseon disabled fallback",
		anchor,
		Color(0.58, 0.9, 1.0, 1.0),
		32
	)
	if is_instance_valid(label):
		label.set_meta(PREVIEW_META, true)
