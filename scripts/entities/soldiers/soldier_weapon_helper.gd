extends RefCounted

const BOW_SCENE = preload("res://scenes/entities/weapons/weapon_bow.tscn")
const REPEATING_CROSSBOW_SCENE = preload("res://scenes/entities/weapons/weapon_repeating_crossbow.tscn")
const SINGIGEON_SCENE = preload("res://scenes/entities/weapons/weapon_singigeon.tscn")
const SWORD_SCENE = preload("res://scenes/entities/weapons/weapon_sword.tscn")
const SPEARMAN_MELEE_SCENES := [
	preload("res://scenes/entities/weapons/weapon_spear.tscn"),
	preload("res://scenes/entities/weapons/weapon_trident.tscn"),
]


static func get_ranged_weapon_id(soldier) -> String:
	if not is_instance_valid(soldier.weapon_bow):
		return ""
	return str(soldier.weapon_bow.get_meta("weapon_id", ""))


static func get_melee_weapon_id(soldier) -> String:
	if not is_instance_valid(soldier.weapon_sword):
		return ""
	return str(soldier.weapon_sword.get_meta("weapon_id", ""))


static func apply_role_loadout(soldier) -> void:
	match str(soldier.crew_role):
		"spearman":
			if get_melee_weapon_id(soldier) != "spearman":
				var spear_scene: PackedScene = SPEARMAN_MELEE_SCENES[randi() % SPEARMAN_MELEE_SCENES.size()]
				soldier.equip_melee_weapon(spear_scene, "spearman")
			soldier._set_active_weapon("sword")
		"repeating_crossbow":
			if get_ranged_weapon_id(soldier) != "repeating_crossbow":
				soldier.equip_weapon(REPEATING_CROSSBOW_SCENE, "repeating_crossbow")
			elif is_instance_valid(soldier.weapon_bow) and soldier.weapon_bow.has_method("refresh_upgrade_stats"):
				soldier.weapon_bow.refresh_upgrade_stats()
			if not soldier.is_melee_only:
				soldier._set_active_weapon("bow")
		"singigeon":
			if get_ranged_weapon_id(soldier) != "singigeon":
				soldier.equip_weapon(SINGIGEON_SCENE, "singigeon")
			elif is_instance_valid(soldier.weapon_bow) and soldier.weapon_bow.has_method("refresh_upgrade_stats"):
				soldier.weapon_bow.refresh_upgrade_stats()
			if not soldier.is_melee_only:
				soldier._set_active_weapon("bow")
		_:
			var melee_id := _get_standard_melee_weapon_id(soldier)
			if get_melee_weapon_id(soldier) != melee_id:
				soldier.equip_melee_weapon(_get_standard_melee_scene(soldier), melee_id)
			if get_ranged_weapon_id(soldier) != "bow":
				soldier.equip_weapon(BOW_SCENE, "bow")
			if not soldier.is_melee_only:
				soldier._set_active_weapon("bow")
	soldier._update_role_visual()


static func _get_standard_melee_weapon_id(soldier) -> String:
	return "spearman" if _should_use_spear_loadout(soldier) else "sword"


static func _get_standard_melee_scene(soldier) -> PackedScene:
	if _should_use_spear_loadout(soldier):
		return SPEARMAN_MELEE_SCENES[randi() % SPEARMAN_MELEE_SCENES.size()]
	return SWORD_SCENE


static func _should_use_spear_loadout(soldier) -> bool:
	if not is_instance_valid(soldier):
		return false
	if soldier.get("team") == null or str(soldier.get("team")) != "player":
		return false
	var um: Node = soldier.get_node_or_null("/root/UpgradeManager")
	if not is_instance_valid(um) or not ("current_levels" in um):
		return false
	return int(um.current_levels.get("crew_numbers", 0)) > 0


static func update_combat_weapon_choice(soldier, nearest) -> void:
	if nearest:
		var dist_xz: float = Vector2(
			soldier.global_position.x - nearest.global_position.x,
			soldier.global_position.z - nearest.global_position.z
		).length()
		var target_ship = nearest.get("owned_ship")
		var cross_ship_close: bool = (
			is_instance_valid(soldier.owned_ship)
			and is_instance_valid(target_ship)
			and target_ship != soldier.owned_ship
			and soldier._is_ship_pair_in_melee_range(target_ship)
		)
		var cross_ship_contact_ready: bool = false
		if cross_ship_close and soldier.has_method("_is_in_cross_ship_contact_zone"):
			cross_ship_contact_ready = soldier._is_in_cross_ship_contact_zone(target_ship) == true
		if cross_ship_close and soldier.has_method("_should_hold_defensive_deck_position_against") and soldier._should_hold_defensive_deck_position_against(target_ship):
			cross_ship_contact_ready = false
		var cross_ship_melee_ready: bool = cross_ship_contact_ready and _can_cross_ship_melee_reach_target(soldier, dist_xz)

		if soldier.is_melee_only:
			soldier._set_active_weapon("sword")
		elif soldier.crew_role == "spearman":
			soldier._set_active_weapon("sword")
		elif soldier.is_ranged_only:
			soldier._set_active_weapon("bow")
		elif cross_ship_melee_ready:
			# 다른 배와 교전 중이라도, 실제 접촉 가능한 가장자리까지 도달했을 때만
			# 일반 병사를 근접 무기로 전환한다.
			soldier._set_active_weapon("sword")
		elif dist_xz <= soldier.weapon_switch_distance:
			soldier._set_active_weapon("sword")
		else:
			soldier._set_active_weapon("bow")
		return

	# 적이 없으면 기본적으로 활을 들고 대기한다.
	if soldier.is_melee_only or soldier.crew_role == "spearman":
		soldier._set_active_weapon("sword")
	else:
		soldier._set_active_weapon("bow")


static func _can_cross_ship_melee_reach_target(soldier, dist_xz: float) -> bool:
	if not is_instance_valid(soldier.weapon_sword):
		return false
	var melee_range: float = float(soldier.weapon_sword.get("attack_range")) if soldier.weapon_sword.get("attack_range") != null else soldier.weapon_switch_distance
	var reach_buffer: float = 0.35
	var max_switch_distance: float = minf(maxf(soldier.cross_ship_melee_switch_distance, soldier.weapon_switch_distance), melee_range + reach_buffer)
	return dist_xz <= max_switch_distance
