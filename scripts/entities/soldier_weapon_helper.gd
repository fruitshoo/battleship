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
	return String(soldier.weapon_bow.get_meta("weapon_id", ""))


static func get_melee_weapon_id(soldier) -> String:
	if not is_instance_valid(soldier.weapon_sword):
		return ""
	return String(soldier.weapon_sword.get_meta("weapon_id", ""))


static func apply_role_loadout(soldier) -> void:
	match String(soldier.crew_role):
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
			if get_melee_weapon_id(soldier) != "sword":
				soldier.equip_melee_weapon(SWORD_SCENE, "sword")
			if get_ranged_weapon_id(soldier) != "bow":
				soldier.equip_weapon(BOW_SCENE, "bow")
			if not soldier.is_melee_only:
				soldier._set_active_weapon("bow")
	soldier._update_role_visual()


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

		if soldier.is_melee_only:
			soldier._set_active_weapon("sword")
		elif soldier.crew_role == "spearman":
			soldier._set_active_weapon("sword")
		elif soldier.is_ranged_only:
			soldier._set_active_weapon("bow")
		elif cross_ship_close:
			# 인접한 적선과 붙었을 때도 거리가 남아 있으면 활/연노를 유지해 교전 공백을 줄인다.
			var cross_ship_melee_switch_distance: float = maxf(
				soldier.weapon_switch_distance,
				soldier.cross_ship_melee_switch_distance
			)
			if dist_xz <= cross_ship_melee_switch_distance:
				soldier._set_active_weapon("sword")
			else:
				soldier._set_active_weapon("bow")
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
