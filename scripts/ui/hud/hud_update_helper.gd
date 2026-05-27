extends RefCounted

const SAIL_MODE_ICON = preload("res://assets/ui/hud/sail_mode_icon.svg")
const SUPPORT_ICON_MAENGSEON_PATH := "res://assets/ui/support_fleet/support_fleet_maengseon_icon.png"
const SUPPORT_ICON_PANOKSEON_PATH := "res://assets/ui/support_fleet/support_fleet_panokseon_icon.png"
const SUPPORT_ICON_GEOBUKSEON_PATH := "res://assets/ui/support_fleet/support_fleet_geobukseon_icon.png"
const PlayerShipSupportHelper = preload("res://scripts/entities/ships/player_ship_support_helper.gd")
const HudGaugeBar = preload("res://scripts/ui/hud/hud_gauge_bar.gd")
const SUPPORT_SLOT_SIZE_DEFAULT := 66.0
const SUPPORT_SLOT_SIZE_COMPACT := 60.0
const SUPPORT_SLOT_SIZE_DENSE := 54.0
const SUPPORT_SLOT_PANOKSEON_ACCENT := Color(0.86, 0.58, 0.34, 0.96)
const SUPPORT_SLOT_MAENGSEON_ACCENT := Color(0.82, 0.69, 0.42, 0.92)
const SUPPORT_SLOT_EMPTY_BG := Color(0.05, 0.07, 0.10, 0.72)
const SUPPORT_SLOT_ICON_BLEED_RATIO := 0.06
const BOSS_HP_FALLBACK_ID := -1
const BOSS_HP_FILL := Color(0.77, 0.22, 0.20, 0.95)
const BOSS_HP_BG := Color(0.07, 0.08, 0.10, 0.92)
const SHIP_HP_UI_SAFE_PADDING := 10.0
const PLAYER_STATUS_SCREEN_GAP := 8.0
static var _support_icon_cache: Dictionary = {}

# Top-line HUD text
static func update_level(hud, val: int) -> void:
	hud._last_level_value = val
	if hud.level_label:
		if hud._last_xp_max > 0:
			hud.level_label.text = "Lv %d · XP %d/%d" % [val, hud._last_xp_current, hud._last_xp_max]
		else:
			hud.level_label.text = "Lv %d" % val

static func update_score(hud, val: int) -> void:
	if hud.score_label:
		var total_points = SaveManager.gold if is_instance_valid(SaveManager) else val
		hud.score_label.text = "포인트 %d · 총 %d" % [val, total_points]

static func update_combat_stats(hud, ship_sunk: int, ships_derelicted: int, soldiers_killed: int, _soldiers_slain: int, _soldiers_drowned: int) -> void:
	var destroyed_ships: int = ship_sunk + ships_derelicted
	var text = "배 %d | 병 %d" % [destroyed_ships, soldiers_killed]
	if hud._last_combat_stats_text == text:
		return
	hud._last_combat_stats_text = text
	if hud.combat_sunk_value_label:
		hud.combat_sunk_value_label.text = str(destroyed_ships)
	if hud.combat_soldier_value_label:
		hud.combat_soldier_value_label.text = str(soldiers_killed)

static func update_difficulty_ui(hud, val: int) -> void:
	if hud.difficulty_label:
		hud._last_difficulty_text = ""
		hud.difficulty_label.text = ""
		hud.difficulty_label.visible = false

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
	elif speed_state == "furled":
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
		elif speed_state == "furled":
			fill_box.bg_color = Color(0.38, 0.45, 0.50, 0.86)
		else:
			fill_box.bg_color = NavalUiTheme.STATUS_ACTIVE_BLUE

static func _apply_boost_bar_state(hud, active: bool, ready: bool) -> void:
	if not hud.boost_bar:
		return
	var fill = hud.boost_bar.get_theme_stylebox("fill")
	if fill is StyleBoxFlat:
		var fill_box := fill as StyleBoxFlat
		if active:
			fill_box.bg_color = Color(1.0, 0.34, 0.16, 0.96)
		elif ready:
			fill_box.bg_color = Color(0.96, 0.68, 0.24, 0.94)
		else:
			fill_box.bg_color = Color(0.47, 0.36, 0.24, 0.82)

static func _update_boost_bar(hud) -> void:
	if not hud.boost_bar:
		return
	if not is_instance_valid(hud.player_ship) or not hud.player_ship.has_method("get_ramming_boost_charge_ratio"):
		hud.boost_bar.visible = false
		return
	if hud.player_ship.has_method("should_show_ramming_boost_gauge") and not hud.player_ship.call("should_show_ramming_boost_gauge"):
		hud.boost_bar.visible = false
		return
	hud.boost_bar.visible = true
	var boost_ratio: float = clampf(float(hud.player_ship.call("get_ramming_boost_charge_ratio")), 0.0, 1.0)
	var boost_active: bool = hud.player_ship.has_method("is_ramming_boost_active") and hud.player_ship.call("is_ramming_boost_active") == true
	var boost_ready := boost_ratio >= 0.999 and not boost_active
	hud._boost_visual_value = lerpf(hud._boost_visual_value, boost_ratio * 100.0, 0.42)
	if absf(hud.boost_bar.value - hud._boost_visual_value) > 0.1:
		hud.boost_bar.value = hud._boost_visual_value
	if absf(hud._last_boost_ratio - boost_ratio) > 0.005:
		hud._last_boost_ratio = boost_ratio
	if hud._last_boost_ready != boost_ready or hud._last_boost_active != boost_active:
		hud._last_boost_ready = boost_ready
		hud._last_boost_active = boost_active
		_apply_boost_bar_state(hud, boost_active, boost_ready)

