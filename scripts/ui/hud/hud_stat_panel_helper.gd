extends RefCounted

const PLAYER_CANNON_BASE_DAMAGE := 22.0
const PLAYER_SAIL_TURN_SPEED := 60.0
const SITE_BONUS_TOTALS_META := "sea_site_bonus_totals"
const SITE_BONUS_COUNTS_META := "sea_site_bonus_counts"
const SITE_BONUS_DATA_PATH := "res://data/sea_site_rewards.json"
const SITE_BONUS_ICON_BY_ID := {
	"cannon_damage_pct": "sports_baseball",
	"cannon_reload_pct": "timer",
	"crew_damage_pct": "swords",
	"crew_defense_add": "health_and_safety",
	"hull_regen_add": "construction",
	"hull_defense_add": "shield",
	"max_hull_add": "favorite",
}

static func process_stat_panel(hud, delta: float) -> void:
	if not hud.show_stat_panel:
		return
	hud._stat_refresh_left -= delta
	if hud._stat_refresh_left <= 0.0:
		hud._stat_refresh_left = hud.stat_refresh_interval
		update_stat_panel(hud)


static func toggle_stat_panel(hud) -> void:
	hud.show_stat_panel = not hud.show_stat_panel
	if hud.show_stat_panel:
		_set_stat_modal_active(hud, true)
		hud._tooltip_hover_slot = null
		hud._tooltip_slot_ref = null
		hud._tooltip_hover_elapsed = 0.0
		hud._hide_upgrade_tooltip(true)
	else:
		_set_stat_modal_active(hud, false)
	hud._stat_refresh_left = 0.0
	update_stat_panel(hud)


static func update_stat_panel(hud) -> void:
	if not is_instance_valid(hud.stat_panel):
		return
	hud.stat_panel.visible = hud.show_stat_panel
	if is_instance_valid(hud.stat_site_bonus_panel):
		hud.stat_site_bonus_panel.visible = hud.show_stat_panel
	if not hud.show_stat_panel:
		_set_stat_modal_active(hud, false)
		return
	if not is_instance_valid(hud.stat_content):
		return
	var sections: Array[Dictionary] = build_stat_sections(hud)
	var site_bonus_sections: Array[Dictionary] = build_site_bonus_sections(hud)
	var site_bonus_has_rows: bool = _sections_have_rows(site_bonus_sections)
	if is_instance_valid(hud.stat_site_bonus_panel):
		hud.stat_site_bonus_panel.visible = hud.show_stat_panel and site_bonus_has_rows
	var columns: int = _get_detail_column_count(hud)
	var signature: String = "%s||site:%s||cols:%d" % [_build_signature(sections), _build_signature(site_bonus_sections), columns]
	if hud._last_stat_signature == signature:
		return
	hud._last_stat_signature = signature
	_rebuild_stat_content(hud, sections)
	_rebuild_site_bonus_content(hud, site_bonus_sections)


static func _set_stat_modal_active(hud, active: bool) -> void:
	if hud == null:
		return
	if active:
		var tree: SceneTree = hud.get_tree() as SceneTree
		if not hud._stat_modal_active:
			hud._stat_modal_previous_layer = int(hud.layer)
			hud._stat_modal_active = true
			if tree != null:
				hud._stat_modal_previous_paused = tree.paused
				tree.paused = true
		if "layer" in hud:
			hud.layer = maxi(int(hud.layer), 20)
		if tree != null:
			tree.paused = true
		if is_instance_valid(hud.stat_backdrop):
			hud.stat_backdrop.visible = true
			hud.stat_backdrop.modulate.a = 1.0
		return

	if is_instance_valid(hud.stat_backdrop):
		hud.stat_backdrop.visible = false
	if not hud._stat_modal_active:
		return
	if "layer" in hud:
		hud.layer = hud._stat_modal_previous_layer
	var restore_tree: SceneTree = hud.get_tree() as SceneTree
	if restore_tree != null:
		restore_tree.paused = hud._stat_modal_previous_paused
	hud._stat_modal_active = false

