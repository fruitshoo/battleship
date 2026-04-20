extends RefCounted
class_name LauncherCombatHelper

const HitTargetResolver = preload("res://scripts/helpers/hit_target_resolver.gd")
const NodeContractHelper = preload("res://scripts/helpers/node_contract_helper.gd")
const SoldierStateHelper = preload("res://scripts/entities/soldiers/soldier_state_helper.gd")
const ShipAILimboKeys = preload("res://scripts/ai/limbo/ship_ai_limbo_keys.gd")

const LIMBO_AI_WEAPON_INTENT_STALE_FRAMES := 4


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
	return interval + randf_range(0.0, jitter)


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
	var soldiers_node := NodeContractHelper.get_soldiers_container(target_ship)
	if not is_instance_valid(soldiers_node):
		return false
	for child in soldiers_node.get_children():
		if not is_instance_valid(child):
			continue
		if NodeContractHelper.get_team_tag(child, "") != team:
			continue
		if SoldierStateHelper.is_dead_soldier(child):
			continue
		return true
	return false


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
