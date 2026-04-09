extends RefCounted

const SAIL_MODE_ICON = preload("res://assets/ui/hud/sail_mode_icon.svg")
const MATERIAL_SYMBOLS_FONT = preload("res://assets/fonts/MaterialSymbolsOutlined.ttf")
const SUPPORT_FLEET_ICON = preload("res://assets/ui/support_fleet/support_fleet_bow_icon.png")
const EntityRegistry = preload("res://scripts/helpers/entity_registry.gd")
const NavalUiTheme = preload("res://scripts/ui/naval_ui_theme.gd")
const CAPTURE_HINT_DISTANCE_PADDING: float = 2.5
const CAPTURE_HINT_CREW_RATIO: float = 0.34
const CAPTURE_HINT_CREW_MAX: int = 2

# Top-line HUD text
static func update_level(hud, val: int) -> void:
	if hud.level_label:
		hud.level_label.text = "[Lv] %d" % val

static func update_score(hud, val: int) -> void:
	if hud.score_label:
		var total_gold = SaveManager.gold if is_instance_valid(SaveManager) else val
		hud.score_label.text = "[Gold] %d (Total %d)" % [val, total_gold]

static func update_combat_stats(hud, ship_sunk: int, ships_derelicted: int, soldiers_killed: int, _soldiers_slain: int, _soldiers_drowned: int) -> void:
	var text = "[전과] 격침 %d | 나포 %d | 병사 %d" % [ship_sunk, ships_derelicted, soldiers_killed]
	if hud._last_combat_stats_text == text:
		return
	hud._last_combat_stats_text = text
	if hud.combat_stats_label:
		hud.combat_stats_label.text = "[전과]"
	if hud.combat_sunk_value_label:
		hud.combat_sunk_value_label.text = str(ship_sunk)
	if hud.combat_derelict_value_label:
		hud.combat_derelict_value_label.text = str(ships_derelicted)
	if hud.combat_soldier_value_label:
		hud.combat_soldier_value_label.text = str(soldiers_killed)

static func update_difficulty_ui(hud, val: int) -> void:
	if hud.difficulty_label:
		var new_text = "[Diff] %d" % val
		if hud._last_difficulty_text != new_text:
			hud._last_difficulty_text = new_text
			hud.difficulty_label.text = new_text

static func update_crew_status(hud, count: int, max_count: int = 4) -> void:
	if hud.crew_label:
		hud.crew_label.text = "병사 %d / %d" % [count, max_count]

static func update_timer(hud) -> void:
	if hud.timer_label:
		var total_seconds: int = int(hud.game_time)
		var minutes: int = int(total_seconds / 60.0)
		var seconds: int = total_seconds % 60
		var new_str = "%d:%02d" % [minutes, seconds]
		if hud._last_timer_str != new_str:
			hud._last_timer_str = new_str
			hud.timer_label.text = new_str

# Main status bars
static func _apply_speed_bar_state(hud, speed_state: String) -> void:
	if not hud.speed_mode_icon or not hud.speed_bar:
		return
	hud.speed_mode_icon.texture = SAIL_MODE_ICON
	if speed_state == "rowing":
		hud.speed_mode_icon.modulate = NavalUiTheme.TEXT_GOLD
	elif speed_state == "exhausted":
		hud.speed_mode_icon.modulate = NavalUiTheme.STATUS_WARN
	elif speed_state == "locked":
		hud.speed_mode_icon.modulate = NavalUiTheme.TEXT_MUTED
	else:
		hud.speed_mode_icon.modulate = NavalUiTheme.TEXT_BLUE
	var fill = hud.speed_bar.get_theme_stylebox("fill")
	if fill is StyleBoxFlat:
		var fill_box := fill as StyleBoxFlat
		if speed_state == "rowing":
			fill_box.bg_color = NavalUiTheme.STATUS_WARN
		elif speed_state == "exhausted":
			fill_box.bg_color = Color(0.78, 0.58, 0.22, 0.92)
		elif speed_state == "locked":
			fill_box.bg_color = Color(0.52, 0.40, 0.32, 0.92)
		else:
			fill_box.bg_color = NavalUiTheme.STATUS_ACTIVE_BLUE