static func build_stat_sections(hud) -> Array[Dictionary]:
	if not is_instance_valid(hud.player_ship):
		return [{
			"title": "전투 수치",
			"icon": "analytics",
			"rows": [
				{"icon": "hourglass_empty", "label": "상태", "value": "플레이어 함선 로딩 중..."},
			],
		}]

	var ship = hud.player_ship
	var sections: Array[Dictionary] = []
	var lm: Node = hud._cached_level_manager
	if not is_instance_valid(lm):
		lm = LevelManagerRegistry.get_level_manager(hud.get_tree())

	var combat_record_section: Dictionary = {}
	if is_instance_valid(lm):
		combat_record_section = {
			"title": "전과",
			"icon": "analytics",
			"rows": [
				{"icon": "directions_boat", "label": "격침", "value": str(int(lm.get("ships_sunk")))},
				{"icon": "sailing", "label": "나포(폐선화)", "value": str(int(lm.get("ships_derelicted")))},
				{"icon": "groups", "label": "병사 처치", "value": str(int(lm.get("soldiers_killed")))},
				{"icon": "swords", "label": "전투 사살", "value": str(int(lm.get("soldiers_slain")))},
				{"icon": "water", "label": "수장", "value": str(int(lm.get("soldiers_drowned")))},
			],
		}

	var ship_snapshot: Dictionary = ship.call("get_debug_ship_state_snapshot") if ship.has_method("get_debug_ship_state_snapshot") else {}
	var hull_hp: float = float(ship_snapshot.get("hull_hp", 0.0))
	var max_hull_hp: float = float(ship_snapshot.get("max_hull_hp", 0.0))
	var hull_defense: float = float(ship_snapshot.get("hull_defense", 0.0))

	var current_speed: float = float(ship_snapshot.get("current_speed", 0.0))
	var max_speed: float = float(ship_snapshot.get("max_speed", 0.0))
	var sail_efficiency_mult: float = _get_float(ship, "sail_efficiency_mult", 1.0)
	var sail_turn_speed: float = _get_float(ship, "sail_turn_speed", PLAYER_SAIL_TURN_SPEED)
	var rowing_speed: float = _get_float(ship, "rowing_speed", 0.0)
	var rowing_acceleration_mult: float = _get_float(ship, "rowing_acceleration_mult", 1.0)
	var max_rowing_stamina: float = float(ship_snapshot.get("max_rowing_stamina", 100.0))
	var rudder_turn_speed: float = _get_float(ship, "rudder_turn_speed", 0.0)
	var rowing_stamina: float = float(ship_snapshot.get("rowing_stamina", 0.0))
	var stamina_drain_rate: float = _get_float(ship, "stamina_drain_rate", 0.0)
	var stamina_recovery_rate: float = _get_float(ship, "stamina_recovery_rate", 0.0)
	sections.append({
		"title": "항해",
		"icon": "air",
		"rows": [
			{"icon": "speed", "label": "현재 / 최고", "value": "%.1f / %.1f" % [current_speed, max_speed]},
			{"icon": "air", "label": "돛 효율", "value": "x%.2f" % sail_efficiency_mult},
			{"icon": "sync_alt", "label": "돛 회전", "value": "%.0f°/s" % sail_turn_speed},
			{"icon": "rowing", "label": "노젓기 속도", "value": "%.1f" % rowing_speed},
			{"icon": "offline_bolt", "label": "노 가속", "value": "+%d%%" % max(0, int(round((rowing_acceleration_mult - 1.0) * 100.0)))},
			{"icon": "turn_right", "label": "러더 선회", "value": "%.0f°/s" % rudder_turn_speed},
			{"icon": "bolt", "label": "스태미나", "value": "%.0f / %.0f" % [rowing_stamina, max_rowing_stamina]},
			{"icon": "trending_down", "label": "소모 / 회복", "value": "%.1f/s / %.1f/s" % [stamina_drain_rate, stamina_recovery_rate]},
		],
	})

	var cannon_count: int = 0
	var cannon_base_damage: float = 0.0
	var cannon_damage_mult: float = 1.0
	var cannon_damage: float = 0.0
	var cannon_range: float = 0.0
	var cannon_cooldown: float = 0.0
	var cannon_crit_chance: float = 0.0
	var cannon_crit_multiplier: float = 1.0
	var cannon_expected_dps: float = 0.0
	var cannon_fleet_damage_mult: float = 1.0
	var cannon_damage_site_bonus: float = 0.0
	var cannon_snapshot: Dictionary = {}
	var primary_cannon: Node = _get_primary_cannon(ship)
	if is_instance_valid(primary_cannon):
		var cannons_node := NodeContractHelper.get_cannons_container(ship)
		if is_instance_valid(cannons_node):
			for child in cannons_node.get_children():
				if is_instance_valid(child):
					cannon_count += 1
		cannon_snapshot = primary_cannon.call("get_debug_cannon_snapshot") if primary_cannon.has_method("get_debug_cannon_snapshot") else {}
		cannon_range = float(cannon_snapshot.get("range", 0.0))
		cannon_cooldown = float(cannon_snapshot.get("cooldown", 0.0))
		cannon_base_damage = float(cannon_snapshot.get("base_damage", 0.0))
		cannon_damage = float(cannon_snapshot.get("damage", 0.0))
		cannon_damage_mult = float(cannon_snapshot.get("damage_mult", 1.0))
		cannon_fleet_damage_mult = float(cannon_snapshot.get("fleet_damage_mult", 1.0))
		cannon_damage_site_bonus = float(cannon_snapshot.get("site_damage_bonus", 0.0))
		cannon_crit_chance = float(cannon_snapshot.get("crit_chance", 0.0))
		cannon_crit_multiplier = float(cannon_snapshot.get("crit_multiplier", 1.0))
		cannon_expected_dps = float(cannon_snapshot.get("expected_dps", 0.0))
	sections.append({
		"title": "대포",
		"icon": "sports_baseball",
		"rows": [
			{"icon": "apps", "label": "포문 수", "value": str(cannon_count)},
			{
				"icon": "adjust",
				"label": "기본 / 최종",
				"value": "%.1f / %.1f" % [cannon_base_damage, cannon_damage],
				"tooltip": _build_cannon_damage_tooltip(cannon_base_damage, cannon_damage, cannon_damage_mult, cannon_fleet_damage_mult, cannon_damage_site_bonus),
			},
			{
				"icon": "network_node",
				"label": "데미지 배율",
				"value": "x%.2f" % cannon_damage_mult,
				"tooltip": _build_cannon_damage_mult_tooltip(cannon_damage_mult, cannon_damage_site_bonus),
			},
			{"icon": "radar", "label": "사거리", "value": "%.1fm" % cannon_range},
			{
				"icon": "timer",
				"label": "재장전",
				"value": "%.2fs" % cannon_cooldown,
				"tooltip": _build_cannon_reload_tooltip(cannon_snapshot),
			},
			{"icon": "grade", "label": "치명타", "value": "%.1f%% x%.1f" % [cannon_crit_chance * 100.0, cannon_crit_multiplier]},
			{"icon": "monitoring", "label": "DPS (1문)", "value": "%.1f" % cannon_expected_dps},
		],
	})

	var crew_stats: Dictionary = ship.call("get_debug_crew_snapshot") if ship.has_method("get_debug_crew_snapshot") else _collect_crew_stats(ship)
	var crew_damage_site_bonus: float = _get_site_bonus_total(ship, "crew_damage_pct")
	var crew_defense_site_bonus: float = _get_site_bonus_total(ship, "crew_defense_add")
	sections.append({
		"title": "병사",
		"icon": "groups",
		"rows": [
			{"icon": "group", "label": "생존 / 정원", "value": "%d / %d" % [int(crew_stats.get("alive_count", 0)), int(_get_int(ship, "max_crew_count", 0))]},
			{"icon": "schedule", "label": "보충 시간", "value": "%.1fs" % _get_float(ship, "crew_respawn_interval", 0.0)},
			{"icon": "badge", "label": "편성", "value": "일%d 화%d 연%d" % [
				int(crew_stats.get("general_count", 0)),
				int(crew_stats.get("fire_pot_count", 0)),
				int(crew_stats.get("repeater_count", 0)),
			]},
			{"icon": "rocket_launch", "label": "신기전", "value": _get_singigeon_proc_value(hud)},
			{"icon": "health_and_safety", "label": "대표 병사 HP / 방어", "value": "%.0f / %.1f" % [
				float(crew_stats.get("sample_hp", 0.0)),
				float(crew_stats.get("sample_defense", 0.0)),
			], "tooltip": _build_flat_bonus_tooltip("병사 방어", "병사 방어력", crew_defense_site_bonus)},
			{"icon": "swords", "label": "근접 / 활", "value": "%.1f / %.1f" % [
				float(crew_stats.get("sword_damage", 0.0)),
				float(crew_stats.get("bow_damage", 0.0)),
			], "tooltip": _build_percent_bonus_tooltip("병사 무기", "병사 무기 피해", crew_damage_site_bonus, "창 피해 = 기본 창 피해 x (1 + 창병 업그레이드 + 해역 병사 무기)\n활 피해 = 기본 활 피해 x (1 + 해역 병사 무기)")},
			{"icon": "grade", "label": "치명타", "value": "%.0f%% x%.1f" % [
				float(crew_stats.get("crit_chance", 0.0)) * 100.0,
				float(crew_stats.get("crit_multiplier", 1.0)),
			]},
		],
	})

	sections.insert(0, {
		"title": "핵심",
		"icon": "monitoring",
		"style": "summary",
		"rows": [
			{"icon": "favorite", "label": "내구 / 방어", "value": "%.0f/%.0f | %.1f" % [hull_hp, max_hull_hp, hull_defense]},
			{"icon": "sports_baseball", "label": "피해 / DPS", "value": "%.1f | %.1f" % [cannon_damage, cannon_expected_dps]},
			{"icon": "groups", "label": "병력", "value": "%d / %d" % [int(crew_stats.get("alive_count", 0)), int(_get_int(ship, "max_crew_count", 0))]},
			{"icon": "speed", "label": "속도", "value": "%.1f / %.1f" % [current_speed, max_speed]},
			{"icon": "bolt", "label": "스태미나", "value": "%.0f / %.0f" % [rowing_stamina, max_rowing_stamina]},
		],
	})

	if not combat_record_section.is_empty():
		sections.append(combat_record_section)

	return sections


