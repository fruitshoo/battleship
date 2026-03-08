class_name HitTargetResolver
extends RefCounted

## 투사체가 맞은 노드에서 실제 함선 루트를 안전하게 찾아냅니다.

static func resolve_ship_from_node(node: Node, max_depth: int = 6) -> Node3D:
	var current: Node = node
	var depth := 0
	while current and depth <= max_depth:
		if current is Node3D:
			var ship := current as Node3D
			if ship.is_in_group("player") or ship.is_in_group("enemy"):
				return ship
			
			var team_tag = resolve_team_tag(ship)
			var looks_like_ship = ship.is_in_group("ships") \
				or "hull_hp" in ship \
				or "max_hull_hp" in ship \
				or "is_sinking" in ship
			if not team_tag.is_empty() and looks_like_ship:
				return ship
		current = current.get_parent()
		depth += 1
	return null

static func resolve_team_tag(node: Node) -> String:
	if not is_instance_valid(node):
		return ""
	if "team" in node:
		var team_val = str(node.get("team"))
		if team_val == "player" or team_val == "enemy":
			return team_val
	if node.is_in_group("player"):
		return "player"
	if node.is_in_group("enemy"):
		return "enemy"
	return ""
