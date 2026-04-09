extends RefCounted
class_name NodeContractHelper

static func get_team_tag(node: Node, fallback: String = "") -> String:
	if not is_instance_valid(node):
		return fallback
	if node.has_method("get_team_tag"):
		return node.get_team_tag()
	if "team" in node:
		var team_value: Variant = node.get("team")
		if team_value != null:
			return str(team_value)
	return fallback


static func is_team(node: Node, team_name: String) -> bool:
	return get_team_tag(node) == team_name


static func is_sinking_or_dying(node: Node) -> bool:
	if not is_instance_valid(node):
		return false
	if node.has_method("is_sinking_or_dying"):
		return node.is_sinking_or_dying()
	var sinking := false
	if "is_sinking" in node:
		sinking = sinking or bool(node.get("is_sinking"))
	if "is_dying" in node:
		sinking = sinking or bool(node.get("is_dying"))
	return sinking


static func get_current_state_value(node: Node) -> int:
	if not is_instance_valid(node):
		return -1
	if node.has_method("get_current_state_value"):
		return int(node.get_current_state_value())
	if "current_state" in node:
		var state_value: Variant = node.get("current_state")
		if state_value != null:
			return int(state_value)
	return -1


static func get_current_speed_value(node: Node) -> float:
	if not is_instance_valid(node):
		return 0.0
	if node.has_method("get_current_speed_value"):
		return float(node.get_current_speed_value())
	if "current_speed" in node:
		var speed_value: Variant = node.get("current_speed")
		if speed_value != null:
			return float(speed_value)
	return 0.0


static func get_owned_ship_node(node: Node) -> Node3D:
	if not is_instance_valid(node):
		return null
	if node.has_method("get_owned_ship_node"):
		return node.get_owned_ship_node()
	if "owned_ship" in node:
		var owned_ship_value: Variant = node.get("owned_ship")
		if is_instance_valid(owned_ship_value) and owned_ship_value is Node3D:
			return owned_ship_value
	return null