static func build_site_bonus_sections(hud) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if is_instance_valid(hud.player_ship):
		rows = _build_site_bonus_rows(hud.player_ship)
	return [{
		"title": "누적 효과",
		"icon": "explore",
		"rows": rows,
	}]

static func _build_signature(sections: Array[Dictionary]) -> String:
	var parts: Array[String] = []
	for section in sections:
		parts.append(str(section.get("title", "")))
		for row in section.get("rows", []):
			if row is Dictionary:
				parts.append("%s=%s" % [str(row.get("label", "")), str(row.get("value", ""))])
				parts.append("tip:%s" % str(row.get("tooltip", "")))
	return "|".join(parts)

static func _rebuild_stat_content(hud, sections: Array[Dictionary]) -> void:
	for child in hud.stat_content.get_children():
		child.queue_free()
	var columns: int = _get_detail_column_count(hud)
	var section_start_index := 0
	if not sections.is_empty() and str(sections[0].get("style", "")) == "summary":
		hud.stat_content.add_child(_create_section(sections[0], hud))
		section_start_index = 1
	var grid := GridContainer.new()
	grid.columns = columns
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 6)
	hud.stat_content.add_child(grid)
	for section_index in range(section_start_index, sections.size()):
		var section: Dictionary = sections[section_index]
		grid.add_child(_create_section(section, hud))