static func update_speed_display(hud) -> void:
	if not is_instance_valid(hud.player_ship):
		return
	if hud.player_ship.get("current_speed") == null:
		return
	var speed: float = float(hud.player_ship.current_speed)
	var max_speed: float = 1.0
	if hud.player_ship.get("max_speed") != null:
		max_speed = maxf(float(hud.player_ship.max_speed), 0.01)
	var speed_magnitude := absf(speed)
	var speed_ratio: float = clampf(speed_magnitude / max_speed, 0.0, 1.0)
	var is_rowing_active: bool = hud.player_ship.get("is_rowing") == true
	var is_rowing_locked: bool = hud.player_ship.get("rowing_locked") == true
	var is_sail_furled: bool = hud.player_ship.get("sail_furled") == true
	var speed_state := "exhausted" if (is_rowing_active and is_rowing_locked) else ("locked" if is_rowing_locked else ("rowing" if is_rowing_active else ("furled" if is_sail_furled else "sail")))
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
		_update_boost_bar(hud)
	elif hud.speed_display:
		var speed_text = "%.1f" % speed
		if hud._last_speed_str != speed_text:
			hud._last_speed_str = speed_text
			hud.speed_display.text = speed_text
		_update_boost_bar(hud)

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
	var visible_support_ships := _sort_support_ships_for_hud(support_ships)
	var slot_count: int = support_ships.size()
	_ensure_support_slot_count(hud, slot_count)
	_apply_support_slot_density(hud, slot_count, visible_support_ships)

	for i in range(hud.support_fleet_hud_slots.size()):
		var slot: PanelContainer = hud.support_fleet_hud_slots[i]
		if not is_instance_valid(slot):
			continue
		var ship = visible_support_ships[i] if i < visible_support_ships.size() else null
		var profile_slot_index := i
		if is_instance_valid(ship):
			profile_slot_index = int(ship.get_meta("support_fleet_slot_index", i))
		var slot_profile: Dictionary = PlayerShipSupportHelper.resolve_support_fleet_profile(hud.player_ship, profile_slot_index)
		var timer_text := ""
		_update_support_slot(slot, ship, slot_profile, timer_text)

static func update_crew_count(hud) -> void:
	if Engine.get_process_frames() % 30 != 0:
		return
	if not is_instance_valid(hud.player_ship):
		return
	pass

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
	slot.custom_minimum_size = Vector2(SUPPORT_SLOT_SIZE_DEFAULT, SUPPORT_SLOT_SIZE_DEFAULT)
	slot.add_theme_stylebox_override("panel", NavalUiTheme.make_support_slot_style())

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
	damage_fill.offset_top = -5.0
	damage_fill.offset_bottom = 0.0
	damage_fill.add_theme_stylebox_override("panel", NavalUiTheme.make_support_slot_damage_style())
	root.add_child(damage_fill)

	var dead_overlay := Panel.new()
	dead_overlay.name = "DeadOverlay"
	dead_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dead_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dead_overlay.add_theme_stylebox_override("panel", NavalUiTheme.make_support_slot_dead_style())
	dead_overlay.visible = false
	root.add_child(dead_overlay)

	var emblem_plate := PanelContainer.new()
	emblem_plate.name = "EmblemPlate"
	emblem_plate.anchor_left = 0.0
	emblem_plate.anchor_top = 0.0
	emblem_plate.anchor_right = 1.0
	emblem_plate.anchor_bottom = 1.0
	emblem_plate.offset_left = 0.0
	emblem_plate.offset_top = 0.0
	emblem_plate.offset_right = 0.0
	emblem_plate.offset_bottom = 0.0
	emblem_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	emblem_plate.clip_contents = true
	emblem_plate.add_theme_stylebox_override("panel", NavalUiTheme.make_emblem_plate_style(SUPPORT_SLOT_MAENGSEON_ACCENT, true))
	root.add_child(emblem_plate)

	var ship_icon := TextureRect.new()
	ship_icon.name = "ShipIcon"
	ship_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ship_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	ship_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ship_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	ship_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	emblem_plate.add_child(ship_icon)

	var icon := Label.new()
	icon.name = "Icon"
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	NavalUiTheme.apply_emblem(icon, "fleet_signal", 15, NavalUiTheme.TEXT_ACCENT)
	emblem_plate.add_child(icon)

	var badge := Label.new()
	badge.name = "TypeBadge"
	badge.anchor_left = 1.0
	badge.anchor_top = 0.0
	badge.anchor_right = 1.0
	badge.anchor_bottom = 0.0
	badge.offset_left = -16.0
	badge.offset_top = 2.0
	badge.offset_right = -4.0
	badge.offset_bottom = 14.0
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	NavalUiTheme.style_overlay_caption(badge, 8, NavalUiTheme.TEXT_GOLD, 2)
	badge.visible = false
	root.add_child(badge)

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

