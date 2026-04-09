class_name LevelManagerRegistry
extends RefCounted

static var _level_manager: Node = null


static func register_level_manager(level_manager: Node) -> void:
	if not is_instance_valid(level_manager):
		return
	_level_manager = level_manager


static func unregister_level_manager(level_manager: Node) -> void:
	if _level_manager == level_manager:
		_level_manager = null


static func get_level_manager(tree: SceneTree = null) -> Node:
	if is_instance_valid(_level_manager):
		return _level_manager
	if not is_instance_valid(tree):
		return null
	var level_manager := tree.root.find_child("LevelManager", true, false)
	if is_instance_valid(level_manager):
		_level_manager = level_manager
		return level_manager
	return null