static func _rebuild_site_bonus_content(hud, sections: Array[Dictionary]) -> void:
	if not is_instance_valid(hud.stat_site_bonus_content):
		return
	for child in hud.stat_site_bonus_content.get_children():
		child.queue_free()
	for section in sections:
		var rows: Array = section.get("rows", [])
		if rows.is_empty():
			continue
		hud.stat_site_bonus_content.add_child(_create_section(section, hud))

static func _create_section(section: Dictionary, hud = null) -> Control:
	var section_root := MarginContainer.new()
	section_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section_root.add_theme_constant_override("margin_left", 1)
	section_root.add_theme_constant_override("margin_top", 1)
	section_root.add_theme_constant_override("margin_right", 1)
	section_root.add_theme_constant_override("margin_bottom", 2)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 3)
	section_root.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	vbox.add_child(header)

	var icon_label: Label = _create_icon_label(str(section.get("icon", "analytics")), 12, NavalUiTheme.TEXT_ACCENT)
	header.add_child(icon_label)

	var title := Label.new()
	title.text = str(section.get("title", ""))
	NavalUiTheme.style_heading(title, 11)
	header.add_child(title)

	var separator := ColorRect.new()
	separator.color = NavalUiTheme.BORDER_GOLD_SOFT
	separator.custom_minimum_size.y = 1.0
	vbox.add_child(separator)

	if str(section.get("style", "")) == "summary":
		var summary_row := HBoxContainer.new()
		summary_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		summary_row.add_theme_constant_override("separation", 6)
		vbox.add_child(summary_row)
		var rows: Array = section.get("rows", [])
		for row_index in range(rows.size()):
			var row = rows[row_index]
			if not (row is Dictionary):
				continue
			if row_index > 0:
				var divider := ColorRect.new()
				divider.color = Color(NavalUiTheme.BORDER_GOLD_DIM.r, NavalUiTheme.BORDER_GOLD_DIM.g, NavalUiTheme.BORDER_GOLD_DIM.b, 0.44)
				divider.custom_minimum_size = Vector2(1.0, 28.0)
				summary_row.add_child(divider)
			var cell := VBoxContainer.new()
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cell.add_theme_constant_override("separation", 1)
			_apply_row_tooltip(cell, row, hud)
			summary_row.add_child(cell)

			var label_row := HBoxContainer.new()
			label_row.add_theme_constant_override("separation", 3)
			cell.add_child(label_row)
			label_row.add_child(_create_icon_label(str(row.get("icon", "chevron_right")), 10, NavalUiTheme.TEXT_BLUE))

			var summary_label := Label.new()
			summary_label.text = str(row.get("label", ""))
			summary_label.clip_text = true
			NavalUiTheme.style_muted(summary_label, 9)
			label_row.add_child(summary_label)

			var summary_value := Label.new()
			summary_value.text = str(row.get("value", ""))
			summary_value.clip_text = true
			NavalUiTheme.style_overlay_value(summary_value, 11)
			summary_value.add_theme_constant_override("outline_size", 2)
			cell.add_child(summary_value)
	else:
		for row in section.get("rows", []):
			if row is Dictionary:
				vbox.add_child(_create_stat_row(row, hud))

	return section_root

