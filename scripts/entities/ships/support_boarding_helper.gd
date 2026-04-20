extends RefCounted
class_name SupportBoardingHelper


const SUPPORT_BOARDING_PURPOSE := ShipBoardingMetaHelper.PURPOSE_SUPPORT_ATTACK
const SUPPORT_RESCUE_BOARDING_PURPOSE := ShipBoardingMetaHelper.PURPOSE_SUPPORT_RESCUE


static func get_boarding_purpose(is_rescue_boarding: bool) -> String:
	return ShipBoardingMetaHelper.get_support_boarding_purpose(is_rescue_boarding)


static func is_support_rescue_boarding_active(player_ship: Node) -> bool:
	if not is_instance_valid(player_ship):
		return false
	return not _get_support_rescue_boarding_ships(player_ship).is_empty()


static func finish_support_rescue_boarding_if_safe(player_ship: Node) -> void:
	var rescue_ships := _get_support_rescue_boarding_ships(player_ship)
	if rescue_ships.is_empty():
		return
	for support_ship in rescue_ships:
		ShipBoardingMetaHelper.set_transfer_suppressed(support_ship, true)

	for soldier in EntityRegistry.get_soldiers_by_ship(player_ship):
		if not _is_support_rescue_boarder_on_player_ship(soldier, player_ship):
			continue
		if soldier.has_method("is_jumping_value") and soldier.is_jumping_value():
			continue
		if soldier.has_method("_try_evacuate_to_home"):
			soldier.call("_try_evacuate_to_home")

	if _count_support_rescue_boarders_on_player_ship(player_ship) > 0:
		return
	for support_ship in rescue_ships:
		_cancel_support_boarding(support_ship, SUPPORT_RESCUE_BOARDING_PURPOSE)


static func finish_support_attack_boarding_if_safe(target_ship: Node, target_team: String) -> bool:
	var attack_ships := _get_support_attack_boarding_ships(target_ship)
	if attack_ships.is_empty():
		return false

	var support_boarders: Array[Node] = []
	for soldier in EntityRegistry.get_soldiers_by_ship(target_ship):
		if not is_instance_valid(soldier):
			continue
		if SoldierStateHelper.is_dead_soldier(soldier):
			continue
		var soldier_team: String = soldier.get_team_tag() if soldier.has_method("get_team_tag") else str(soldier.get("team"))
		if soldier_team == target_team:
			return false
		if _is_support_attack_boarder_on_target(soldier, target_ship, attack_ships):
			support_boarders.append(soldier)
		else:
			return false

	target_ship.boarding_capture_progress = 0.0
	for support_ship in attack_ships:
		ShipBoardingMetaHelper.set_transfer_suppressed(support_ship, true)

	for soldier in support_boarders:
		if soldier.has_method("is_jumping_value") and soldier.is_jumping_value():
			continue
		if soldier.has_method("_try_evacuate_to_home"):
			soldier.call("_try_evacuate_to_home")

	if _count_support_attack_boarders_on_target(target_ship, attack_ships) > 0:
		return true
	for support_ship in attack_ships:
		_cancel_support_boarding(support_ship, SUPPORT_BOARDING_PURPOSE)
	return true


static func _get_support_rescue_boarding_ships(player_ship: Node) -> Array[Node]:
	var rescue_ships: Array[Node] = []
	if not is_instance_valid(player_ship):
		return rescue_ships
	for support_ship in EntityRegistry.get_ships_by_team("player"):
		if not is_instance_valid(support_ship) or support_ship == player_ship:
			continue
		if not ShipAllyRoleHelper.is_support_ship(support_ship):
			continue
		if support_ship.get("is_boarding") != true:
			continue
		if support_ship.get("boarding_target") != player_ship:
			continue
		if not ShipBoardingMetaHelper.is_boarding_purpose(support_ship, SUPPORT_RESCUE_BOARDING_PURPOSE):
			continue
		rescue_ships.append(support_ship)
	return rescue_ships


