extends RefCounted

const PLAYER_CANNON_BASE_DAMAGE := 25.0
const PLAYER_SAIL_TURN_SPEED := 60.0
const MATERIAL_SYMBOLS_FONT = preload("res://assets/fonts/MaterialSymbolsOutlined.ttf")

static func update_stat_panel(hud) -> void:
	if not is_instance_valid(hud.stat_panel):
		return
	hud.stat_panel.visible = hud.show_stat_panel
	if not hud.show_stat_panel:
		return
	if not is_instance_valid(hud.stat_content):
		return
	var sections: Array[Dictionary] = build_stat_sections(hud)
	var signature: String = _build_signature(sections)
	if hud._last_stat_signature == signature:
		return
	hud._last_stat_signature = signature
	_rebuild_stat_content(hud, sections)

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

	var hull_hp: float = _get_float(ship, "hull_hp", 0.0)
	var max_hull_hp: float = _get_float(ship, "max_hull_hp", 0.0)
	var hull_defense: float = _get_float(ship, "hull_defense", 0.0)
	sections.append({
		"title": "선체",
		"icon": "shield",
		"rows": [
			{"icon": "favorite", "label": "내구도", "value": "%.0f / %.0f" % [hull_hp, max_hull_hp]},
			{"icon": "shield", "label": "방어력", "value": "%.1f" % hull_defense},
		],
	})

	var current_speed: float = _get_float(ship, "current_speed", 0.0)
	var max_speed: float = _get_float(ship, "max_speed", 0.0)
	var sail_efficiency_mult: float = _get_float(ship, "sail_efficiency_mult", 1.0)
	var sail_turn_speed: float = _get_float(ship, "sail_turn_speed", PLAYER_SAIL_TURN_SPEED)
	var rowing_speed: float = _get_float(ship, "rowing_speed", 0.0)
	var rowing_acceleration_mult: float = _get_float(ship, "rowing_acceleration_mult", 1.0)
	var max_rowing_stamina: float = _get_float(ship, "max_rowing_stamina", 100.0)
	var rudder_turn_speed: float = _get_float(ship, "rudder_turn_speed", 0.0)
	var rowing_stamina: float = _get_float(ship, "rowing_stamina", 0.0)
	var stamina_drain_rate: float = _get_float(ship, "stamina_drain_rate", 0.0)
	var stamina_recovery_rate: float = _get_float(ship, "stamina_recovery_rate", 0.0)
	sections.append({
		"title": "항해",
		"icon": "air",
		"rows": [
			{"icon": "speed", "label": "현재 / 최고속", "value": "%.1f / %.1f" % [current_speed, max_speed]},
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
	var cannon_fleet_mult: float = 1.0
	var cannon_damage: float = 0.0
	var cannon_range: float = 0.0
	var cannon_cooldown: float = 0.0
	var cannon_crit_chance: float = 0.0
	var cannon_crit_multiplier: float = 1.0
	var cannon_expected_dps: float = 0.0
	var primary_cannon: Node = _get_primary_cannon(ship)
	if is_instance_valid(primary_cannon):
		var cannons_node = ship.get_node_or_null("Cannons")
		if is_instance_valid(cannons_node):
			for child in cannons_node.get_children():
				if is_instance_valid(child):
					cannon_count += 1
		if primary_cannon.has_method("_get_current_range"):
			cannon_range = float(primary_cannon.call("_get_current_range"))
		else:
			cannon_range = _get_float(primary_cannon, "detection_range", 0.0)
		if primary_cannon.has_method("_get_current_cooldown"):
			cannon_cooldown = float(primary_cannon.call("_get_current_cooldown"))
		else:
			cannon_cooldown = _get_float(primary_cannon, "fire_cooldown", 0.0)
		var projectile_stats: Dictionary = _get_cannon_projectile_stats(primary_cannon)
		var base_damage: float = float(projectile_stats.get("damage", 0.0))
		if base_damage <= 1.0 and str(primary_cannon.get("team")) == "player":
			base_damage = PLAYER_CANNON_BASE_DAMAGE
		cannon_base_damage = base_damage
		cannon_crit_chance = _get_float(primary_cannon, "_cached_crit_chance", float(projectile_stats.get("crit_chance", 0.0)))
		cannon_crit_multiplier = _get_float(primary_cannon, "_cached_crit_multiplier", float(projectile_stats.get("crit_multiplier", 1.0)))
		cannon_damage_mult = _get_float(primary_cannon, "_cached_dmg_mult", 1.0)
		cannon_fleet_mult = _get_float(primary_cannon, "fleet_damage_mult", 1.0)
		cannon_damage = base_damage * cannon_damage_mult * cannon_fleet_mult
		var expected_shot_damage: float = cannon_damage * (1.0 + cannon_crit_chance * (cannon_crit_multiplier - 1.0))
		if cannon_cooldown > 0.0:
			cannon_expected_dps = expected_shot_damage / cannon_cooldown
	sections.append({
		"title": "대포",
		"icon": "sports_baseball",
		"rows": [
			{"icon": "apps", "label": "포문 수", "value": str(cannon_count)},
			{"icon": "adjust", "label": "기본 / 최종 데미지", "value": "%.1f / %.1f" % [cannon_base_damage, cannon_damage]},
			{"icon": "network_node", "label": "배율", "value": "업그레이드 x%.2f | 함대 x%.2f" % [cannon_damage_mult, cannon_fleet_mult]},
			{"icon": "radar", "label": "사거리", "value": "%.1fm" % cannon_range},
			{"icon": "timer", "label": "재장전", "value": "%.2fs" % cannon_cooldown},
			{"icon": "grade", "label": "치명타", "value": "%.1f%% x%.1f" % [cannon_crit_chance * 100.0, cannon_crit_multiplier]},
			{"icon": "monitoring", "label": "기대 DPS (1문)", "value": "%.1f" % cannon_expected_dps},
		],
	})

	var crew_stats: Dictionary = _collect_crew_stats(ship)
	sections.append({
		"title": "병사",
		"icon": "groups",
		"rows": [
			{"icon": "group", "label": "정원 / 생존", "value": "%d / %d" % [int(crew_stats.get("alive_count", 0)), int(_get_int(ship, "max_crew_count", 0))]},
			{"icon": "schedule", "label": "보충 시간", "value": "%.1fs" % _get_float(ship, "crew_respawn_interval", 0.0)},
			{"icon": "badge", "label": "편성", "value": "일반 %d | 창 %d | 화통 %d | 연노 %d" % [
				int(crew_stats.get("general_count", 0)),
				int(crew_stats.get("spearman_count", 0)),
				int(crew_stats.get("fire_pot_count", 0)),
				int(crew_stats.get("repeater_count", 0)),
			]},
			{"icon": "rocket_launch", "label": "신기전병", "value": "%d명" % [
				int(crew_stats.get("singigeon_count", 0)),
			]},
			{"icon": "health_and_safety", "label": "대표 병사 HP / 방어", "value": "%.0f / %.1f" % [
				float(crew_stats.get("sample_hp", 0.0)),
				float(crew_stats.get("sample_defense", 0.0)),
			]},
			{"icon": "swords", "label": "검 / 활", "value": "%.1f / %.1f" % [
				float(crew_stats.get("sword_damage", 0.0)),
				float(crew_stats.get("bow_damage", 0.0)),
			]},
			{"icon": "grade", "label": "치명타", "value": "%.0f%% x%.1f" % [
				float(crew_stats.get("crit_chance", 0.0)) * 100.0,
				float(crew_stats.get("crit_multiplier", 1.0)),
			]},
		],
	})

	var relic_names: Array[String] = _get_relic_names()
	if not relic_names.is_empty():
		var relic_rows: Array[Dictionary] = []
		for relic_name in relic_names:
			relic_rows.append({"icon": "auto_awesome", "label": "렐릭", "value": relic_name})
		sections.append({
			"title": "렐릭",
			"icon": "diamond",
			"rows": relic_rows,
		})

	return sections

static func _build_signature(sections: Array[Dictionary]) -> String:
	var parts: Array[String] = []
	for section in sections:
		parts.append(str(section.get("title", "")))
		for row in section.get("rows", []):
			if row is Dictionary:
				parts.append("%s=%s" % [str(row.get("label", "")), str(row.get("value", ""))])
	return "|".join(parts)

static func _rebuild_stat_content(hud, sections: Array[Dictionary]) -> void:
	for child in hud.stat_content.get_children():
		child.queue_free()
	for section in sections:
		hud.stat_content.add_child(_create_section(section))

static func _create_section(section: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.05, 0.08, 0.12, 0.76)
	panel_style.border_color = Color(0.38, 0.55, 0.72, 0.34)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(8)
	panel_style.content_margin_left = 10
	panel_style.content_margin_right = 10
	panel_style.content_margin_top = 8
	panel_style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", panel_style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	vbox.add_child(header)

	var icon_label := _create_icon_label(str(section.get("icon", "analytics")), 18, Color(0.78, 0.9, 1.0))
	header.add_child(icon_label)

	var title := Label.new()
	title.text = str(section.get("title", ""))
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0))
	header.add_child(title)

	var separator := HSeparator.new()
	vbox.add_child(separator)

	for row in section.get("rows", []):
		if row is Dictionary:
			vbox.add_child(_create_stat_row(row))

	return panel

static func _create_stat_row(row: Dictionary) -> Control:
	var row_box := HBoxContainer.new()
	row_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_box.add_theme_constant_override("separation", 8)

	row_box.add_child(_create_icon_label(str(row.get("icon", "chevron_right")), 16, Color(0.68, 0.85, 1.0)))

	var label := Label.new()
	label.text = str(row.get("label", ""))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.78, 0.84, 0.9))
	row_box.add_child(label)

	var value := Label.new()
	value.text = str(row.get("value", ""))
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.add_theme_font_size_override("font_size", 12)
	value.add_theme_color_override("font_color", Color(0.94, 0.96, 0.99))
	value.add_theme_color_override("font_outline_color", Color(0.03, 0.05, 0.08, 0.85))
	value.add_theme_constant_override("outline_size", 2)
	row_box.add_child(value)

	return row_box