static func update_speed_display(hud) -> void:
	if not is_instance_valid(hud.player_ship):
		return
	if hud.player_ship.get("current_speed") == null:
		return
	var speed: float = float(hud.player_ship.current_speed)
	var max_speed: float = 1.0
	if hud.player_ship.get("max_speed") != null:
		max_speed = maxf(float(hud.player_ship.max_speed), 0.01)
	var speed_ratio: float = clampf(speed / max_speed, 0.0, 1.0)
	var is_rowing_active: bool = hud.player_ship.get("is_rowing") == true
	var is_rowing_locked: bool = hud.player_ship.get("rowing_locked") == true
	var speed_state := "exhausted" if (is_rowing_active and is_rowing_locked) else ("locked" if is_rowing_locked else ("rowing" if is_rowing_active else "sail"))
	if hud.speed_bar:
		var target_value = speed_ratio * 100.0
		var speed_text = "%.1f" % speed
		if hud.speed_bar_label and hud.speed_bar_label.text != speed_text:
			hud.speed_bar_label.text = speed_text
		if absf(hud._last_speed_ratio - speed_ratio) > 0.005:
			hud._last_speed_ratio = speed_ratio
		hud._speed_visual_value = lerpf(hud._speed_visual_value, target_value, 0.35)
		if absf(hud.speed_bar.value - hud._speed_visual_value) > 0.1:
			hud.speed_bar.value = hud._speed_visual_value
		if hud._last_speed_mode != speed_state:
			hud._last_speed_mode = speed_state
			_apply_speed_bar_state(hud, speed_state)
	elif hud.speed_display:
		var speed_text = "%.1f ㏏" % speed
		if hud._last_speed_str != speed_text:
			hud._last_speed_str = speed_text
			hud.speed_display.text = speed_text

# Crew and combat
static func update_force_panel(hud) -> void:
	if not is_instance_valid(hud.player_ship):
		return
	_update_support_force_status(hud)

static func _update_crew_force_status(hud) -> void:
	pass

static func _update_support_force_status(hud) -> void:
	if not hud.support_slot_container or not is_instance_valid(hud.player_ship):
		return
	var support_ships: Array = []
	if hud.player_ship.has_method("_get_support_fleet_ships"):
		support_ships = hud.player_ship._get_support_fleet_ships()
	_ensure_support_slot_count(hud, support_ships.size())

	for i in range(hud.support_fleet_hud_slots.size()):
		var slot: PanelContainer = hud.support_fleet_hud_slots[i]
		if not is_instance_valid(slot):
			continue
		var ship = support_ships[i] if i < support_ships.size() else null
		_update_support_slot(slot, ship, "")

static func update_crew_count(hud) -> void:
	if Engine.get_process_frames() % 30 != 0:
		return
	if not is_instance_valid(hud.player_ship):
		return
	pass

static func _is_support_respawn_active(player_ship) -> bool:
	if not is_instance_valid(player_ship):
		return false
	if not is_instance_valid(UpgradeManager) or "current_levels" not in UpgradeManager:
		return false
	if player_ship.get("is_sinking") == true or player_ship.get("is_dying") == true:
		return false
	return int(UpgradeManager.current_levels.get("fleet_signal", 0)) > 0

static func _ensure_support_slot_count(hud, slot_count: int) -> void:
	while hud.support_fleet_hud_slots.size() < slot_count:
		var slot: PanelContainer = _create_support_slot()
		hud.support_slot_container.add_child(slot)
		hud.support_fleet_hud_slots.append(slot)
	while hud.support_fleet_hud_slots.size() > slot_count:
		var last_slot: PanelContainer = hud.support_fleet_hud_slots.pop_back()
		if is_instance_valid(last_slot):
			last_slot.queue_free()