static func _apply_support_slot_density(hud, slot_count: int, visible_support_ships: Array = []) -> void:
	var empty_slot_size: float = SUPPORT_SLOT_SIZE_DEFAULT
	if slot_count >= 5:
		empty_slot_size = SUPPORT_SLOT_SIZE_DENSE
	elif slot_count >= 4:
		empty_slot_size = SUPPORT_SLOT_SIZE_COMPACT
	if is_instance_valid(hud.support_row):
		hud.support_row.add_theme_constant_override("separation", 4)
	if is_instance_valid(hud.support_slot_container):
		hud.support_slot_container.add_theme_constant_override("separation", 4 if slot_count >= 5 else 5)
	for slot_index in range(hud.support_fleet_hud_slots.size()):
		var slot: PanelContainer = hud.support_fleet_hud_slots[slot_index]
		if not is_instance_valid(slot):
			continue
		var support_ship = visible_support_ships[slot_index] if slot_index < visible_support_ships.size() else null
		var slot_size: float = _get_support_slot_display_size(support_ship, empty_slot_size)
		slot.custom_minimum_size = Vector2(slot_size, slot_size)
		slot.size = slot.custom_minimum_size
		var slot_style := slot.get_theme_stylebox("panel") as StyleBoxFlat
		if is_instance_valid(slot_style):
			slot_style.set_corner_radius_all(roundi(slot_size * 0.5))
		var emblem_plate := slot.get_node_or_null("Root/EmblemPlate") as PanelContainer
		if is_instance_valid(emblem_plate):
			emblem_plate.offset_left = 0.0
			emblem_plate.offset_top = 0.0
			emblem_plate.offset_right = 0.0
			emblem_plate.offset_bottom = 0.0
		var ship_icon := slot.get_node_or_null("Root/EmblemPlate/ShipIcon") as TextureRect
		if is_instance_valid(ship_icon):
			var icon_bleed := roundf(slot_size * SUPPORT_SLOT_ICON_BLEED_RATIO)
			ship_icon.offset_left = -icon_bleed
			ship_icon.offset_top = -icon_bleed
			ship_icon.offset_right = icon_bleed
			ship_icon.offset_bottom = icon_bleed
		var badge := slot.get_node_or_null("Root/TypeBadge") as Label
		if is_instance_valid(badge):
			badge.offset_left = -roundf(slot_size * 0.34)
			badge.offset_top = 2.0
			badge.offset_right = -4.0
			badge.offset_bottom = roundf(slot_size * 0.28)

static func _sort_support_ships_for_hud(support_ships: Array) -> Array:
	var visible_support_ships: Array = support_ships.duplicate()
	visible_support_ships.sort_custom(func(a, b):
		var rank_a := _get_support_ship_display_rank(a)
		var rank_b := _get_support_ship_display_rank(b)
		if rank_a != rank_b:
			return rank_a < rank_b
		var order_a: int = int(a.get_meta("support_fleet_order", a.get_instance_id())) if is_instance_valid(a) else 0
		var order_b: int = int(b.get_meta("support_fleet_order", b.get_instance_id())) if is_instance_valid(b) else 0
		if order_a != order_b:
			return order_a < order_b
		var slot_a: int = int(a.get_meta("support_fleet_slot_index", order_a)) if is_instance_valid(a) else order_a
		var slot_b: int = int(b.get_meta("support_fleet_slot_index", order_b)) if is_instance_valid(b) else order_b
		return slot_a < slot_b
	)
	return visible_support_ships

static func _get_support_ship_display_rank(ship) -> int:
	var ship_type_name := _get_support_ship_type_name(ship)
	if ship_type_name.contains("geobukseon") or ship_type_name.contains("turtle"):
		return 0
	if ship_type_name.contains("panokseon"):
		return 1
	return 2

static func _get_support_slot_display_size(_ship, fallback_size: float) -> float:
	return fallback_size

static func _get_support_ship_type_name(ship) -> String:
	if is_instance_valid(ship) and ship.get("ship_type") != null:
		return str(ship.get("ship_type")).strip_edges().to_lower()
	return ""

static func _update_support_slot(slot: PanelContainer, ship, slot_profile: Dictionary = {}, timer_text: String = "") -> void:
	var slot_style: StyleBoxFlat = slot.get_theme_stylebox("panel") as StyleBoxFlat
	var damage_fill: Panel = slot.get_node("Root/DamageFill") as Panel
	var dead_overlay: Panel = slot.get_node("Root/DeadOverlay") as Panel
	var emblem_plate: PanelContainer = slot.get_node("Root/EmblemPlate") as PanelContainer
	var emblem_style: StyleBoxFlat = emblem_plate.get_theme_stylebox("panel") as StyleBoxFlat if is_instance_valid(emblem_plate) else null
	var icon: Label = slot.get_node("Root/EmblemPlate/Icon") as Label
	var ship_icon: TextureRect = slot.get_node_or_null("Root/EmblemPlate/ShipIcon") as TextureRect
	var badge: Label = slot.get_node("Root/TypeBadge") as Label
	var timer: Label = slot.get_node("Root/Timer") as Label
	if not is_instance_valid(icon) or not is_instance_valid(dead_overlay) or not is_instance_valid(damage_fill) or not is_instance_valid(timer):
		return
	var visual := _get_support_slot_visual(ship, slot_profile)
	var accent: Color = visual.get("accent", SUPPORT_SLOT_MAENGSEON_ACCENT)
	var bg_color: Color = visual.get("bg", NavalUiTheme.PANEL_BG_DARK)
	var badge_text: String = str(visual.get("badge", ""))
	var badge_color: Color = visual.get("badge_color", accent)
	var emblem_token: String = str(visual.get("emblem", "fleet_signal"))
	var emblem_color: Color = visual.get("emblem_color", NavalUiTheme.TEXT_ACCENT)
	var icon_texture: Texture2D = visual.get("icon_texture", null) as Texture2D
	var slot_size_px: float = slot.custom_minimum_size.x if slot.custom_minimum_size.x > 0.0 else SUPPORT_SLOT_SIZE_DEFAULT
	var emblem_font_size := 15
	if slot_size_px <= SUPPORT_SLOT_SIZE_DENSE + 0.5:
		emblem_font_size = 13
	elif slot_size_px <= SUPPORT_SLOT_SIZE_COMPACT + 0.5:
		emblem_font_size = 14
	if is_instance_valid(badge):
		badge.visible = not badge_text.is_empty()
		badge.text = badge_text
		NavalUiTheme.style_overlay_caption(badge, 8, badge_color, 2)
	NavalUiTheme.apply_emblem(icon, emblem_token, emblem_font_size, emblem_color)
	if is_instance_valid(ship_icon):
		ship_icon.texture = icon_texture
		ship_icon.visible = icon_texture != null
		ship_icon.modulate = Color(1.0, 1.0, 1.0, 1.0)
	if is_instance_valid(emblem_style):
		if icon_texture != null:
			emblem_style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
			emblem_style.border_color = Color(accent.r, accent.g, accent.b, 0.0)
		else:
			emblem_style.bg_color = Color(accent.r, accent.g, accent.b, 0.08)
			emblem_style.border_color = accent.lerp(NavalUiTheme.BORDER_GOLD_SOFT, 0.18)
	if is_instance_valid(ship) and ship.get("hull_hp") != null and ship.get("max_hull_hp") != null:
		var hull_hp: float = maxf(0.0, float(ship.get("hull_hp")))
		var max_hull_hp: float = maxf(float(ship.get("max_hull_hp")), 1.0)
		var hull_ratio: float = clampf(hull_hp / max_hull_hp, 0.0, 1.0)
		damage_fill.visible = true
		damage_fill.anchor_right = hull_ratio
		var damage_style := damage_fill.get_theme_stylebox("panel") as StyleBoxFlat
		if is_instance_valid(damage_style):
			damage_style.bg_color = NavalUiTheme.STATUS_DANGER.lerp(NavalUiTheme.STATUS_GOOD, hull_ratio)
		dead_overlay.visible = false
		icon.visible = icon_texture == null
		timer.visible = false
		timer.text = ""
		if slot_style:
			slot_style.bg_color = bg_color
			slot_style.border_color = accent
	else:
		damage_fill.visible = false
		damage_fill.anchor_right = 1.0
		dead_overlay.visible = true
		icon.visible = icon_texture == null
		NavalUiTheme.apply_emblem(icon, emblem_token, emblem_font_size, Color(0.62, 0.66, 0.72, 0.82))
		if is_instance_valid(ship_icon) and icon_texture != null:
			ship_icon.modulate = Color(0.58, 0.62, 0.68, 0.78)
		timer.visible = not timer_text.is_empty()
		timer.text = timer_text
		if slot_style:
			slot_style.bg_color = SUPPORT_SLOT_EMPTY_BG
			slot_style.border_color = accent.lerp(NavalUiTheme.STATUS_DEAD, 0.45)
		if is_instance_valid(emblem_style):
			emblem_style.bg_color = Color(0.08, 0.08, 0.09, 0.42)
			emblem_style.border_color = accent.lerp(NavalUiTheme.STATUS_DEAD, 0.35)