static func _create_stat_row(row: Dictionary, hud = null) -> Control:
	var row_box := HBoxContainer.new()
	row_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_box.custom_minimum_size.y = 15.0
	row_box.add_theme_constant_override("separation", 4)
	_apply_row_tooltip(row_box, row, hud)

	var icon_label := _create_icon_label(str(row.get("icon", "chevron_right")), 12, NavalUiTheme.TEXT_BLUE)
	_apply_row_tooltip(icon_label, row, hud)
	row_box.add_child(icon_label)

	var label := Label.new()
	label.text = str(row.get("label", ""))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	NavalUiTheme.style_body(label, 10)
	_apply_row_tooltip(label, row, hud)
	row_box.add_child(label)

	var value := Label.new()
	value.text = str(row.get("value", ""))
	value.custom_minimum_size.x = 92.0
	value.size_flags_horizontal = Control.SIZE_SHRINK_END
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.clip_text = true
	NavalUiTheme.style_overlay_value(value, 10)
	value.add_theme_constant_override("outline_size", 2)
	_apply_row_tooltip(value, row, hud)
	row_box.add_child(value)

	return row_box

static func _apply_row_tooltip(control: Control, row: Dictionary, hud = null) -> void:
	if not is_instance_valid(control):
		return
	var tooltip := str(row.get("tooltip", "")).strip_edges()
	if tooltip.is_empty():
		return
	if hud != null and hud.has_method("_bind_text_tooltip_hover"):
		hud.call("_bind_text_tooltip_hover", control, tooltip, NavalUiTheme.TEXT_ACCENT, true)
		return
	control.tooltip_text = tooltip

static func _create_icon_label(icon_name: String, font_size: int, color: Color) -> Label:
	var icon_label := Label.new()
	icon_label.custom_minimum_size = Vector2(15, 15)
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	NavalUiTheme.apply_emblem(icon_label, icon_name, font_size, color)
	return icon_label

static func _get_detail_column_count(hud) -> int:
	var viewport: Viewport = hud.get_viewport()
	if viewport == null:
		return 1
	var viewport_width: float = viewport.get_visible_rect().size.x
	if viewport_width >= 720.0:
		return 2
	return 1

static func _sections_have_rows(sections: Array[Dictionary]) -> bool:
	for section in sections:
		var rows: Array = section.get("rows", [])
		if not rows.is_empty():
			return true
	return false

static func _build_cannon_damage_tooltip(base_damage: float, final_damage: float, damage_mult: float, fleet_damage_mult: float, site_damage_bonus: float) -> String:
	if base_damage <= 0.0001:
		return ""
	var upgrade_bonus := maxf(0.0, damage_mult - 1.0 - site_damage_bonus)
	return "\n".join([
		"대포 최종 피해",
		"기본 포탄 피해: %.1f" % base_damage,
		"철환 업그레이드: %s" % _format_percent(upgrade_bonus),
		"해역 포격 피해: %s" % _format_percent(site_damage_bonus),
		"함대 피해 배율: x%.2f" % fleet_damage_mult,
		"계산: %.1f x (1 + %.2f + %.2f) x %.2f = %.1f" % [
			base_damage,
			upgrade_bonus,
			site_damage_bonus,
			fleet_damage_mult,
			final_damage,
		],
	])


static func _build_cannon_damage_mult_tooltip(damage_mult: float, site_damage_bonus: float) -> String:
	var upgrade_bonus := maxf(0.0, damage_mult - 1.0 - site_damage_bonus)
	return "\n".join([
		"대포 피해 배율",
		"철환 업그레이드: %s" % _format_percent(upgrade_bonus),
		"해역 포격 피해: %s" % _format_percent(site_damage_bonus),
		"합산 배율: x%.2f" % damage_mult,
	])


