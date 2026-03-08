class_name SceneGroupCache
extends RefCounted

## 한 physics frame 동안 group 조회 결과를 재사용합니다.
## 전투 중 다수의 노드가 같은 group을 반복 조회하는 비용을 줄이기 위한 캐시입니다.

static var _last_physics_frame: int = -1
static var _cached_groups: Dictionary = {}
static var _cached_first_nodes: Dictionary = {}

static func _refresh_if_needed() -> void:
	var frame := Engine.get_physics_frames()
	if frame == _last_physics_frame:
		return
	_last_physics_frame = frame
	_cached_groups.clear()
	_cached_first_nodes.clear()

static func get_nodes(tree: SceneTree, group_name: String) -> Array:
	_refresh_if_needed()
	if not _cached_groups.has(group_name):
		_cached_groups[group_name] = tree.get_nodes_in_group(group_name)
	return _cached_groups[group_name]

static func get_first(tree: SceneTree, group_name: String) -> Node:
	_refresh_if_needed()
	if not _cached_first_nodes.has(group_name):
		var nodes := get_nodes(tree, group_name)
		_cached_first_nodes[group_name] = nodes[0] if not nodes.is_empty() else null
	var node: Node = _cached_first_nodes[group_name]
	if node == null:
		return null
	if is_instance_valid(node):
		return node
	_cached_first_nodes.erase(group_name)
	return get_first(tree, group_name)