static func _get_support_slot_visual(ship, slot_profile: Dictionary = {}) -> Dictionary:
	var ship_type_name := ""
	if is_instance_valid(ship) and ship.get("ship_type") != null:
		ship_type_name = str(ship.get("ship_type")).strip_edges().to_lower()
	if ship_type_name.is_empty():
		ship_type_name = str(slot_profile.get("ship_type", "maengseon_ally")).strip_edges().to_lower()
	var is_panokseon := ship_type_name.contains("panokseon")
	var is_geobukseon := ship_type_name.contains("geobukseon") or ship_type_name.contains("turtle")
	var icon_path := SUPPORT_ICON_MAENGSEON_PATH
	if is_geobukseon:
		icon_path = SUPPORT_ICON_GEOBUKSEON_PATH
	elif is_panokseon:
		icon_path = SUPPORT_ICON_PANOKSEON_PATH
	return {
		"accent": SUPPORT_SLOT_PANOKSEON_ACCENT if is_panokseon else SUPPORT_SLOT_MAENGSEON_ACCENT,
		"bg": Color(0.09, 0.07, 0.06, 0.92) if is_panokseon else NavalUiTheme.PANEL_BG_DARK,
		"emblem": "fort" if is_panokseon else "fleet_signal",
		"emblem_color": NavalUiTheme.TEXT_ACCENT if is_panokseon else NavalUiTheme.TEXT_MAIN,
		"icon_texture": _get_support_icon_texture(icon_path),
		"badge": "포" if is_panokseon else "",
		"badge_color": NavalUiTheme.TEXT_ACCENT if is_panokseon else NavalUiTheme.TEXT_GOLD,
	}

static func _get_support_icon_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _support_icon_cache.has(path):
		return _support_icon_cache[path] as Texture2D
	var imported_texture := load(path) as Texture2D
	if imported_texture != null:
		_support_icon_cache[path] = imported_texture
		return imported_texture
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		_support_icon_cache[path] = null
		return null
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	_support_icon_cache[path] = texture
	return texture

static func update_hull_display(hud) -> void:
	if is_instance_valid(hud.player_ship) and hud.player_ship.get("hull_hp") != null:
		hud.update_hull_hp(hud.player_ship.hull_hp, hud.player_ship.max_hull_hp)

static func update_stamina_display(hud) -> void:
	if is_instance_valid(hud.player_ship) and hud.player_ship.get("rowing_stamina") != null:
		var max_stamina: float = 100.0
		if hud.player_ship.get("max_rowing_stamina") != null:
			max_stamina = float(hud.player_ship.max_rowing_stamina)
		hud.update_stamina(hud.player_ship.rowing_stamina, max_stamina)

static func update_player_status_overlay(hud, _positions_only: bool = false) -> void:
	if not is_instance_valid(hud.player_status_root):
		return
	if not is_instance_valid(hud.player_ship) or not hud.player_ship.is_inside_tree():
		hud.player_status_root.visible = false
		return
	var cam: Camera3D = hud.get_viewport().get_camera_3d()
	if not is_instance_valid(cam):
		hud.player_status_root.visible = false
		return
	if hud.player_ship.get("is_sinking") == true or hud.player_ship.get("is_dying") == true:
		hud.player_status_root.visible = false
		return
	var viewport_rect: Rect2 = hud.get_viewport().get_visible_rect()
	var root_size: Vector2 = hud.player_status_root.size
	if root_size.x <= 0.0 or root_size.y <= 0.0:
		root_size = hud.player_status_root.custom_minimum_size
	var screen_bottom := _get_player_ship_screen_bottom(hud.player_ship, cam)
	if screen_bottom == Vector2.INF:
		hud.player_status_root.visible = false
		return
	var target_pos := screen_bottom + Vector2(-root_size.x * 0.5, PLAYER_STATUS_SCREEN_GAP)
	var margin := 8.0
	target_pos.x = clampf(target_pos.x, margin, maxf(margin, viewport_rect.size.x - root_size.x - margin))
	target_pos.y = clampf(target_pos.y, margin, maxf(margin, viewport_rect.size.y - root_size.y - margin))
	hud.player_status_root.position = target_pos
	hud.player_status_root.visible = true

