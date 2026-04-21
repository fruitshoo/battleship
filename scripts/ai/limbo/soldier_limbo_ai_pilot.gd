extends RefCounted


const DEFAULT_TREE_PATH := "res://resources/ai/limbo/soldier_ai_pilot.tres"
const BOARDER_TREE_PATH := "res://resources/ai/limbo/soldier_boarder_ai_pilot.tres"
const BOARDING_TREE_PATH := "res://resources/ai/limbo/soldier_boarding_ai_pilot.tres"
const RANGED_TREE_PATH := "res://resources/ai/limbo/soldier_ranged_ai_pilot.tres"
const PLAYER_NODE_NAME := "LimboAISoldierPilotPlayer"
const META_LAST_STATUS := "soldier_limbo_ai_last_status"
const META_LAST_ERROR := "soldier_limbo_ai_last_error"
const META_TREE_PATH := "soldier_limbo_ai_tree_path"
const UPDATE_MODE_MANUAL := 2


static func tick(soldier: Node, delta: float, behavior_tree_path: String = DEFAULT_TREE_PATH) -> bool:
	if not is_instance_valid(soldier):
		return false
	var resolved_tree_path: String = resolve_tree_path(soldier, behavior_tree_path)
	var player: Node = _ensure_player(soldier, resolved_tree_path)
	if not is_instance_valid(player):
		return false
	if not player.has_method("update"):
		soldier.set_meta(META_LAST_ERROR, "BTPlayer update method is unavailable")
		return false

	if soldier.has_meta(META_LAST_ERROR):
		soldier.remove_meta(META_LAST_ERROR)
	var status: Variant = player.call("update", maxf(delta, 0.0))
	soldier.set_meta(META_LAST_STATUS, status)
	return true


static func resolve_tree_path(soldier: Node, behavior_tree_path: String = DEFAULT_TREE_PATH) -> String:
	var requested_path: String = behavior_tree_path.strip_edges()
	if requested_path.is_empty():
		requested_path = DEFAULT_TREE_PATH
	if requested_path != DEFAULT_TREE_PATH:
		return requested_path
	if not is_instance_valid(soldier):
		return requested_path
	if not soldier.has_method("get_limbo_ai_default_tree_path"):
		return requested_path
	var default_path: String = str(soldier.call("get_limbo_ai_default_tree_path")).strip_edges()
	return default_path if not default_path.is_empty() else requested_path


static func is_available() -> bool:
	return ClassDB.class_exists("BTPlayer") and ClassDB.class_exists("BehaviorTree")


static func _ensure_player(soldier: Node, behavior_tree_path: String) -> Node:
	if not is_available():
		soldier.set_meta(META_LAST_ERROR, "LimboAI classes are not registered")
		return null

	var player: Node = soldier.get_node_or_null(PLAYER_NODE_NAME)
	if not is_instance_valid(player):
		player = _create_player(soldier)
	if not is_instance_valid(player):
		return null
	if not player.has_method("set_behavior_tree"):
		soldier.set_meta(META_LAST_ERROR, "%s is not a BTPlayer" % PLAYER_NODE_NAME)
		return null

	if player.get("behavior_tree") == null or str(player.get_meta(META_TREE_PATH, "")) != behavior_tree_path:
		var behavior_tree: Resource = load(behavior_tree_path)
		if behavior_tree == null:
			soldier.set_meta(META_LAST_ERROR, "failed to load behavior tree: %s" % behavior_tree_path)
			return null
		player.set("behavior_tree", behavior_tree)
		player.set_meta(META_TREE_PATH, behavior_tree_path)
	return player


static func _create_player(soldier: Node) -> Node:
	var player := ClassDB.instantiate("BTPlayer") as Node
	if not is_instance_valid(player):
		soldier.set_meta(META_LAST_ERROR, "failed to instantiate BTPlayer")
		return null

	player.name = PLAYER_NODE_NAME
	soldier.add_child(player)
	if player.has_method("set_scene_root_hint"):
		player.call("set_scene_root_hint", soldier)
	player.set("agent_node", player.get_path_to(soldier))
	player.set("update_mode", UPDATE_MODE_MANUAL)
	player.set("active", true)
	return player