static func _create_support_slot() -> PanelContainer:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(76, 76)
	var slot_style := StyleBoxFlat.new()
	slot_style.bg_color = Color(0.05, 0.07, 0.10, 0.90)
	slot_style.border_color = Color(0.84, 0.68, 0.35, 0.90)
	slot_style.border_width_left = 2
	slot_style.border_width_top = 2
	slot_style.border_width_right = 2
	slot_style.border_width_bottom = 2
	slot_style.corner_radius_top_left = 38
	slot_style.corner_radius_top_right = 38
	slot_style.corner_radius_bottom_right = 38
	slot_style.corner_radius_bottom_left = 38
	slot.add_theme_stylebox_override("panel", slot_style)

	var root := Control.new()
	root.name = "Root"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slot.add_child(root)

	var damage_fill := Panel.new()
	damage_fill.name = "DamageFill"
	damage_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	damage_fill.anchor_left = 0.0
	damage_fill.anchor_right = 1.0
	damage_fill.anchor_top = 1.0
	damage_fill.anchor_bottom = 1.0
	damage_fill.offset_left = 0.0
	damage_fill.offset_right = 0.0
	damage_fill.offset_top = 0.0
	damage_fill.offset_bottom = 0.0
	var damage_style := StyleBoxFlat.new()
	damage_style.bg_color = Color(0.92, 0.24, 0.24, 0.76)
	damage_style.corner_radius_top_left = 38
	damage_style.corner_radius_top_right = 38
	damage_style.corner_radius_bottom_right = 38
	damage_style.corner_radius_bottom_left = 38
	damage_fill.add_theme_stylebox_override("panel", damage_style)
	root.add_child(damage_fill)

	var dead_overlay := Panel.new()
	dead_overlay.name = "DeadOverlay"
	dead_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dead_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dead_style := StyleBoxFlat.new()
	dead_style.bg_color = Color(0.08, 0.08, 0.08, 0.72)
	dead_style.corner_radius_top_left = 38
	dead_style.corner_radius_top_right = 38
	dead_style.corner_radius_bottom_right = 38
	dead_style.corner_radius_bottom_left = 38
	dead_overlay.add_theme_stylebox_override("panel", dead_style)
	dead_overlay.visible = false
	root.add_child(dead_overlay)

	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.anchor_left = 0.0
	icon.anchor_top = 0.0
	icon.anchor_right = 1.0
	icon.anchor_bottom = 1.0
	icon.offset_left = 4.0
	icon.offset_top = 4.0
	icon.offset_right = -4.0
	icon.offset_bottom = -4.0
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(68, 68)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = SUPPORT_FLEET_ICON
	icon.modulate = NavalUiTheme.TEXT_MAIN
	root.add_child(icon)

	var timer := Label.new()
	timer.name = "Timer"
	timer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	NavalUiTheme.style_overlay_value(timer, 10)
	timer.add_theme_constant_override("outline_size", 3)
	timer.visible = false
	root.add_child(timer)

	return slot

static func _update_support_slot(slot: PanelContainer, ship, timer_text: String = "") -> void:
	var slot_style: StyleBoxFlat = slot.get_theme_stylebox("panel") as StyleBoxFlat
	var damage_fill: ColorRect = slot.get_node("Root/DamageFill") as ColorRect
	var dead_overlay: ColorRect = slot.get_node("Root/DeadOverlay") as ColorRect
	var icon: TextureRect = slot.get_node("Root/Icon") as TextureRect
	var timer: Label = slot.get_node("Root/Timer") as Label
	if not is_instance_valid(icon) or not is_instance_valid(dead_overlay) or not is_instance_valid(damage_fill) or not is_instance_valid(timer):
		return
	if is_instance_valid(ship) and ship.get("hull_hp") != null and ship.get("max_hull_hp") != null:
		var max_hp: float = maxf(float(ship.max_hull_hp), 1.0)
		var hull_hp: float = clampf(float(ship.hull_hp), 0.0, max_hp)
		var lost_ratio: float = clampf(1.0 - (hull_hp / max_hp), 0.0, 1.0)
		damage_fill.visible = lost_ratio > 0.01
		damage_fill.anchor_top = 1.0 - lost_ratio
		damage_fill.anchor_bottom = 1.0
		damage_fill.offset_top = 0.0
		damage_fill.offset_bottom = 0.0
		dead_overlay.visible = false
		icon.visible = true
		icon.texture = SUPPORT_FLEET_ICON
		icon.modulate = NavalUiTheme.TEXT_MAIN
		timer.visible = false
		timer.text = ""
		if slot_style:
			slot_style.bg_color = NavalUiTheme.PANEL_BG_DARK
			slot_style.border_color = NavalUiTheme.BORDER_GOLD_DIM
	else:
		damage_fill.visible = false
		dead_overlay.visible = true
		icon.visible = true
		icon.texture = SUPPORT_FLEET_ICON
		icon.modulate = Color(0.62, 0.66, 0.72, 0.82)
		timer.visible = not timer_text.is_empty()
		timer.text = timer_text
		if slot_style:
			slot_style.bg_color = Color(0.06, 0.07, 0.09, 0.9)
			slot_style.border_color = NavalUiTheme.STATUS_DEAD