static func _get_player_ship_screen_bottom(player_ship: Node3D, cam: Camera3D) -> Vector2:
	var deck_half := Vector2(1.5, 4.0)
	if player_ship.has_method("get_deck_half_extents"):
		var extents = player_ship.call("get_deck_half_extents")
		if extents is Vector2:
			deck_half = extents as Vector2
	elif player_ship.has_method("get_collision_half_extents"):
		var collision_extents = player_ship.call("get_collision_half_extents")
		if collision_extents is Vector2:
			deck_half = collision_extents as Vector2
	var deck_height: float = 0.5
	if player_ship.get("deck_height") != null:
		deck_height = float(player_ship.get("deck_height"))
	var local_y_values := [0.0, maxf(0.1, deck_height * 0.35)]
	var local_x_values := [-deck_half.x, 0.0, deck_half.x]
	var local_z_values := [-deck_half.y, 0.0, deck_half.y]
	var min_x := INF
	var max_x := -INF
	var max_y := -INF
	var projected_count := 0
	for local_y in local_y_values:
		for local_x in local_x_values:
			for local_z in local_z_values:
				var world_pos := player_ship.to_global(Vector3(local_x, local_y, local_z))
				if cam.is_position_behind(world_pos):
					continue
				var screen_pos := cam.unproject_position(world_pos)
				min_x = minf(min_x, screen_pos.x)
				max_x = maxf(max_x, screen_pos.x)
				max_y = maxf(max_y, screen_pos.y)
				projected_count += 1
	if projected_count <= 0:
		return Vector2.INF
	return Vector2((min_x + max_x) * 0.5, max_y)

static func update_boarding_display(hud) -> void:
	if not hud.boarding_ui or not is_instance_valid(hud.player_ship):
		return
	var is_boarding = hud.player_ship.get("is_boarding") == true
	var prep_timer = hud.player_ship.get("boarding_prep_timer") if "boarding_prep_timer" in hud.player_ship else 0.0
	var prep_duration = hud.player_ship.get("boarding_prep_duration") if "boarding_prep_duration" in hud.player_ship else 2.5
	var boarding_target: Node3D = hud.player_ship.get("boarding_target") if "boarding_target" in hud.player_ship else null
	var target_friendly_count: int = 0
	var target_hostile_count: int = 0
	var target_overrun: bool = false
	var target_name: String = _get_short_ship_name(boarding_target)
	var target_capture_ratio: float = 0.0
	var target_capture_remaining: float = 0.0
	if is_instance_valid(boarding_target):
		target_friendly_count = int(boarding_target.get("deck_friendly_crew_count")) if boarding_target.get("deck_friendly_crew_count") != null else 0
		target_hostile_count = int(boarding_target.get("deck_hostile_boarder_count")) if boarding_target.get("deck_hostile_boarder_count") != null else 0
		target_overrun = boarding_target.get("deck_is_overrun") == true
		target_capture_ratio = _get_boarding_capture_ratio(boarding_target)
		target_capture_remaining = _get_boarding_capture_remaining(boarding_target)
	if is_boarding:
		hud.boarding_ui.visible = true
		var target_suffix := " [%s]" % target_name if not target_name.is_empty() else ""
		if prep_timer < prep_duration:
			hud.boarding_label.text = "도선 준비 중%s  승조 %d | 월선 %d" % [target_suffix, target_friendly_count, target_hostile_count]
			hud.boarding_bar.value = (prep_timer / prep_duration) * 100
			_set_boarding_bar_fill(hud, Color(1.0, 1.0, 1.0, 0.7))
		else:
			if target_overrun:
				hud.boarding_label.text = "갑판 장악 중%s  승조 %d | 월선 %d | %.1f초" % [
					target_suffix,
					target_friendly_count,
					target_hostile_count,
					target_capture_remaining
				]
				hud.boarding_bar.value = target_capture_ratio * 100.0
			else:
				hud.boarding_label.text = "도선 진행 중%s  승조 %d | 월선 %d" % [
					target_suffix,
					target_friendly_count,
					target_hostile_count
				]
				hud.boarding_bar.value = 100
			_set_boarding_bar_fill(hud, NavalUiTheme.STATUS_WARN if target_overrun else NavalUiTheme.STATUS_ACTIVE_BLUE)
	else:
		hud.boarding_ui.visible = false


static func _set_boarding_bar_fill(hud, color: Color) -> void:
	if not is_instance_valid(hud.boarding_bar):
		return
	var fill := hud.boarding_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill:
		fill.bg_color = color
		hud.boarding_bar.queue_redraw()


static func update_capture_opportunity_display(hud) -> void:
	if not is_instance_valid(hud.capture_opportunity_label):
		return
	hud.capture_opportunity_label.visible = false
	hud.capture_opportunity_label.text = ""
	hud._last_capture_opportunity_text = ""

static func _get_capture_opportunity_text(_player_ship) -> String:
	return ""

static func update_boss_hp(hud, current: float, maximum: float) -> void:
	refresh_boss_hp_display(hud, current, maximum)

