extends RefCounted
class_name HudSoldierDebugHelper


static func format_soldier_limbo_panel_text(label: String, soldier: Node3D, soldier_snapshot: Dictionary, focus_reason: String = "") -> String:
	if not is_instance_valid(soldier):
		return "%s: 없음" % label
	var soldier_name: String = str(soldier_snapshot.get("name", soldier.name)).strip_edges()
	if soldier_name.is_empty():
		soldier_name = soldier.name
	var role_name: String = str(soldier_snapshot.get("role", "")).strip_edges()
	if not role_name.is_empty():
		soldier_name = "%s (%s)" % [soldier_name, role_name]
	var limbo: Dictionary = soldier_snapshot.get("limbo", {})
	var state_name: String = str(soldier_snapshot.get("state", "")).strip_edges()
	var boarding_status: String = str(soldier_snapshot.get("boarding_status", "")).strip_edges()
	var boarding_status_text: String = boarding_status
	match boarding_status.to_lower():
		"on_deck":
			boarding_status_text = "on deck"
		"boarding":
			boarding_status_text = "away team"
		"returning":
			boarding_status_text = "returning home"
		"stranded":
			boarding_status_text = "cut off"
	if limbo.is_empty() or limbo.get("enabled", false) != true:
		var manual_details: Array[String] = []
		if not state_name.is_empty():
			manual_details.append("state %s" % state_name)
		if not focus_reason.is_empty():
			manual_details.append("focus %s" % focus_reason)
		return "%s: %s | 수동/비활성\n%s" % [
			label,
			soldier_name,
			" | ".join(manual_details) if not manual_details.is_empty() else "state 없음",
		]
	var tree_path: String = str(limbo.get("tree_path", "")).strip_edges()
	var tree_name: String = tree_path.get_file().get_basename() if not tree_path.is_empty() else "-"
	var details: Array[String] = []
	if not state_name.is_empty():
		details.append("state %s" % state_name)
	var mode_name: String = str(limbo.get("mode", "")).strip_edges()
	if not mode_name.is_empty():
		details.append("mode %s" % mode_name)
	if not focus_reason.is_empty():
		details.append("focus %s" % focus_reason)
	var target_name: String = str(soldier_snapshot.get("target_name", "")).strip_edges()
	if not target_name.is_empty():
		details.append("target %s" % target_name)
	if not boarding_status_text.is_empty():
		details.append("boarding %s" % boarding_status_text)
	var target_distance: float = float(limbo.get("target_distance", -1.0))
	if target_distance >= 0.0:
		details.append("%.1fm" % target_distance)
	var reason_text: String = str(limbo.get("reason", "")).strip_edges()
	match reason_text:
		"target_in_range":
			reason_text = "in range"
		"target_visible":
			reason_text = "closing"
	if not reason_text.is_empty():
		details.append("why %s" % reason_text)
	var error_text: String = str(limbo.get("error", "")).strip_edges()
	if not error_text.is_empty():
		details.append("err %s" % error_text)
	return "%s: %s | tree %s\n%s" % [
		label,
		soldier_name,
		tree_name,
		" | ".join(details) if not details.is_empty() else "state 없음",
	]