static func _build_cannon_reload_tooltip(snapshot: Dictionary) -> String:
	if snapshot.is_empty():
		return ""
	var base_cooldown := float(snapshot.get("base_cooldown", 0.0))
	var final_cooldown := float(snapshot.get("cooldown", 0.0))
	if base_cooldown <= 0.0001 or final_cooldown <= 0.0001:
		return ""
	var site_reload_bonus := float(snapshot.get("site_reload_bonus", 0.0))
	var site_reload_factor := maxf(0.55, 1.0 - site_reload_bonus)
	var cached_cooldown_mult := float(snapshot.get("cached_cooldown_mult", 1.0))
	var upgrade_cooldown_mult := cached_cooldown_mult / maxf(site_reload_factor, 0.001)
	var fleet_cooldown_mult := float(snapshot.get("fleet_cooldown_mult", 1.0))
	var reload_crew_cooldown_mult := float(snapshot.get("reload_crew_cooldown_mult", 1.0))
	var reload_crew_speed_mult := float(snapshot.get("reload_crew_speed_mult", 1.0))
	var boarding_cooldown_mult := float(snapshot.get("boarding_reload_cooldown_mult", 1.0))
	var tempo_mult := float(snapshot.get("tempo_mult", 1.0))
	return "\n".join([
		"대포 재장전",
		"기본 시간: %.2fs" % base_cooldown,
		"화약 업그레이드: x%.2f" % upgrade_cooldown_mult,
		"해역 포격 속도: %s -> x%.2f" % [_format_percent(site_reload_bonus), site_reload_factor],
		"장전 병사: 속도 x%.2f -> 시간 x%.2f" % [reload_crew_speed_mult, reload_crew_cooldown_mult],
		"함대/상태/템포: x%.2f / x%.2f / x%.2f" % [fleet_cooldown_mult, boarding_cooldown_mult, tempo_mult],
		"계산: %.2fs x %.2f x %.2f x %.2f x %.2f x %.2f x %.2f = %.2fs" % [
			base_cooldown,
			upgrade_cooldown_mult,
			site_reload_factor,
			fleet_cooldown_mult,
			reload_crew_cooldown_mult,
			boarding_cooldown_mult,
			tempo_mult,
			final_cooldown,
		],
	])


static func _build_percent_bonus_tooltip(bonus_name: String, affected_stat: String, total_value: float, formula: String) -> String:
	if total_value <= 0.0001:
		return ""
	return "\n".join([
		"해역 보너스: %s %s" % [bonus_name, _format_percent(total_value)],
		"적용 대상: %s" % affected_stat,
		formula,
	])


static func _build_flat_bonus_tooltip(bonus_name: String, affected_stat: String, total_value: float, suffix: String = "") -> String:
	if total_value <= 0.0001:
		return ""
	return "\n".join([
		"해역 보너스: %s %s" % [bonus_name, _format_flat_bonus(total_value, suffix)],
		"적용 대상: %s" % affected_stat,
		"계산: 기존 수치 + 해역 보너스",
	])


static func _format_percent(value: float) -> String:
	var sign := "+" if value >= 0.0 else ""
	return "%s%d%%" % [sign, int(round(value * 100.0))]


static func _format_flat_bonus(value: float, suffix: String = "") -> String:
	var sign := "+" if value >= 0.0 else ""
	if absf(value - round(value)) < 0.01:
		return "%s%d%s" % [sign, int(round(value)), suffix]
	return "%s%.1f%s" % [sign, value, suffix]

static func _get_primary_cannon(ship) -> Node:
	var cannons_node := NodeContractHelper.get_cannons_container(ship)
	if not is_instance_valid(cannons_node):
		return null
	for child in cannons_node.get_children():
		if is_instance_valid(child):
			return child
	return null

static func _get_cannon_projectile_stats(cannon) -> Dictionary:
	var stats: Dictionary = {
		"damage": 0.0,
		"crit_chance": 0.0,
		"crit_multiplier": 1.0,
	}
	if not is_instance_valid(cannon):
		return stats
	var projectile_scene = cannon.get("cannonball_scene")
	if not (projectile_scene is PackedScene):
		return stats
	var projectile = (projectile_scene as PackedScene).instantiate()
	if projectile == null:
		return stats
	stats["damage"] = _get_float(projectile, "damage", 0.0)
	stats["crit_chance"] = _get_float(projectile, "crit_chance", 0.0)
	stats["crit_multiplier"] = _get_float(projectile, "crit_multiplier", 1.0)
	if projectile is Node:
		(projectile as Node).free()
	return stats

