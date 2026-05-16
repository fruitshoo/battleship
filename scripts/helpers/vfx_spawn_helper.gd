extends RefCounted
class_name VfxSpawnHelper


static func snapshot_world_position(node: Node, offset: Vector3 = Vector3.ZERO) -> Variant:
	if not is_instance_valid(node) or not (node is Node3D):
		return null
	var node_3d := node as Node3D
	if not node_3d.is_inside_tree():
		return null
	var world_position := node_3d.global_position + offset
	return world_position if world_position.is_finite() else null


static func acquire_world_node3d(
	tree: SceneTree,
	scene: PackedScene,
	world_position: Vector3,
	budget_key: String = "",
	budget_max_per_frame: int = 1,
	budget_max_distance: float = -1.0
) -> Node3D:
	if not is_instance_valid(tree) or scene == null or not world_position.is_finite():
		return null
	var resolved_budget_key := budget_key.strip_edges()
	if not resolved_budget_key.is_empty():
		if not VfxBudget.allow_spawn(tree, resolved_budget_key, world_position, maxi(1, budget_max_per_frame), budget_max_distance):
			return null
	var node := ScenePool.acquire(tree, scene)
	if not is_instance_valid(node):
		return null
	tree.root.add_child(node)
	if not (node is Node3D):
		ScenePool.release(node)
		return null
	var node_3d := node as Node3D
	node_3d.global_position = world_position
	if not resolved_budget_key.is_empty() and node.has_method("set_budget_reserved"):
		node.call("set_budget_reserved")
	return node_3d


static func orient_world_node3d(node: Node3D, world_position: Vector3, look_direction: Vector3 = Vector3.ZERO) -> void:
	if not is_instance_valid(node) or not world_position.is_finite():
		return
	var next_transform := node.global_transform
	next_transform.origin = world_position
	look_direction.y = 0.0
	if look_direction.length_squared() > 0.001:
		next_transform.basis = Basis.looking_at(look_direction.normalized(), Vector3.UP)
	node.global_transform = next_transform


static func activate(node: Node) -> void:
	if is_instance_valid(node) and node.has_method("pool_activate"):
		node.call("pool_activate")
