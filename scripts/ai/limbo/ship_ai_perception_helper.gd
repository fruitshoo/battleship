extends RefCounted
class_name ShipAIPerceptionHelper

const KEY_TARGET_DISTANCE := "target_distance"
const KEY_PREFERRED_RANGE := "preferred_range"
const KEY_RANGE_TOLERANCE := "range_tolerance"
const KEY_RETREAT_RANGE := "retreat_range"
const KEY_LED_TARGET_POSITION := "led_target_position"


static func build_engagement_snapshot(agent_3d: Node3D, target: Node3D, default_preferred_range: float, default_range_tolerance: float, default_retreat_range: float = 0.0) -> Dictionary:
	if not is_instance_valid(agent_3d) or not is_instance_valid(target):
		return {}
	var target_distance := get_target_distance(agent_3d, target)
	return {
		KEY_TARGET_DISTANCE: target_distance,
		KEY_PREFERRED_RANGE: get_preferred_range(agent_3d, default_preferred_range),
		KEY_RANGE_TOLERANCE: get_range_tolerance(agent_3d, default_range_tolerance),
		KEY_RETREAT_RANGE: get_retreat_range(agent_3d, default_retreat_range),
		KEY_LED_TARGET_POSITION: get_led_target_position(agent_3d, target, target_distance),
	}


static func get_target_distance(agent_3d: Node3D, target: Node3D) -> float:
	if not is_instance_valid(agent_3d) or not is_instance_valid(target):
		return 0.0
	return agent_3d.global_position.distance_to(target.global_position)


static func get_hull_ratio(ship: Node) -> float:
	if not is_instance_valid(ship):
		return 1.0
	if ship.has_method("get_hull_ratio"):
		return clampf(float(ship.call("get_hull_ratio")), 0.0, 1.0)
	var max_hull := 0.0
	var hull := 0.0
	if "max_hull_hp" in ship and ship.get("max_hull_hp") != null:
		max_hull = float(ship.get("max_hull_hp"))
	if "hull_hp" in ship and ship.get("hull_hp") != null:
		hull = float(ship.get("hull_hp"))
	if max_hull <= 0.0:
		return 1.0
	return clampf(hull / max_hull, 0.0, 1.0)


static func get_ship_team_tag(ship: Node) -> String:
	if not is_instance_valid(ship):
		return ""
	if ship.has_method("get_team_tag"):
		return str(ship.call("get_team_tag"))
	if "team" in ship:
		return str(ship.get("team"))
	return ""


static func is_enemy_ship(ship: Node) -> bool:
	var team := get_ship_team_tag(ship)
	return team == "enemy" if not team.is_empty() else true


static func is_ship_gunner(ship: Node) -> bool:
	if not is_instance_valid(ship):
		return false
	if ship.has_method("is_gunner_role"):
		return ship.call("is_gunner_role") == true
	if "combat_role" in ship:
		return int(ship.get("combat_role")) == 1
	return false


static func can_ship_board(ship: Node) -> bool:
	if not is_instance_valid(ship):
		return false
	if ship.has_method("can_board_targets"):
		return ship.call("can_board_targets") == true
	if "allow_boarding" in ship:
		return ship.get("allow_boarding") == true
	return false


static func can_ship_use_fire_pot_attack(ship: Node) -> bool:
	if not is_instance_valid(ship):
		return false
	if ship.has_method("can_use_fire_pot_attack"):
		return ship.call("can_use_fire_pot_attack") == true
	return false


static func get_orbit_preferred_range(ship: Node3D, default_preferred_range: float) -> float:
	if not is_instance_valid(ship):
		return maxf(0.0, default_preferred_range)
	if ship.has_method("get_preferred_engagement_range"):
		return maxf(0.0, float(ship.call("get_preferred_engagement_range")))
	if "orbit_distance" in ship:
		return maxf(0.0, float(ship.get("orbit_distance")))
	return maxf(0.0, default_preferred_range)


static func get_preferred_range(ship: Node3D, default_preferred_range: float) -> float:
	if not is_instance_valid(ship):
		return maxf(0.0, default_preferred_range)
	if ship.has_method("get_preferred_engagement_range"):
		return maxf(0.0, float(ship.call("get_preferred_engagement_range")))
	if "preferred_combat_range" in ship:
		return maxf(0.0, float(ship.get("preferred_combat_range")))
	return maxf(0.0, default_preferred_range)


static func get_range_tolerance(ship: Node3D, default_range_tolerance: float) -> float:
	if not is_instance_valid(ship):
		return maxf(0.0, default_range_tolerance)
	if ship.has_method("get_engagement_range_tolerance"):
		return maxf(0.0, float(ship.call("get_engagement_range_tolerance")))
	if "combat_range_tolerance" in ship:
		return maxf(0.0, float(ship.get("combat_range_tolerance")))
	return maxf(0.0, default_range_tolerance)


static func get_retreat_range(ship: Node3D, default_retreat_range: float) -> float:
	if not is_instance_valid(ship):
		return maxf(0.0, default_retreat_range)
	if ship.has_method("get_retreat_engagement_distance"):
		return maxf(0.0, float(ship.call("get_retreat_engagement_distance")))
	if "retreat_distance" in ship:
		return maxf(0.0, float(ship.get("retreat_distance")))
	return maxf(0.0, default_retreat_range)


static func get_current_speed(node: Node3D) -> float:
	if not is_instance_valid(node):
		return 0.0
	if node.has_method("get_current_speed_value"):
		return maxf(0.0, float(node.call("get_current_speed_value")))
	if "current_speed" in node:
		return maxf(0.0, float(node.get("current_speed")))
	return 0.0


static func get_led_target_position(agent_3d: Node3D, target: Node3D, target_distance: float = -1.0) -> Vector3:
	if not is_instance_valid(target):
		return Vector3.ZERO
	var target_pos := target.global_position
	var distance := target_distance
	if distance < 0.0 and is_instance_valid(agent_3d):
		distance = agent_3d.global_position.distance_to(target.global_position)
	if distance < 25.0:
		return target_pos
	var target_speed := get_current_speed(target)
	if target_speed <= 0.0:
		return target_pos
	var agent_speed := 1.0
	if is_instance_valid(agent_3d) and "move_speed" in agent_3d:
		agent_speed = maxf(1.0, float(agent_3d.get("move_speed")))
	var lead_forward := Vector3(-sin(target.rotation.y), 0.0, -cos(target.rotation.y))
	var time_to_reach := minf(distance / agent_speed, 3.0)
	return target_pos + lead_forward * target_speed * time_to_reach
