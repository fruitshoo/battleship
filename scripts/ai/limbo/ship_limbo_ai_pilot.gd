extends RefCounted
class_name ShipLimboAIPilot


const DEFAULT_TREE_PATH := "res://resources/ai/limbo/ship_ai_pilot_skeleton.tres"
const ENEMY_GUNNER_TREE_PATH := "res://resources/ai/limbo/enemy_gunner_ai_pilot.tres"
const ENEMY_BOARDER_TREE_PATH := "res://resources/ai/limbo/enemy_boarder_ai_pilot.tres"
const ENEMY_FIREPOT_TREE_PATH := "res://resources/ai/limbo/enemy_firepot_ai_pilot.tres"
const BOSS_TREE_PATH := "res://resources/ai/limbo/boss_ship_ai_pilot.tres"
const SUPPORT_TREE_PATH := "res://resources/ai/limbo/support_ship_ai_pilot.tres"
const CAPTURED_MINION_TREE_PATH := "res://resources/ai/limbo/captured_minion_ai_pilot.tres"
const PLAYER_NODE_NAME := "LimboAIPilotPlayer"
const META_LAST_STATUS := "limbo_ai_last_status"
const META_LAST_ERROR := "limbo_ai_last_error"
const META_TREE_PATH := "limbo_ai_tree_path"
const UPDATE_MODE_MANUAL := 2


static func tick(ship: Node, delta: float, behavior_tree_path: String = DEFAULT_TREE_PATH) -> bool:
	if not is_instance_valid(ship):
		return false
	var resolved_tree_path := resolve_tree_path(ship, behavior_tree_path)
	var player := _ensure_player(ship, resolved_tree_path)
	if not is_instance_valid(player):
		return false
	if not player.has_method("update"):
		ship.set_meta(META_LAST_ERROR, "BTPlayer update method is unavailable")
		return false

	if ship.has_meta(META_LAST_ERROR):
		ship.remove_meta(META_LAST_ERROR)
	var status: Variant = player.call("update", maxf(delta, 0.0))
	ship.set_meta(META_LAST_STATUS, status)
	_apply_pilot_target(ship)
	return true


static func resolve_tree_path(ship: Node, behavior_tree_path: String = DEFAULT_TREE_PATH) -> String:
	var requested_path := behavior_tree_path.strip_edges()
	if requested_path.is_empty():
		requested_path = DEFAULT_TREE_PATH
	if requested_path != DEFAULT_TREE_PATH:
		return requested_path
	if not is_instance_valid(ship):
		return requested_path

	var ship_default_tree_path := _get_ship_default_tree_path(ship)
	if not ship_default_tree_path.is_empty() and ship_default_tree_path != DEFAULT_TREE_PATH:
		return ship_default_tree_path

	var team_tag := _get_team_tag(ship)
	if team_tag == "player":
		if ShipAllyRoleHelper.is_support_ship(ship):
			return SUPPORT_TREE_PATH
		if ShipAllyRoleHelper.is_captured_minion(ship):
			return CAPTURED_MINION_TREE_PATH
	elif team_tag == "enemy" and ship.has_method("is_gunner_role"):
		return ENEMY_GUNNER_TREE_PATH if ship.call("is_gunner_role") == true else ENEMY_BOARDER_TREE_PATH
	return requested_path


static func is_available() -> bool:
	return ClassDB.class_exists("BTPlayer") and ClassDB.class_exists("BehaviorTree")


static func get_pilot_target(ship: Node) -> Node3D:
	if not is_instance_valid(ship):
		return null
	var target_id := int(ship.get_meta(ShipAILimboKeys.META_TARGET_ID, 0))
	if target_id == 0:
		return null
	return instance_from_id(target_id) as Node3D


static func _ensure_player(ship: Node, behavior_tree_path: String) -> Node:
	if not is_available():
		ship.set_meta(META_LAST_ERROR, "LimboAI classes are not registered")
		return null

	var player := ship.get_node_or_null(PLAYER_NODE_NAME)
	if not is_instance_valid(player):
		player = _create_player(ship)
	if not is_instance_valid(player):
		return null
	if not player.has_method("set_behavior_tree"):
		ship.set_meta(META_LAST_ERROR, "%s is not a BTPlayer" % PLAYER_NODE_NAME)
		return null

	if player.get("behavior_tree") == null or str(player.get_meta(META_TREE_PATH, "")) != behavior_tree_path:
		var behavior_tree := load(behavior_tree_path)
		if behavior_tree == null:
			ship.set_meta(META_LAST_ERROR, "failed to load behavior tree: %s" % behavior_tree_path)
			return null
		player.set("behavior_tree", behavior_tree)
		player.set_meta(META_TREE_PATH, behavior_tree_path)
	return player


static func _create_player(ship: Node) -> Node:
	var player := ClassDB.instantiate("BTPlayer") as Node
	if not is_instance_valid(player):
		ship.set_meta(META_LAST_ERROR, "failed to instantiate BTPlayer")
		return null

	player.name = PLAYER_NODE_NAME
	ship.add_child(player)
	if player.has_method("set_scene_root_hint"):
		player.call("set_scene_root_hint", ship)
	player.set("agent_node", player.get_path_to(ship))
	player.set("update_mode", UPDATE_MODE_MANUAL)
	player.set("active", true)
	return player


static func _apply_pilot_target(ship: Node) -> void:
	var pilot_target := get_pilot_target(ship)
	if not is_instance_valid(pilot_target):
		return
	if "target" in ship:
		ship.set("target", pilot_target)


static func _get_team_tag(ship: Node) -> String:
	if ship.has_method("get_team_tag"):
		return str(ship.call("get_team_tag"))
	if "team" in ship:
		return str(ship.get("team"))
	return ""


static func _get_ship_default_tree_path(ship: Node) -> String:
	if not is_instance_valid(ship) or not ship.has_method("get_limbo_ai_default_tree_path"):
		return ""
	return str(ship.call("get_limbo_ai_default_tree_path")).strip_edges()