static func refresh_boss_hp_display(hud, fallback_current: float = -1.0, fallback_maximum: float = -1.0) -> void:
	if hud == null or not is_instance_valid(hud.boss_hp_container):
		return
	var boss_rows: Array[Dictionary] = _collect_active_boss_hp_rows()
	if boss_rows.is_empty() and fallback_current > 0.0 and fallback_maximum > 0.0:
		boss_rows.append({
			"id": BOSS_HP_FALLBACK_ID,
			"label": "보스",
			"current": fallback_current,
			"maximum": fallback_maximum,
			"tier": 0,
		})
	_sort_boss_hp_rows(boss_rows)

	var active_ids: Dictionary = {}
	var label_counts: Dictionary = {}
	for row in boss_rows:
		var base_label := str(row.get("label", "보스"))
		label_counts[base_label] = int(label_counts.get(base_label, 0)) + 1

	var label_seen: Dictionary = {}
	var show_labels: bool = boss_rows.size() > 0
	for index in range(boss_rows.size()):
		var row: Dictionary = boss_rows[index]
		var boss_id: int = int(row.get("id", BOSS_HP_FALLBACK_ID))
		active_ids[boss_id] = true
		var base_label := str(row.get("label", "보스"))
		label_seen[base_label] = int(label_seen.get(base_label, 0)) + 1
		var display_label := base_label
		if int(label_counts.get(base_label, 0)) > 1:
			display_label = "%s %d" % [base_label, int(label_seen[base_label])]
		var entry: Dictionary = _ensure_boss_hp_entry(hud, boss_id)
		_update_boss_hp_entry(entry, display_label, float(row.get("current", 0.0)), float(row.get("maximum", 1.0)), show_labels)
		var root := entry.get("root", null) as VBoxContainer
		if is_instance_valid(root):
			hud.boss_hp_container.move_child(root, index)

	_cleanup_stale_boss_hp_entries(hud, active_ids)
	var active_count: int = boss_rows.size()
	hud.boss_hp_container.visible = active_count > 0
	if hud.boss_hp_visible_count != active_count:
		hud.boss_hp_visible_count = active_count
		if hud.has_method("_apply_layout_density"):
			hud._apply_layout_density()
	_update_legacy_boss_hp_refs(hud)

static func _collect_active_boss_hp_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var ships: Array = EntityRegistry.get_ships_by_team("enemy")
	for ship in ships:
		if not _is_boss_hp_target_valid(ship):
			continue
		var maximum: float = maxf(float(ship.get("max_hull_hp")), 1.0)
		var current: float = clampf(float(ship.get("hull_hp")), 0.0, maximum)
		rows.append({
			"id": ship.get_instance_id(),
			"label": _get_boss_hp_label(ship),
			"current": current,
			"maximum": maximum,
			"tier": int(ship.get("tier")) if ship.get("tier") != null else 0,
		})
	return rows

static func _is_boss_hp_target_valid(ship) -> bool:
	if not is_instance_valid(ship) or not ship.is_inside_tree():
		return false
	if not ship.is_in_group("boss"):
		return false
	if ship.get("hull_hp") == null or ship.get("max_hull_hp") == null:
		return false
	if ship.get("is_sinking") == true or ship.get("is_dying") == true:
		return false
	var maximum: float = float(ship.get("max_hull_hp"))
	if maximum <= 0.0:
		return false
	return float(ship.get("hull_hp")) > 0.0

static func _get_boss_hp_label(ship) -> String:
	if not is_instance_valid(ship):
		return "보스"
	var tier_value: int = int(ship.get("tier")) if ship.get("tier") != null else 0
	if tier_value >= 2:
		return "대장선"
	var ship_type_name := str(ship.get("ship_type")).strip_edges().to_lower() if ship.get("ship_type") != null else ""
	if ship_type_name.contains("final"):
		return "대장선"
	if ship_type_name.contains("mid") or ship_type_name.contains("atakebune"):
		return "대형 적선"
	return "보스"

static func _sort_boss_hp_rows(rows: Array[Dictionary]) -> void:
	for i in range(rows.size()):
		var best_index := i
		for j in range(i + 1, rows.size()):
			if _boss_hp_row_precedes(rows[j], rows[best_index]):
				best_index = j
		if best_index != i:
			var temp := rows[i]
			rows[i] = rows[best_index]
			rows[best_index] = temp

static func _boss_hp_row_precedes(a: Dictionary, b: Dictionary) -> bool:
	var a_tier := int(a.get("tier", 0))
	var b_tier := int(b.get("tier", 0))
	if a_tier != b_tier:
		return a_tier > b_tier
	return int(a.get("id", 0)) < int(b.get("id", 0))