static func update_hull_display(hud) -> void:
	if is_instance_valid(hud.player_ship) and hud.player_ship.get("hull_hp") != null:
		hud.update_hull_hp(hud.player_ship.hull_hp, hud.player_ship.max_hull_hp)

static func update_stamina_display(hud) -> void:
	if is_instance_valid(hud.player_ship) and hud.player_ship.get("rowing_stamina") != null:
		var max_stamina: float = 100.0
		if hud.player_ship.get("max_rowing_stamina") != null:
			max_stamina = float(hud.player_ship.max_rowing_stamina)
		hud.update_stamina(hud.player_ship.rowing_stamina, max_stamina)

static func update_boarding_display(hud) -> void:
	if not hud.boarding_ui or not is_instance_valid(hud.player_ship):
		return
	var is_boarding = hud.player_ship.get("is_boarding") == true
	var prep_timer = hud.player_ship.get("boarding_prep_timer") if "boarding_prep_timer" in hud.player_ship else 0.0
	var prep_duration = hud.player_ship.get("boarding_prep_duration") if "boarding_prep_duration" in hud.player_ship else 2.5
	if is_boarding:
		hud.boarding_ui.visible = true
		if prep_timer < prep_duration:
			hud.boarding_label.text = "도선 준비 중 (밧줄 고정)..."
			hud.boarding_bar.value = (prep_timer / prep_duration) * 100
			var fill = hud.boarding_bar.get_theme_stylebox("fill") as StyleBoxFlat
			if fill:
				fill.bg_color = Color(1.0, 1.0, 1.0, 0.7)
		else:
			hud.boarding_label.text = "도선 진행 중!"
			hud.boarding_bar.value = 100
			var fill_active = hud.boarding_bar.get_theme_stylebox("fill") as StyleBoxFlat
			if fill_active:
				fill_active.bg_color = NavalUiTheme.STATUS_ACTIVE_BLUE
	else:
		hud.boarding_ui.visible = false

static func update_capture_opportunity_display(hud) -> void:
	if not is_instance_valid(hud.capture_opportunity_label):
		return
	if not is_instance_valid(hud.player_ship):
		hud.capture_opportunity_label.visible = false
		hud._last_capture_opportunity_text = ""
		return
	var next_text: String = _get_capture_opportunity_text(hud.player_ship)
	if next_text.is_empty():
		if hud.capture_opportunity_label.visible:
			hud.capture_opportunity_label.visible = false
		hud._last_capture_opportunity_text = ""
		return
	if hud._last_capture_opportunity_text != next_text:
		hud._last_capture_opportunity_text = next_text
		hud.capture_opportunity_label.text = next_text
	hud.capture_opportunity_label.visible = true