static func _get_support_attack_boarding_ships(target_ship: Node) -> Array[Node]:
	var attack_ships: Array[Node] = []
	if not is_instance_valid(target_ship):
		return attack_ships
	for support_ship in EntityRegistry.get_ships_by_team("player"):
		if not is_instance_valid(support_ship):
			continue
		if not ShipAllyRoleHelper.is_support_ship(support_ship):
			continue
		if support_ship.get("is_boarding") != true:
			continue
		if support_ship.get("boarding_target") != target_ship:
			continue
		if not ShipBoardingMetaHelper.is_boarding_purpose(support_ship, SUPPORT_BOARDING_PURPOSE):
			continue
		attack_ships.append(support_ship)
	return attack_ships


static func _count_support_rescue_boarders_on_player_ship(player_ship: Node) -> int:
	var count := 0
	for soldier in EntityRegistry.get_soldiers_by_ship(player_ship):
		if _is_support_rescue_boarder_on_player_ship(soldier, player_ship):
			count += 1
	return count


static func _count_support_attack_boarders_on_target(target_ship: Node, attack_ships: Array[Node]) -> int:
	var count := 0
	for soldier in EntityRegistry.get_soldiers_by_ship(target_ship):
		if _is_support_attack_boarder_on_target(soldier, target_ship, attack_ships):
			count += 1
	return count


static func _is_support_rescue_boarder_on_player_ship(soldier: Node, player_ship: Node) -> bool:
	if not is_instance_valid(soldier) or not is_instance_valid(player_ship):
		return false
	if SoldierStateHelper.is_dead_soldier(soldier):
		return false
	var soldier_team: String = soldier.get_team_tag() if soldier.has_method("get_team_tag") else str(soldier.get("team"))
	if soldier_team != "player":
		return false
	var owned_ship: Variant = soldier.get("owned_ship") if soldier.get("owned_ship") != null else null
	if owned_ship != player_ship:
		return false
	var home_ship: Variant = soldier.get("home_ship") if soldier.get("home_ship") != null else null
	if not is_instance_valid(home_ship) or home_ship == player_ship:
		return false
	if not (home_ship is Node):
		return false
	var home_node := home_ship as Node
	if not ShipAllyRoleHelper.is_support_ship(home_node):
		return false
	if home_node.get("is_sinking") == true or home_node.get("is_dying") == true:
		return false
	return true


static func _is_support_attack_boarder_on_target(soldier: Node, target_ship: Node, attack_ships: Array[Node]) -> bool:
	if not is_instance_valid(soldier) or not is_instance_valid(target_ship):
		return false
	if SoldierStateHelper.is_dead_soldier(soldier):
		return false
	var soldier_team: String = soldier.get_team_tag() if soldier.has_method("get_team_tag") else str(soldier.get("team"))
	if soldier_team != "player":
		return false
	var owned_ship: Variant = soldier.get("owned_ship") if soldier.get("owned_ship") != null else null
	if owned_ship != target_ship:
		return false
	var home_ship: Variant = soldier.get("home_ship") if soldier.get("home_ship") != null else null
	if not is_instance_valid(home_ship) or not (home_ship is Node):
		return false
	var home_node := home_ship as Node
	if not attack_ships.has(home_node):
		return false
	if home_node.get("is_sinking") == true or home_node.get("is_dying") == true:
		return false
	return true


static func _cancel_support_boarding(support_ship: Node, expected_purpose: String) -> void:
	if not is_instance_valid(support_ship):
		return
	if not ShipBoardingMetaHelper.is_boarding_purpose(support_ship, expected_purpose):
		return
	if support_ship.has_method("_cancel_boarding"):
		support_ship.call("_cancel_boarding")
	else:
		if support_ship.get("is_boarding") != null:
			support_ship.set("is_boarding", false)
		if support_ship.get("boarding_target") != null:
			support_ship.set("boarding_target", null)
	ShipBoardingMetaHelper.remove_meta_key(support_ship, ShipBoardingMetaHelper.KEY_PURPOSE)
	ShipBoardingMetaHelper.remove_meta_key(support_ship, ShipBoardingMetaHelper.KEY_TRANSFER_SUPPRESSED)
	if support_ship.has_meta(ShipBoardingMetaHelper.KEY_SUPPORT_DEBUG_MODE):
		ShipBoardingMetaHelper.set_support_debug_mode(support_ship, ShipBoardingMetaHelper.SUPPORT_DEBUG_TRAIL)
