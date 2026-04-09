class_name EntityRegistry
extends RefCounted

static var _ships: Array[Node] = []
static var _soldiers: Array[Node] = []


static func register_ship(ship: Node) -> void:
	if not is_instance_valid(ship):
		return
	if not _ships.has(ship):
		_ships.append(ship)


static func unregister_ship(ship: Node) -> void:
	_unregister_node(_ships, ship)


static func register_soldier(soldier: Node) -> void:
	if not is_instance_valid(soldier):
		return
	if not _soldiers.has(soldier):
		_soldiers.append(soldier)


static func unregister_soldier(soldier: Node) -> void:
	_unregister_node(_soldiers, soldier)


static func get_ships() -> Array:
	return _compact_nodes(_ships)


static func get_soldiers() -> Array:
	return _compact_nodes(_soldiers)


static func count_ships() -> int:
	return get_ships().size()


static func count_soldiers() -> int:
	return get_soldiers().size()


static func _unregister_node(collection: Array, node: Node) -> void:
	if node == null:
		return
	var index := collection.find(node)
	if index != -1:
		collection.remove_at(index)


static func _compact_nodes(collection: Array) -> Array:
	for index in range(collection.size() - 1, -1, -1):
		if not is_instance_valid(collection[index]):
			collection.remove_at(index)
	return collection.duplicate()