static func _get_capture_opportunity_text(player_ship) -> String:
	if not is_instance_valid(player_ship):
		return ""
	if player_ship.get("is_boarding") == true:
		return ""

	var best_derelict: Node3D = null
	var best_derelict_dist: float = INF
	var best_weakened: Node3D = null
	var best_weakened_dist: float = INF
	var best_weakened_alive: int = 0

	var detect_distance: float = 12.0
	if player_ship.get("max_boarding_distance") != null:
		detect_distance = float(player_ship.get("max_boarding_distance")) + CAPTURE_HINT_DISTANCE_PADDING

	var ships: Array = EntityRegistry.get_ships_by_team("enemy")
	for ship in ships:
		if not is_instance_valid(ship) or ship == player_ship:
			continue
		if str(ship.get("team")) != "enemy":
			continue
		if ship.get("is_dying") == true or ship.get("is_sinking") == true:
			continue

		var distance: float = player_ship.global_position.distance_to(ship.global_position)
		if distance > detect_distance:
			continue

		if ship.get("is_derelict") == true:
			if distance < best_derelict_dist:
				best_derelict = ship
				best_derelict_dist = distance
			continue

		if player_ship.has_method("_is_side_boarding_approach"):
			var can_side_board: bool = player_ship.call("_is_side_boarding_approach", ship) == true
			if not can_side_board:
				continue

		if not ship.has_method("get_alive_crew_count"):
			continue
		var alive_count: int = int(ship.call("get_alive_crew_count"))
		var max_count: int = alive_count
		if ship.get("max_crew_count") != null:
			max_count = max(1, int(ship.get("max_crew_count")))
		var low_crew_threshold: int = max(1, min(CAPTURE_HINT_CREW_MAX, int(ceili(float(max_count) * CAPTURE_HINT_CREW_RATIO))))
		if alive_count > low_crew_threshold:
			continue
		if distance < best_weakened_dist:
			best_weakened = ship
			best_weakened_dist = distance
			best_weakened_alive = alive_count

	if is_instance_valid(best_derelict):
		return "폐선 확보 가능"
	if is_instance_valid(best_weakened):
		return "나포 기회 - 적선 병력 %d" % best_weakened_alive
	return ""

static func update_boss_hp(hud, current: float, maximum: float) -> void:
	if hud.boss_hp_bar_new:
		hud.boss_hp_bar_new.max_value = maximum
		hud.boss_hp_bar_new.visible = current > 0
		var tween = hud.create_tween()
		tween.tween_property(hud.boss_hp_bar_new, "value", current, 0.2)
		if hud.boss_hp_text_label:
			hud.boss_hp_text_label.text = "BOSS: %.0f/%.0f" % [current, maximum]

# Ship HP overlay
static func update_ship_health_bars(hud, positions_only: bool = false) -> void:
	if not is_instance_valid(hud.ship_hp_overlay):
		return
	if not hud.show_ship_health_bars:
		_hide_all_ship_health_bars(hud)
		return
	var cam: Camera3D = hud.get_viewport().get_camera_3d()
	if not is_instance_valid(cam):
		return
	var viewport_rect: Rect2 = hud.get_viewport().get_visible_rect()
	var active_ids: Dictionary = {}
	var ships: Array = EntityRegistry.get_ships()
	for ship in ships:
		if not _is_ship_hp_bar_target_valid(ship):
			continue
		var ship_id: int = ship.get_instance_id()
		if not _update_single_ship_health_bar(hud, ship, cam, viewport_rect, positions_only):
			continue
		active_ids[ship_id] = true
	_cleanup_stale_ship_hp_bars(hud, active_ids)

static func _hide_all_ship_health_bars(hud) -> void:
	for bar_root in hud.ship_hp_bars.values():
		if is_instance_valid(bar_root):
			bar_root.visible = false

static func _is_ship_hp_bar_target_valid(ship) -> bool:
	if not is_instance_valid(ship) or not ship.is_inside_tree():
		return false
	if ship.get("hull_hp") == null or ship.get("max_hull_hp") == null:
		return false
	if ship.get("is_sinking") == true or ship.get("is_dying") == true:
		return false
	var max_hp: float = float(ship.get("max_hull_hp"))
	if max_hp <= 0.0:
		return false
	var current_hp: float = clampf(float(ship.get("hull_hp")), 0.0, max_hp)
	return current_hp > 0.0

