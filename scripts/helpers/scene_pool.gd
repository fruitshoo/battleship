class_name ScenePool
extends RefCounted

const ROOT_NAME := "__ScenePoolRoot"
const STORE_META := "__scene_pool_store"
const KEY_META := "__scene_pool_key"
const PENDING_RELEASE_META := "__scene_pool_pending_release"
const DEFAULT_CAPACITY := 12

static func acquire(tree: SceneTree, scene: PackedScene) -> Node:
	if tree == null or scene == null:
		return null
	var key := scene.resource_path
	if key.is_empty():
		return scene.instantiate()
	var store := _get_store(tree)
	if store.is_empty() and _get_root_node(tree) == null:
		return scene.instantiate()
	var pool: Array = store.get(key, [])
	while not pool.is_empty():
		var node = pool.pop_back()
		if is_instance_valid(node):
			store[key] = pool
			if node.get_parent():
				node.get_parent().remove_child(node)
			_prepare_acquired_node(node)
			return node
	store[key] = pool
	var instance := scene.instantiate()
	if is_instance_valid(instance):
		instance.set_meta(KEY_META, key)
		_prepare_acquired_node(instance)
	return instance

static func release(node: Node) -> void:
	if not is_instance_valid(node):
		return
	var tree := node.get_tree()
	if tree == null or not node.has_meta(KEY_META):
		node.queue_free()
		return
	if node.has_method("pool_reset"):
		node.call("pool_reset")
	_prepare_released_node(node)
	var key := str(node.get_meta(KEY_META))
	var store := _get_store(tree)
	if store.is_empty() and _get_root_node(tree) == null:
		node.queue_free()
		return
	var pool: Array = store.get(key, [])
	var capacity := DEFAULT_CAPACITY
	if node.has_method("pool_capacity"):
		capacity = max(1, int(node.call("pool_capacity")))
	if pool.size() >= capacity:
		node.queue_free()
		return
	if node.has_meta(PENDING_RELEASE_META) and node.get_meta(PENDING_RELEASE_META) == true:
		return
	node.set_meta(PENDING_RELEASE_META, true)
	var node_id: int = node.get_instance_id()
	var pool_root := _get_root_node(tree)
	var pool_root_id: int = pool_root.get_instance_id() if is_instance_valid(pool_root) else 0
	tree.process_frame.connect(
		func() -> void:
			_finish_release_deferred(node_id, pool_root_id, key, capacity),
		CONNECT_ONE_SHOT
	)

static func release_by_instance_id(node_id: int) -> void:
	var node := NodeContractHelper.get_instance_node(node_id)
	if not is_instance_valid(node):
		return
	release(node)

static func _finish_release_deferred(node_id: int, pool_root_id: int, key: String, capacity: int) -> void:
	var node := NodeContractHelper.get_instance_node(node_id)
	var pool_root := NodeContractHelper.get_instance_node(pool_root_id)
	if not is_instance_valid(node) or not is_instance_valid(pool_root):
		return
	node.set_meta(PENDING_RELEASE_META, false)
	var deferred_store: Dictionary = pool_root.get_meta(STORE_META) if pool_root.has_meta(STORE_META) else {}
	var deferred_pool: Array = deferred_store.get(key, [])
	if deferred_pool.size() >= capacity:
		node.queue_free()
		return
	if node.get_parent():
		node.get_parent().remove_child(node)
	pool_root.add_child(node)
	deferred_pool.append(node)
	deferred_store[key] = deferred_pool
	pool_root.set_meta(STORE_META, deferred_store)

static func _get_store(tree: SceneTree) -> Dictionary:
	var root := _get_root_node(tree)
	if root == null:
		return {}
	if not root.has_meta(STORE_META):
		root.set_meta(STORE_META, {})
	return root.get_meta(STORE_META)

static func _get_root_node(tree: SceneTree) -> Node:
	if tree == null or tree.root == null:
		return null
	var root := tree.root
	var pool_root := root.get_node_or_null(ROOT_NAME)
	if pool_root != null:
		return pool_root
	pool_root = Node.new()
	pool_root.name = ROOT_NAME
	pool_root.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(pool_root)
	return pool_root

static func _prepare_acquired_node(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_INHERIT
	if node is Node3D:
		(node as Node3D).visible = true
	elif node is CanvasItem:
		(node as CanvasItem).visible = true
	if node is Area3D:
		var area := node as Area3D
		if area.is_inside_tree():
			area.set_deferred("monitoring", true)
			area.set_deferred("monitorable", true)
		else:
			area.monitoring = true
			area.monitorable = true
	if node is CollisionObject3D:
		(node as CollisionObject3D).disable_mode = CollisionObject3D.DISABLE_MODE_REMOVE

static func _prepare_released_node(node: Node) -> void:
	if node.is_inside_tree():
		node.set_deferred("process_mode", Node.PROCESS_MODE_DISABLED)
	else:
		node.process_mode = Node.PROCESS_MODE_DISABLED
	if node is Node3D:
		(node as Node3D).visible = false
	elif node is CanvasItem:
		(node as CanvasItem).visible = false
	if node is Area3D:
		var area := node as Area3D
		if area.is_inside_tree():
			area.set_deferred("monitoring", false)
			area.set_deferred("monitorable", false)
		else:
			area.monitoring = false
			area.monitorable = false
