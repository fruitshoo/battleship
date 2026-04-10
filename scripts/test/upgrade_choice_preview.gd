extends Node3D

const PreviewHarnessHelper = preload("res://scripts/test/preview_harness_helper.gd")
const NavalUiTheme = preload("res://scripts/ui/naval_ui_theme.gd")

@export var auto_open_debug_panel: bool = false
@export var stop_regular_spawns: bool = true
@export var trial_count: int = 12
@export var auto_print_summary: bool = true
@export var auto_quit_delay_seconds: float = 0.05

var _overlay_panel: PanelContainer = null
var _overlay_label: Label = null
var _round_sequence: Array[String] = ["ship", "crew", "ship", "crew", "ship", "crew"]
var _round_offer_counts: Array[Dictionary] = []
var _round_pick_counts: Array[Dictionary] = []
var _early_fleet_offer_count: int = 0


func _ready() -> void:
	call_deferred("_configure_preview")


func _configure_preview() -> void:
	PreviewHarnessHelper.setup_common(self, auto_open_debug_panel, stop_regular_spawns)
	_ensure_overlay()
	_run_trials()
	_update_overlay()
	if auto_print_summary:
		_print_summary()
	if _should_auto_quit_after_report():
		call_deferred("_quit_after_report")


func _run_trials() -> void:
	_round_offer_counts.clear()
	_round_pick_counts.clear()
	_early_fleet_offer_count = 0
	for _round_type in _round_sequence:
		_round_offer_counts.append({})
		_round_pick_counts.append({})

	for trial_index in range(trial_count):
		_reset_upgrade_state_for_trial()
		seed(9000 + trial_index)

		for round_index in range(_round_sequence.size()):
			var round_type: String = _round_sequence[round_index]
			var choices: Array = _get_round_choices(round_type)
			for choice in choices:
				var upgrade_id := str(choice)
				_increment_count(_round_offer_counts[round_index], upgrade_id)
				if round_index < 4 and upgrade_id.begins_with("fleet_"):
					_early_fleet_offer_count += 1
			var picked_id := _pick_choice(round_type, choices)
			if not picked_id.is_empty():
				_increment_count(_round_pick_counts[round_index], picked_id)
				_apply_mock_choice(picked_id)
			if auto_print_summary:
				print("[UpgradeChoice] trial=%d round=%d type=%s choices=%s picked=%s" % [
					trial_index + 1,
					round_index + 1,
					round_type,
					", ".join(_stringify_choices(choices)),
					picked_id,
				])


func _reset_upgrade_state_for_trial() -> void:
	if not is_instance_valid(UpgradeManager):
		return
	if UpgradeManager.has_method("reset_run_upgrades"):
		UpgradeManager.reset_run_upgrades()
	for upgrade_id in UpgradeManager.current_levels.keys():
		UpgradeManager.current_levels[upgrade_id] = 0
	UpgradeManager.current_levels["cannon"] = 1


func _get_round_choices(round_type: String) -> Array:
	if not is_instance_valid(UpgradeManager):
		return []
	if round_type == "crew":
		return UpgradeManager.get_command_upgrade_choices(3)
	return UpgradeManager.get_ship_upgrade_choices(3)


func _pick_choice(round_type: String, choices: Array) -> String:
	if choices.is_empty():
		return ""
	for choice in choices:
		var upgrade_id := str(choice)
		if round_type == "ship" and (upgrade_id == "cannon" or upgrade_id == "janggun"):
			return upgrade_id
		if round_type == "crew" and (upgrade_id == "crew_reserve" or upgrade_id == "boarding_resist"):
			return upgrade_id
	return str(choices[0])


func _apply_mock_choice(upgrade_id: String) -> void:
	if not is_instance_valid(UpgradeManager):
		return
	var current_level: int = int(UpgradeManager.current_levels.get(upgrade_id, 0))
	var max_level: int = int(UpgradeManager.UPGRADES.get(upgrade_id, {}).get("max_level", current_level))
	UpgradeManager.current_levels[upgrade_id] = mini(current_level + 1, max_level)


func _increment_count(counter: Dictionary, key: String) -> void:
	counter[key] = int(counter.get(key, 0)) + 1


func _stringify_choices(choices: Array) -> Array[String]:
	var result: Array[String] = []
	for choice in choices:
		result.append(str(choice))
	return result


func _print_summary() -> void:
	print("[UpgradeChoice] summary trials=%d early_fleet_offers=%d" % [trial_count, _early_fleet_offer_count])
	for round_index in range(_round_sequence.size()):
		var round_type: String = _round_sequence[round_index]
		print("[UpgradeChoice] round=%d type=%s offers=%s picks=%s" % [
			round_index + 1,
			round_type,
			_format_counter(_round_offer_counts[round_index]),
			_format_counter(_round_pick_counts[round_index]),
		])


func _format_counter(counter: Dictionary) -> String:
	var parts: Array[String] = []
	var keys: Array[String] = []
	for key in counter.keys():
		keys.append(str(key))
	keys.sort()
	for key in keys:
		parts.append("%s:%d" % [key, int(counter.get(key, 0))])
	return ", ".join(parts)


func _ensure_overlay() -> void:
	if is_instance_valid(_overlay_panel):
		return
	var hud: Node = get_node_or_null("GameHUD")
	if not is_instance_valid(hud):
		return

	_overlay_panel = PanelContainer.new()
	_overlay_panel.name = "UpgradeChoicePreviewOverlay"
	_overlay_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_overlay_panel.offset_left = 20.0
	_overlay_panel.offset_top = 20.0
	_overlay_panel.offset_right = 580.0
	_overlay_panel.offset_bottom = 220.0
	_overlay_panel.z_index = 100
	_overlay_panel.add_theme_stylebox_override(
		"panel",
		NavalUiTheme.make_panel_style(NavalUiTheme.PANEL_BG_SOFT, NavalUiTheme.BORDER_GOLD_DIM, 10, 1, 10.0, 8.0, 10.0, 8.0)
	)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_overlay_panel.add_child(box)

	var title := Label.new()
	title.text = "Upgrade Choice Preview"
	NavalUiTheme.style_heading(title, 14)
	box.add_child(title)

	_overlay_label = Label.new()
	_overlay_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	NavalUiTheme.style_body(_overlay_label, 12)
	box.add_child(_overlay_label)

	hud.add_child(_overlay_panel)


func _update_overlay() -> void:
	if not is_instance_valid(_overlay_label):
		return
	var lines: Array[String] = []
	lines.append("trials:%d  early fleet offers:%d" % [trial_count, _early_fleet_offer_count])
	for round_index in range(mini(4, _round_sequence.size())):
		var picks: Dictionary = _round_pick_counts[round_index] if round_index < _round_pick_counts.size() else {}
		lines.append("r%d %s picks: %s" % [
			round_index + 1,
			_round_sequence[round_index],
			_format_counter(picks),
		])
	_overlay_label.text = "\n".join(lines)


func _should_auto_quit_after_report() -> bool:
	return _env_flag_enabled("BATTLESHIP_UPGRADE_CHOICE_AUTO_QUIT")


func _quit_after_report() -> void:
	await get_tree().create_timer(maxf(auto_quit_delay_seconds, 0.01)).timeout
	get_tree().quit()


func _env_flag_enabled(name: String) -> bool:
	var value := OS.get_environment(name).strip_edges().to_lower()
	return value == "1" or value == "true" or value == "yes" or value == "on"