static func find_focus_player_soldier(player_ship: Node3D, focused_enemy_ship: Node3D = null) -> Dictionary:
	if not is_instance_valid(player_ship):
		return {"soldier": null, "reason": ""}
	var away_team_soldier: Node3D = null
	var away_team_focus_match: Node3D = null
	var away_team_distance_sq: float = INF
	var away_team_focus_distance_sq: float = INF
	var returning_soldier: Node3D = null
	var returning_distance_sq: float = INF
	for candidate_variant in EntityRegistry.get_soldiers_by_team("player"):
		var candidate := candidate_variant as Node3D
		if not is_instance_valid(candidate):
			continue
		if SoldierStateHelper.is_dead_soldier(candidate):
			continue
		var home_ship: Node3D = candidate.call("get_home_ship_node") as Node3D if candidate.has_method("get_home_ship_node") else candidate.get("home_ship")
		if home_ship != player_ship:
			continue
		var owned_ship: Node3D = candidate.call("get_owned_ship_node") as Node3D if candidate.has_method("get_owned_ship_node") else candidate.get("owned_ship")
		var boarding_status := str(candidate.call("get_boarding_status_value")).strip_edges().to_lower() if candidate.has_method("get_boarding_status_value") else str(candidate.get("boarding_status")).strip_edges().to_lower()
		var planar_delta := Vector2(
			candidate.global_position.x - player_ship.global_position.x,
			candidate.global_position.z - player_ship.global_position.z
		)
		var dist_sq: float = planar_delta.length_squared()
		if is_instance_valid(owned_ship) and owned_ship != player_ship and (boarding_status == "boarding" or boarding_status == "stranded"):
			if is_instance_valid(focused_enemy_ship) and owned_ship == focused_enemy_ship:
				if dist_sq < away_team_focus_distance_sq:
					away_team_focus_distance_sq = dist_sq
					away_team_focus_match = candidate
			elif dist_sq < away_team_distance_sq:
				away_team_distance_sq = dist_sq
				away_team_soldier = candidate
		elif boarding_status == "returning" and dist_sq < returning_distance_sq:
			returning_distance_sq = dist_sq
			returning_soldier = candidate
	if is_instance_valid(away_team_focus_match):
		away_team_soldier = away_team_focus_match
	if is_instance_valid(away_team_soldier):
		var away_ship: Node3D = away_team_soldier.call("get_owned_ship_node") as Node3D if away_team_soldier.has_method("get_owned_ship_node") else away_team_soldier.get("owned_ship")
		var away_reason := "away team"
		if is_instance_valid(away_ship) and away_ship != player_ship:
			away_reason = "%s -> %s" % [away_reason, away_ship.name]
		return {"soldier": away_team_soldier, "reason": away_reason}
	if is_instance_valid(returning_soldier):
		return {"soldier": returning_soldier, "reason": "returning home -> %s" % player_ship.name}
	var deck_soldier := _find_nearest_alive_soldier_on_ship(player_ship, "player")
	return {"soldier": deck_soldier, "reason": "home deck"} if is_instance_valid(deck_soldier) else {"soldier": null, "reason": ""}


static func find_focus_enemy_soldier(player_ship: Node3D, focused_enemy_ship: Node3D) -> Dictionary:
	if not is_instance_valid(player_ship):
		return {"soldier": null, "reason": ""}
	var deck_boarder: Node3D = _find_nearest_alive_soldier_on_ship(player_ship, "enemy")
	if is_instance_valid(deck_boarder):
		return {"soldier": deck_boarder, "reason": "boarding our deck"}
	if is_instance_valid(focused_enemy_ship):
		var target_ship_soldier: Node3D = _find_nearest_alive_soldier_on_ship(focused_enemy_ship, "enemy")
		if is_instance_valid(target_ship_soldier):
			return {"soldier": target_ship_soldier, "reason": "crew on -> %s" % focused_enemy_ship.name}
	var nearest_soldier: Node3D = _find_nearest_alive_enemy_soldier_global(player_ship)
	return {"soldier": nearest_soldier, "reason": "nearby contact"} if is_instance_valid(nearest_soldier) else {"soldier": null, "reason": ""}


static func _find_nearest_alive_soldier_on_ship(ship: Node3D, team_name: String) -> Node3D:
	if not is_instance_valid(ship):
		return null
	var nearest_soldier: Node3D = null
	var nearest_distance_sq: float = INF
	for candidate_variant in EntityRegistry.get_soldiers_by_ship(ship):
		var candidate := candidate_variant as Node3D
		if not is_instance_valid(candidate):
			continue
		if NodeContractHelper.get_team_tag(candidate) != team_name:
			continue
		if SoldierStateHelper.is_dead_soldier(candidate):
			continue
		var planar_delta := Vector2(
			candidate.global_position.x - ship.global_position.x,
			candidate.global_position.z - ship.global_position.z
		)
		var dist_sq: float = planar_delta.length_squared()
		if dist_sq < nearest_distance_sq:
			nearest_distance_sq = dist_sq
			nearest_soldier = candidate
	return nearest_soldier


static func _find_nearest_alive_enemy_soldier_global(reference_ship: Node3D) -> Node3D:
	if not is_instance_valid(reference_ship):
		return null
	var nearest_soldier: Node3D = null
	var nearest_distance_sq: float = INF
	for candidate_variant in EntityRegistry.get_soldiers_by_team("enemy"):
		var candidate := candidate_variant as Node3D
		if not is_instance_valid(candidate):
			continue
		if SoldierStateHelper.is_dead_soldier(candidate):
			continue
		var planar_delta := Vector2(
			candidate.global_position.x - reference_ship.global_position.x,
			candidate.global_position.z - reference_ship.global_position.z
		)
		var dist_sq: float = planar_delta.length_squared()
		if dist_sq < nearest_distance_sq:
			nearest_distance_sq = dist_sq
			nearest_soldier = candidate
	return nearest_soldier