static func _create_icon_label(icon_name: String, font_size: int, color: Color) -> Label:
	var icon_label := Label.new()
	icon_label.custom_minimum_size = Vector2(18, 18)
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_label.add_theme_font_size_override("font_size", font_size)
	icon_label.add_theme_color_override("font_color", color)
	if MATERIAL_SYMBOLS_FONT:
		icon_label.add_theme_font_override("font", MATERIAL_SYMBOLS_FONT)
	icon_label.text = icon_name
	return icon_label

static func _get_primary_cannon(ship) -> Node:
	var cannons_node = ship.get_node_or_null("Cannons")
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
	var soldiers_node = ship.get_node_or_null("Soldiers")
	if not is_instance_valid(soldiers_node):
		return result

	var sample_soldier = null
	for child in soldiers_node.get_children():
		if not is_instance_valid(child):
			continue
		var team_tag: String = str(child.get("team"))
		if team_tag != "player":
			continue
		var state_value = child.get("current_state")
		if state_value != null and int(state_value) == 4:
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
	if sample_soldier.get_meta("defense_flat_bonus") != null:
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

static func _get_relic_names() -> Array[String]:
	var relic_names: Array[String] = []
	if not is_instance_valid(UpgradeManager):
		return relic_names
	var acquired = UpgradeManager.get("acquired_relics")
	var relics = UpgradeManager.get("RELICS")
	if not (acquired is Array) or not (relics is Dictionary):
		return relic_names
	for relic_id in acquired:
		var relic_data = relics.get(relic_id, {})
		if relic_data is Dictionary:
			relic_names.append(str(relic_data.get("name", relic_id)))
	return relic_names

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
