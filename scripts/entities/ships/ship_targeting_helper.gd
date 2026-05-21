extends RefCounted
class_name ShipTargetingHelper

const PlayerFleetRoleHelper = preload("res://scripts/entities/ships/player_fleet_role_helper.gd")


const PLAYER_FLAGSHIP_TARGET_WEIGHT := 0.8
const PLAYER_SUPPORT_TARGET_WEIGHT := 1.08


static func select_player_target_for(ship: Node) -> Node3D:
	if not is_instance_valid(ship):
		return null
	var players := EntityRegistry.get_ships_by_team("player")
	if _get_team_tag(ship) == "player":
		return _select_controlled_player(players, ship)
	return _select_weighted_player_target(players, ship)


static func is_ship_targetable(node: Node) -> bool:
	if not is_instance_valid(node):
		return false
	if node.has_method("is_combat_disabled") and node.call("is_combat_disabled") == true:
		return false
	if node.has_method("is_sinking_or_dying") and node.call("is_sinking_or_dying") == true:
		return false
	return node.get("is_sinking") != true and node.get("is_dying") != true and node.get("is_dead") != true


static func is_player_controlled_ship(node: Node) -> bool:
	return PlayerFleetRoleHelper.is_player_flagship(node)


static func is_support_fleet_ship(node: Node) -> bool:
	return PlayerFleetRoleHelper.is_support_ship(node)


static func _select_controlled_player(players: Array, requester: Node) -> Node3D:
	for candidate in players:
		if candidate == requester:
			continue
		if not is_ship_targetable(candidate):
			continue
		if is_player_controlled_ship(candidate) and candidate is Node3D:
			return candidate as Node3D
	return null


static func _select_weighted_player_target(players: Array, requester: Node) -> Node3D:
	var requester_3d := requester as Node3D
	if not is_instance_valid(requester_3d):
		return null
	var closest_score := INF
	var closest_player: Node3D = null
	for candidate in players:
		if candidate == requester:
			continue
		if not is_ship_targetable(candidate):
			continue
		var candidate_3d := candidate as Node3D
		if not is_instance_valid(candidate_3d):
			continue
		var score: float = requester_3d.global_position.distance_squared_to(candidate_3d.global_position)
		if PlayerFleetRoleHelper.is_player_flagship(candidate):
			score *= PLAYER_FLAGSHIP_TARGET_WEIGHT
		elif PlayerFleetRoleHelper.is_support_ship(candidate):
			score *= PLAYER_SUPPORT_TARGET_WEIGHT
		if score < closest_score:
			closest_score = score
			closest_player = candidate_3d
	return closest_player


static func _get_team_tag(node: Node) -> String:
	if not is_instance_valid(node):
		return ""
	if node.has_method("get_team_tag"):
		return str(node.call("get_team_tag"))
	var team_value: Variant = node.get("team")
	return str(team_value) if team_value != null else ""