static func _ensure_boss_hp_entry(hud, boss_id: int) -> Dictionary:
	if hud.boss_hp_entries.has(boss_id):
		var existing: Dictionary = hud.boss_hp_entries[boss_id]
		if is_instance_valid(existing.get("root", null)) and is_instance_valid(existing.get("bar", null)):
			return existing

	var root := VBoxContainer.new()
	root.name = "BossHPRow_%s" % str(boss_id)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.custom_minimum_size = Vector2(560.0, 40.0)
	root.add_theme_constant_override("separation", 2)
	hud.boss_hp_container.add_child(root)

	var label := Label.new()
	label.name = "BossName"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.custom_minimum_size = Vector2(560.0, 24.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.visible = false
	NavalUiTheme.style_caption(label, 13, NavalUiTheme.TEXT_MUTED)
	label.add_theme_color_override("font_outline_color", NavalUiTheme.OUTLINE_DARK)
	label.add_theme_constant_override("outline_size", 2)
	root.add_child(label)

	var bar := HudGaugeBar.new()
	bar.name = "BossHP_%s" % str(boss_id)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.custom_minimum_size = Vector2(560.0, 16.0)
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = 1.0
	bar.show_percentage = false
	NavalUiTheme.apply_progress_bar(bar, BOSS_HP_BG, BOSS_HP_FILL, 3)
	bar.configure_gauge(BOSS_HP_BG, BOSS_HP_FILL, 3, {
		"damage_trail": true,
		"border_color": Color(0.92, 0.44, 0.30, 0.82),
		"segments": 5,
		"shine_strength": 0.24,
		"trail_follow_speed": 2.2,
	})
	root.add_child(bar)

	var entry := {
		"root": root,
		"bar": bar,
		"label": label,
	}
	hud.boss_hp_entries[boss_id] = entry
	return entry

static func _update_boss_hp_entry(entry: Dictionary, label_text: String, current: float, maximum: float, show_label: bool) -> void:
	var bar := entry.get("bar", null) as ProgressBar
	if not is_instance_valid(bar):
		return
	bar.max_value = maxf(maximum, 1.0)
	bar.visible = current > 0.0
	if bar.get_meta("boss_hp_initialized", false) != true:
		bar.value = current
		bar.set_meta("boss_hp_initialized", true)
	else:
		bar.value = lerpf(float(bar.value), current, 0.45)

	var label := entry.get("label", null) as Label
	if is_instance_valid(label):
		label.text = label_text
		label.visible = show_label
	var root := entry.get("root", null) as VBoxContainer
	if is_instance_valid(root):
		root.add_theme_constant_override("separation", 2 if show_label else 0)

static func _cleanup_stale_boss_hp_entries(hud, active_ids: Dictionary) -> void:
	for boss_id in hud.boss_hp_entries.keys():
		if active_ids.has(boss_id):
			continue
		var entry: Dictionary = hud.boss_hp_entries[boss_id]
		var root := entry.get("root", null) as VBoxContainer
		if is_instance_valid(root):
			root.queue_free()
		hud.boss_hp_entries.erase(boss_id)

static func _update_legacy_boss_hp_refs(hud) -> void:
	hud.boss_hp_bar_new = null
	hud.boss_hp_text_label = null
	for entry in hud.boss_hp_entries.values():
		if not (entry is Dictionary):
			continue
		var bar := (entry as Dictionary).get("bar", null) as ProgressBar
		if not is_instance_valid(bar):
			continue
		hud.boss_hp_bar_new = bar
		hud.boss_hp_text_label = (entry as Dictionary).get("label", null) as Label
		return

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
		if ship == hud.player_ship:
			continue
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
	if ship.is_in_group("boss"):
		return false
	if ship.get("is_sinking") == true or ship.get("is_dying") == true:
		return false
	var max_hp: float = float(ship.get("max_hull_hp"))
	if max_hp <= 0.0:
		return false
	var current_hp: float = clampf(float(ship.get("hull_hp")), 0.0, max_hp)
	return current_hp > 0.0 and _should_show_ship_hp_bar(ship, current_hp, max_hp)

static func _should_show_ship_hp_bar(ship, current_hp: float, max_hp: float) -> bool:
	if not is_instance_valid(ship):
		return false
	if ship.get("deck_is_contested") == true or ship.get("deck_is_overrun") == true:
		return true
	var hostile_count: int = int(ship.get("deck_hostile_boarder_count")) if ship.get("deck_hostile_boarder_count") != null else 0
	if hostile_count > 0:
		return true
	var damage_threshold: float = maxf(1.0, max_hp * 0.01)
	return current_hp < max_hp - damage_threshold

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
	if _ship_hp_bar_overlaps_reserved_hud(hud, Rect2(bar_root.position, bar_root.size)):
		bar_root.visible = false
		return true
	var hp_bar: ProgressBar = bar_root.get_node("Bar") as ProgressBar
	var boarding_label: Label = bar_root.get_node("Boarding") as Label
	var state_label: Label = bar_root.get_node("State") as Label
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
	var bg_style: StyleBoxFlat = hp_bar.get_theme_stylebox("background") as StyleBoxFlat
	if is_instance_valid(bg_style):
		if ship.get("deck_is_overrun") == true:
			bg_style.border_color = Color(1.0, 0.78, 0.28, 0.98)
			bg_style.bg_color = Color(0.14, 0.08, 0.02, 0.84)
		elif ship.get("deck_is_contested") == true:
			bg_style.border_color = Color(1.0, 0.90, 0.48, 0.96)
			bg_style.bg_color = Color(0.11, 0.08, 0.03, 0.78)
		else:
			bg_style.border_color = NavalUiTheme.STATUS_ACTIVE_BLUE if team_tag == "player" else Color(1.0, 0.42, 0.42, 0.95)
			bg_style.bg_color = Color(0.03, 0.04, 0.06, 0.72)
	if is_instance_valid(boarding_label):
		var friendly_count: int = int(ship.get("deck_friendly_crew_count")) if ship.get("deck_friendly_crew_count") != null else 0
		var hostile_count: int = int(ship.get("deck_hostile_boarder_count")) if ship.get("deck_hostile_boarder_count") != null else 0
		var is_contested: bool = ship.get("deck_is_contested") == true
		var is_overrun: bool = ship.get("deck_is_overrun") == true
		if hostile_count > 0 or is_contested:
			var capture_suffix: String = ""
			if is_overrun:
				capture_suffix = " | %s" % _get_boarding_capture_short_text(ship, "위기" if team_tag == "player" else "장악")
			if team_tag == "player":
				boarding_label.text = "갑판 %d | 적 %d%s" % [friendly_count, hostile_count, capture_suffix]
				boarding_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.56, 1.0) if is_overrun else Color(1.0, 0.88, 0.62, 1.0))
			else:
				boarding_label.text = "승조 %d | 월선 %d%s" % [friendly_count, hostile_count, capture_suffix]
				boarding_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.46, 1.0) if is_overrun else Color(1.0, 0.80, 0.64, 1.0))
			boarding_label.visible = true
		else:
			boarding_label.visible = false
	if is_instance_valid(state_label):
		var is_contested_state: bool = ship.get("deck_is_contested") == true
		var is_overrun_state: bool = ship.get("deck_is_overrun") == true
		if is_overrun_state:
			state_label.text = _get_boarding_capture_short_text(ship, "장악" if team_tag != "player" else "위기")
			state_label.add_theme_color_override("font_color", Color(1.0, 0.80, 0.32, 1.0))
			state_label.visible = true
		elif is_contested_state:
			state_label.text = "교전"
			state_label.add_theme_color_override("font_color", Color(1.0, 0.90, 0.58, 1.0))
			state_label.visible = true
		else:
			state_label.visible = false
	return true

