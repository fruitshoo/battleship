extends RefCounted
class_name ShipLimboAIPilot

const ShipAILimboKeys = preload("res://scripts/ai/limbo/ship_ai_limbo_keys.gd")

const DEFAULT_TREE_PATH := "res://resources/ai/limbo/ship_ai_pilot_skeleton.tres"
const PLAYER_NODE_NAME := "LimboAIPilotPlayer"
const META_LAST_STATUS := "limbo_ai_last_status"
const META_LAST_ERROR := "limbo_ai_last_error"
const META_TREE_PATH := "limbo_ai_tree_path"
const UPDATE_MODE_MANUAL := 2


static func tick(ship: Node, delta: float, behavior_tree_path: String = DEFAULT_TREE_PATH) -> bool:
	if not is_instance_valid(ship):
		return false
	var player := _ensure_player(ship, behavior_tree_path)
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
