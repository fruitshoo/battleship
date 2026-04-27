extends RefCounted
class_name LauncherCombatHelper


const LIMBO_AI_WEAPON_INTENT_STALE_FRAMES := 4
const TARGET_SCAN_LOAD_SHIP_SOFT_LIMIT := 12
const TARGET_SCAN_LOAD_SOLDIER_SOFT_LIMIT := 60
const TARGET_SCAN_LOAD_PROJECTILE_SOFT_LIMIT := 18

static var _target_scan_load_frame: int = -1
static var _target_scan_load_multiplier: float = 1.0
static var _alive_soldier_cache_frame: int = -1
static var _alive_soldier_cache: Dictionary = {}


static func enemy_team_tag(team: String) -> String:
	return "enemy" if team == "player" else "player"


static func is_enemy_node(node: Node, team: String) -> bool:
	if not is_instance_valid(node):
		return false
	var resolved := HitTargetResolver.resolve_team_tag(node)
	if not resolved.is_empty():
		return resolved == enemy_team_tag(team)
	return node.is_in_group(enemy_team_tag(team))


static func resolve_owner_ship(launcher: Node) -> Node:
	var node: Node = launcher.get_parent() if is_instance_valid(launcher) else null
	while is_instance_valid(node):
		if node.is_in_group("ships"):
			return node
		if "is_sinking" in node and "is_dying" in node:
			return node
		node = node.get_parent()
	return null


static func is_owner_combat_ready(owner_ship: Node) -> bool:
	if not is_instance_valid(owner_ship):
		return true
	if owner_ship.has_method("are_weapons_disabled") and owner_ship.are_weapons_disabled():
		return false
	if owner_ship.has_method("is_combat_disabled") and owner_ship.is_combat_disabled():
		return false
	if owner_ship.get("limbo_ai_pilot_enabled") == true and NodeContractHelper.get_team_tag(owner_ship, "") == "enemy":
		var weapon_frame := int(owner_ship.get_meta(ShipAILimboKeys.META_WEAPON_FRAME, -1000000))
		if Engine.get_physics_frames() - weapon_frame <= LIMBO_AI_WEAPON_INTENT_STALE_FRAMES:
			var weapon_intent := str(owner_ship.get_meta(ShipAILimboKeys.META_WEAPON_INTENT, "")).strip_edges()
			if weapon_intent == ShipAILimboKeys.WEAPON_HOLD_FIRE:
				return false
	return owner_ship.get("deck_is_overrun") != true


static func get_target_scan_interval(base_interval: float, tracking_multiplier: float, has_valid_target: bool, jitter: float = 0.05) -> float:
	var interval := base_interval
	if has_valid_target:
		interval *= tracking_multiplier
	interval *= get_target_scan_load_multiplier()
	return interval + randf_range(0.0, jitter)


static func get_target_scan_load_multiplier() -> float:
	var frame := Engine.get_physics_frames()
	if frame == _target_scan_load_frame:
		return _target_scan_load_multiplier
	_target_scan_load_frame = frame
	var ship_count := EntityRegistry.count_ships()
	var soldier_count := EntityRegistry.count_soldiers()
	var projectile_count := EntityRegistry.count_projectiles()
	var multiplier := 1.0
	if ship_count > TARGET_SCAN_LOAD_SHIP_SOFT_LIMIT:
		multiplier += minf(0.55, float(ship_count - TARGET_SCAN_LOAD_SHIP_SOFT_LIMIT) * 0.035)
	if soldier_count > TARGET_SCAN_LOAD_SOLDIER_SOFT_LIMIT:
		multiplier += minf(0.28, float(soldier_count - TARGET_SCAN_LOAD_SOLDIER_SOFT_LIMIT) * 0.006)
	if projectile_count > TARGET_SCAN_LOAD_PROJECTILE_SOFT_LIMIT:
		multiplier += minf(0.45, float(projectile_count - TARGET_SCAN_LOAD_PROJECTILE_SOFT_LIMIT) * 0.015)
	_target_scan_load_multiplier = clampf(multiplier, 1.0, 2.1)
	return _target_scan_load_multiplier


static func get_valid_target_node(target: Variant) -> Node3D:
	if not is_instance_valid(target) or not (target is Node3D):
		return null
	var target_node := target as Node3D
	if target_node.is_queued_for_deletion():
		return null
	return target_node


static func is_combat_targetable(node: Node) -> bool:
	if not is_instance_valid(node):
		return false
	if node.has_method("is_combat_disabled") and node.is_combat_disabled():
		return false
	return true


static func get_enemy_combat_target(target: Variant, team: String) -> Node3D:
	var target_node := get_valid_target_node(target)
	if target_node == null:
		return null
	if not is_combat_targetable(target_node):
		return null
	if not is_enemy_node(target_node, team):
		return null
	return target_node


static func is_target_in_range(origin: Node3D, target: Node3D, max_range: float) -> bool:
	if not is_instance_valid(origin) or not is_instance_valid(target):
		return false
	return origin.global_position.distance_squared_to(target.global_position) <= max_range * max_range


static func has_friendly_boarding_attacker(target_ship: Node, team: String) -> bool:
	if not is_instance_valid(target_ship) or not target_ship.has_method("get_boarding_attacker_ship"):
		return false
	var attacker: Variant = target_ship.get_boarding_attacker_ship()
	return is_instance_valid(attacker) and attacker is Node and NodeContractHelper.get_team_tag(attacker, "") == team


static func has_alive_soldier_on_team(target_ship: Node, team: String) -> bool:
	if not is_instance_valid(target_ship):
		return false
	_refresh_alive_soldier_cache_if_needed()
	var cache_key := "%d:%s" % [target_ship.get_instance_id(), team]
	if _alive_soldier_cache.has(cache_key):
		return _alive_soldier_cache[cache_key] == true
	var soldiers_node := NodeContractHelper.get_soldiers_container(target_ship)
	if not is_instance_valid(soldiers_node):
		_alive_soldier_cache[cache_key] = false
		return false
	for child in soldiers_node.get_children():
		if not is_instance_valid(child):
			continue
		if NodeContractHelper.get_team_tag(child, "") != team:
			continue
		if SoldierStateHelper.is_dead_soldier(child):
			continue
		_alive_soldier_cache[cache_key] = true
		return true
	_alive_soldier_cache[cache_key] = false
	return false


static func _refresh_alive_soldier_cache_if_needed() -> void:
	var frame := Engine.get_physics_frames()
	if frame == _alive_soldier_cache_frame:
		return
	_alive_soldier_cache_frame = frame
	_alive_soldier_cache.clear()


static func is_enemy_soldier_target(target: Variant, team: String, origin: Node3D, max_range: float) -> bool:
	var target_node := get_valid_target_node(target)
	if target_node == null:
		return false
	if SoldierStateHelper.is_dead_soldier(target_node):
		return false
	var target_team := NodeContractHelper.get_team_tag(target_node, "")
	if not target_team.is_empty() and target_team != enemy_team_tag(team):
		return false
	return is_target_in_range(origin, target_node, max_range)