static func _collect_crew_stats(ship) -> Dictionary:
	var result: Dictionary = {
		"alive_count": 0,
		"general_count": 0,
		"spearman_count": 0,
		"fire_pot_count": 0,
		"repeater_count": 0,
		"singigeon_count": 0,
		"sample_hp": 0.0,
		"sample_defense": 0.0,
		"sword_damage": 0.0,
		"bow_damage": 0.0,
		"crit_chance": 0.0,
		"crit_multiplier": 1.0,
	}
	var soldiers_node = NodeContractHelper.get_soldiers_container(ship)
	if not is_instance_valid(soldiers_node):
		return result

	var sample_soldier = null
	for child in soldiers_node.get_children():
		if not is_instance_valid(child):
			continue
		var team_tag: String = str(child.get("team"))
		if team_tag != "player":
			continue
		if _is_dead_soldier_node(child):
			continue
		result["alive_count"] = int(result.get("alive_count", 0)) + 1
		var role: String = "general"
		if child.get("crew_role") != null:
			role = str(child.get("crew_role"))
		match role:
			"spearman":
				result["spearman_count"] = int(result.get("spearman_count", 0)) + 1
			"fire_pot":
				result["fire_pot_count"] = int(result.get("fire_pot_count", 0)) + 1
			"repeating_crossbow":
				result["repeater_count"] = int(result.get("repeater_count", 0)) + 1
			"singigeon":
				result["singigeon_count"] = int(result.get("singigeon_count", 0)) + 1
			_:
				result["general_count"] = int(result.get("general_count", 0)) + 1
		if sample_soldier == null or role == "general":
			sample_soldier = child
			if role == "general":
				pass

	if sample_soldier == null:
		return result

	result["sample_hp"] = _get_float(sample_soldier, "max_health", 0.0)
	var defense_bonus: float = 0.0
	if sample_soldier.has_meta("defense_flat_bonus"):
		defense_bonus = float(sample_soldier.get_meta("defense_flat_bonus"))
	result["sample_defense"] = _get_float(sample_soldier, "defense", 0.0) + defense_bonus
	result["crit_chance"] = _get_float(sample_soldier, "crit_chance", 0.0)
	result["crit_multiplier"] = _get_float(sample_soldier, "crit_multiplier", 1.0)
	var melee_damage: float = 0.0
	var ranged_damage: float = 0.0
	if sample_soldier.get("weapon_sword") != null:
		melee_damage = _get_float(sample_soldier.get("weapon_sword"), "damage", 0.0)
	if sample_soldier.get("weapon_bow") != null:
		ranged_damage = _get_float(sample_soldier.get("weapon_bow"), "damage", 0.0)
	result["sword_damage"] = melee_damage
	result["bow_damage"] = ranged_damage
	return result

static func _get_singigeon_proc_value(hud) -> String:
	var um: Node = hud.get_node_or_null("/root/UpgradeManager") if is_instance_valid(hud) else null
	if not is_instance_valid(um) or not ("current_levels" in um):
		return "0%"
	var level := int(um.current_levels.get("singigeon", 0))
	if level <= 0:
		return "0%"
	var upgrades: Dictionary = um.get("UPGRADES") if um.get("UPGRADES") is Dictionary else {}
	var proc_stats := UpgradeManagerDataHelper.get_singigeon_proc_stats(upgrades, um.current_levels, level)
	return "%.0f%%" % (float(proc_stats.get("chance", 0.0)) * 100.0)


static func _is_dead_soldier_node(soldier: Node) -> bool:
	if not is_instance_valid(soldier):
		return true
	if soldier.has_method("is_dead_soldier"):
		return soldier.call("is_dead_soldier") == true
	var state_value = soldier.get("current_state")
	if soldier.has_method("is_state_value_dead"):
		return soldier.call("is_state_value_dead", state_value) == true
	return state_value != null and int(state_value) == 4

static func _build_site_bonus_rows(player_ship: Node) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if not is_instance_valid(player_ship):
		return rows
	var totals_variant: Variant = player_ship.get_meta(SITE_BONUS_TOTALS_META, {})
	if not (totals_variant is Dictionary):
		return rows
	var totals: Dictionary = totals_variant as Dictionary
	if totals.is_empty():
		return rows
	var counts_variant: Variant = player_ship.get_meta(SITE_BONUS_COUNTS_META, {})
	var counts: Dictionary = counts_variant as Dictionary if counts_variant is Dictionary else {}
	var handled_ids: Dictionary = {}
	for entry in _load_site_bonus_entries():
		if not (entry is Dictionary):
			continue
		var entry_dict: Dictionary = entry
		var bonus_id := str(entry_dict.get("id", ""))
		if bonus_id.is_empty() or not totals.has(bonus_id):
			continue
		var total_value := maxf(0.0, float(totals.get(bonus_id, 0.0)))
		if total_value <= 0.0001:
			continue
		rows.append(_make_site_bonus_row(
			bonus_id,
			str(entry_dict.get("name", bonus_id)),
			str(entry_dict.get("format", "flat")),
			total_value,
			int(counts.get(bonus_id, 0))
		))
		handled_ids[bonus_id] = true
	var extra_ids: Array[String] = []
	for bonus_id_variant in totals.keys():
		var bonus_id := str(bonus_id_variant)
		if handled_ids.has(bonus_id):
			continue
		if maxf(0.0, float(totals.get(bonus_id_variant, 0.0))) <= 0.0001:
			continue
		extra_ids.append(bonus_id)
	extra_ids.sort()
	for bonus_id in extra_ids:
		rows.append(_make_site_bonus_row(
			bonus_id,
			bonus_id,
			"flat",
			maxf(0.0, float(totals.get(bonus_id, 0.0))),
			int(counts.get(bonus_id, 0))
		))
	return rows