static func _update_single_ship_health_bar(hud, ship, cam: Camera3D, viewport_rect: Rect2, positions_only: bool = false) -> bool:
	var max_hp: float = float(ship.get("max_hull_hp"))
	var current_hp: float = clampf(float(ship.get("hull_hp")), 0.0, max_hp)
	var deck_height: float = 0.5
	if ship.get("deck_height") != null:
		deck_height = float(ship.get("deck_height"))
	var world_pos: Vector3 = ship.global_position + Vector3(0.0, deck_height + 0.45, 0.0)
	var cam_forward: Vector3 = -cam.global_transform.basis.z
	if cam_forward.dot(world_pos - cam.global_position) <= 0.0:
		return false
	var screen_pos: Vector2 = cam.unproject_position(world_pos)
	if screen_pos.x < -80.0 or screen_pos.y < -40.0 or screen_pos.x > viewport_rect.size.x + 80.0 or screen_pos.y > viewport_rect.size.y + 80.0:
		return false
	var ship_id: int = ship.get_instance_id()
	var team_tag: String = "enemy"
	if ship.get("team") != null:
		team_tag = str(ship.get("team"))
	var bar_root: Control = _ensure_ship_hp_bar(hud, ship_id, team_tag)
	bar_root.visible = true
	bar_root.position = screen_pos + Vector2(-hud.SHIP_HP_BAR_WIDTH * 0.5, hud.SHIP_HP_BAR_OFFSET_Y)
	var hp_bar: ProgressBar = bar_root.get_node("Bar") as ProgressBar
	if not is_instance_valid(hp_bar):
		return false
	if positions_only:
		return true
	hp_bar.max_value = max_hp
	hp_bar.value = current_hp
	var ratio: float = current_hp / max_hp
	var fill_style: StyleBoxFlat = hp_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if is_instance_valid(fill_style):
		if ratio > 0.6:
			fill_style.bg_color = NavalUiTheme.STATUS_GOOD
		elif ratio > 0.3:
			fill_style.bg_color = NavalUiTheme.STATUS_WARN
		else:
			fill_style.bg_color = NavalUiTheme.STATUS_DANGER
	return true

static func _cleanup_stale_ship_hp_bars(hud, active_ids: Dictionary) -> void:
	var stale_ids: Array = []
	for ship_id_variant in hud.ship_hp_bars.keys():
		var ship_id: int = int(ship_id_variant)
		if active_ids.has(ship_id):
			continue
		stale_ids.append(ship_id)
	for stale_id_variant in stale_ids:
		var stale_id: int = int(stale_id_variant)
		var stale_bar: Control = hud.ship_hp_bars[stale_id]
		if is_instance_valid(stale_bar):
			stale_bar.queue_free()
		hud.ship_hp_bars.erase(stale_id)

static func _ensure_ship_hp_bar(hud, ship_id: int, team_tag: String) -> Control:
	if hud.ship_hp_bars.has(ship_id):
		var existing: Control = hud.ship_hp_bars[ship_id]
		if is_instance_valid(existing):
			return existing
	var bar_root: Control = Control.new()
	bar_root.name = "ShipHP_%d" % ship_id
	bar_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_root.custom_minimum_size = Vector2(hud.SHIP_HP_BAR_WIDTH, hud.SHIP_HP_BAR_HEIGHT)
	bar_root.size = bar_root.custom_minimum_size
	bar_root.z_index = 20
	hud.ship_hp_overlay.add_child(bar_root)

	var hp_bar: ProgressBar = ProgressBar.new()
	hp_bar.name = "Bar"
	hp_bar.show_percentage = false
	hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_bar.custom_minimum_size = Vector2(hud.SHIP_HP_BAR_WIDTH, hud.SHIP_HP_BAR_HEIGHT)
	hp_bar.size = hp_bar.custom_minimum_size
	hp_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	bar_root.add_child(hp_bar)

	var bg_style: StyleBoxFlat = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.03, 0.04, 0.06, 0.72)
	bg_style.set_border_width_all(1)
	bg_style.border_color = NavalUiTheme.STATUS_ACTIVE_BLUE if team_tag == "player" else Color(1.0, 0.42, 0.42, 0.95)
	bg_style.set_corner_radius_all(3)
	hp_bar.add_theme_stylebox_override("background", bg_style)

	var fill_style: StyleBoxFlat = StyleBoxFlat.new()
	fill_style.bg_color = NavalUiTheme.STATUS_GOOD
	fill_style.set_corner_radius_all(2)
	hp_bar.add_theme_stylebox_override("fill", fill_style)

	hud.ship_hp_bars[ship_id] = bar_root
	return bar_root