static func _get_boarding_capture_short_text(ship, label: String) -> String:
	var ratio: float = _get_boarding_capture_ratio(ship)
	return "%s %d%%" % [label, int(round(ratio * 100.0))]

static func _get_boarding_capture_ratio(ship) -> float:
	var duration: float = _get_boarding_capture_duration(ship)
	if duration <= 0.01:
		return 0.0
	var progress: float = 0.0
	if is_instance_valid(ship) and ship.get("boarding_capture_progress") != null:
		progress = float(ship.get("boarding_capture_progress"))
	return clampf(progress / duration, 0.0, 1.0)

static func _get_boarding_capture_remaining(ship) -> float:
	var duration: float = _get_boarding_capture_duration(ship)
	var progress: float = 0.0
	if is_instance_valid(ship) and ship.get("boarding_capture_progress") != null:
		progress = float(ship.get("boarding_capture_progress"))
	return maxf(0.0, duration - progress)

static func _get_boarding_capture_duration(ship) -> float:
	if not is_instance_valid(ship):
		return 0.0
	var duration: float = 0.0
	if ship.get("boarding_capture_duration") != null:
		duration = float(ship.get("boarding_capture_duration"))
	if ship.has_method("get_effective_boarding_capture_duration"):
		var attacker_ship: Node = null
		if ship.has_method("get_boarding_attacker_ship"):
			attacker_ship = ship.call("get_boarding_attacker_ship")
		duration = float(ship.call("get_effective_boarding_capture_duration", attacker_ship))
	return maxf(duration, 0.01)

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
	bar_root.custom_minimum_size = Vector2(hud.SHIP_HP_BAR_WIDTH, hud.SHIP_HP_BAR_HEIGHT + 30.0)
	bar_root.size = bar_root.custom_minimum_size
	bar_root.z_index = 0
	hud.ship_hp_overlay.add_child(bar_root)

	var state_label := Label.new()
	state_label.name = "State"
	state_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	state_label.position = Vector2(0.0, 0.0)
	state_label.custom_minimum_size = Vector2(hud.SHIP_HP_BAR_WIDTH, 14.0)
	state_label.size = state_label.custom_minimum_size
	state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	NavalUiTheme.style_overlay_caption(state_label, 10, NavalUiTheme.TEXT_MAIN, 2)
	state_label.visible = false
	bar_root.add_child(state_label)

	var boarding_label := Label.new()
	boarding_label.name = "Boarding"
	boarding_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boarding_label.position = Vector2(0.0, 14.0)
	boarding_label.custom_minimum_size = Vector2(hud.SHIP_HP_BAR_WIDTH, 14.0)
	boarding_label.size = boarding_label.custom_minimum_size
	boarding_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boarding_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	NavalUiTheme.style_overlay_caption(boarding_label, 10, NavalUiTheme.TEXT_MAIN, 2)
	boarding_label.visible = false
	bar_root.add_child(boarding_label)

	var hp_bar: ProgressBar = HudGaugeBar.new()
	hp_bar.name = "Bar"
	hp_bar.show_percentage = false
	hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_bar.custom_minimum_size = Vector2(hud.SHIP_HP_BAR_WIDTH, hud.SHIP_HP_BAR_HEIGHT)
	hp_bar.size = hp_bar.custom_minimum_size
	hp_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	hp_bar.position = Vector2(0.0, 28.0)
	bar_root.add_child(hp_bar)

	var accent := NavalUiTheme.STATUS_ACTIVE_BLUE if team_tag == "player" else Color(1.0, 0.42, 0.42, 0.95)
	if hp_bar.has_method("configure_gauge"):
		hp_bar.configure_gauge(Color(0.03, 0.04, 0.06, 0.66), NavalUiTheme.STATUS_GOOD, 2, {
			"damage_trail": true,
			"border_color": accent,
			"shine_strength": 0.08,
			"trail_follow_speed": 3.4,
		})
	else:
		hp_bar.add_theme_stylebox_override("background", NavalUiTheme.make_ship_hp_bar_background_style(accent))
		hp_bar.add_theme_stylebox_override("fill", NavalUiTheme.make_ship_hp_bar_fill_style())

	hud.ship_hp_bars[ship_id] = bar_root
	return bar_root

static func _ship_hp_bar_overlaps_reserved_hud(hud, rect: Rect2) -> bool:
	var reserved_controls: Array = [
		hud.top_left_container,
		hud.top_right_container,
		hud.bottom_left_container,
		hud.bottom_right_container,
		hud.boss_hp_container,
	]
	for control in reserved_controls:
		if not is_instance_valid(control) or not control.visible:
			continue
		var reserved_rect: Rect2 = control.get_global_rect().grow(SHIP_HP_UI_SAFE_PADDING)
		if reserved_rect.intersects(rect, true):
			return true
	return false


static func _get_short_ship_name(ship) -> String:
	if not is_instance_valid(ship):
		return ""
	if ship.get("ship_type") != null:
		var ship_type: String = str(ship.get("ship_type"))
		if not ship_type.is_empty():
			return ship_type.capitalize()
	return ship.name if ship.name != null else ""