static func _make_site_bonus_row(bonus_id: String, bonus_name: String, value_format: String, total_value: float, count: int) -> Dictionary:
	var label := bonus_name
	if count > 1:
		label = "%s x%d" % [label, count]
	return {
		"icon": str(SITE_BONUS_ICON_BY_ID.get(bonus_id, "auto_awesome")),
		"label": label,
		"value": _format_site_bonus_value(value_format, total_value),
		"tooltip": _build_site_bonus_tooltip(bonus_id, bonus_name, value_format, total_value, count),
	}


static func _build_site_bonus_tooltip(bonus_id: String, bonus_name: String, value_format: String, total_value: float, count: int) -> String:
	var lines: Array[String] = [
		"해역 보너스: %s" % bonus_name,
		"누적: %s%s" % [_format_site_bonus_value(value_format, total_value), " (%d회)" % count if count > 0 else ""],
	]
	match bonus_id:
		"cannon_damage_pct":
			lines.append("적용: 대포 피해 배율에 합산")
			lines.append("계산: 기본 포탄 피해 x (1 + 철환 업그레이드 + 해역 포격 피해) x 함대 피해")
		"cannon_reload_pct":
			lines.append("적용: 대포 재장전 시간을 감소")
			lines.append("계산: 기본 재장전 x 화약 배율 x (1 - 해역 포격 속도) x 병사/함대/상태 배율")
		"crew_damage_pct":
			lines.append("적용: 병사 검/활/무기 피해 배율에 합산")
			lines.append("계산: 창 피해는 창병 업그레이드와 합산, 활 피해는 해역 병사 무기 보너스와 합산")
		"crew_defense_add":
			lines.append("적용: 병사 방어력에 더함")
			lines.append("계산: 기존 병사 방어력 + 해역 보너스")
		"hull_regen_add":
			lines.append("적용: 초당 선체 자동 수리량에 더함")
			lines.append("계산: 기존 자동 수리량 + 해역 보너스")
		"hull_defense_add":
			lines.append("적용: 선체 방어력에 더함")
			lines.append("계산: 기존 선체 방어력 + 해역 보너스")
		"max_hull_add":
			lines.append("적용: 최대 내구도에 더함")
			lines.append("획득 시 현재 내구도도 같은 양만큼 회복")
		_:
			lines.append("적용: 해당 수치에 누적 반영")
	return "\n".join(lines)


static func _load_site_bonus_entries() -> Array:
	if not FileAccess.file_exists(SITE_BONUS_DATA_PATH):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SITE_BONUS_DATA_PATH))
	if not (parsed is Dictionary):
		return []
	var entries: Variant = (parsed as Dictionary).get("minor_stat_bonuses", [])
	if entries is Array:
		return entries as Array
	return []


static func _format_site_bonus_value(value_format: String, value: float) -> String:
	match value_format:
		"percent":
			return "+%d%%" % int(round(value * 100.0))
		"per_second":
			return "+%.1f/초" % value
		"hp":
			return "+%d" % int(round(value))
		_:
			if absf(value - round(value)) < 0.01:
				return "+%d" % int(round(value))
			return "+%.1f" % value


static func _get_site_bonus_total(ship: Node, bonus_id: String) -> float:
	if not is_instance_valid(ship):
		return 0.0
	var totals_variant: Variant = ship.get_meta(SITE_BONUS_TOTALS_META, {})
	if totals_variant is Dictionary:
		return maxf(0.0, float((totals_variant as Dictionary).get(bonus_id, 0.0)))
	return 0.0

static func _get_float(obj, property_name: String, default_value: float) -> float:
	if obj == null:
		return default_value
	var value = obj.get(property_name)
	if value == null:
		return default_value
	return float(value)

static func _get_int(obj, property_name: String, default_value: int) -> int:
	if obj == null:
		return default_value
	var value = obj.get(property_name)
	if value == null:
		return default_value
	return int(value)
