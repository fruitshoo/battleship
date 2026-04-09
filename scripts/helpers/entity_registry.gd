class_name EntityRegistry
extends RefCounted

static var _ships: Array[Node] = []
static var _soldiers: Array[Node] = []
static var _projectiles: Array[Node] = []
static var _captured_minions: Array[Node] = []
static var _soldiers_by_ship: Dictionary = {}


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
	_register_soldier_ship_bucket(soldier, soldier.get("owned_ship"))


static func unregister_soldier(soldier: Node) -> void:
	_unregister_soldier_ship_bucket(soldier, soldier.get("owned_ship"))
	_unregister_node(_soldiers, soldier)


static func move_soldier_ship(soldier: Node, old_ship: Node, new_ship: Node) -> void:
	if not is_instance_valid(soldier):
		return
	_unregister_soldier_ship_bucket(soldier, old_ship)
	_register_soldier_ship_bucket(soldier, new_ship)


static func get_ships() -> Array:
	return _compact_nodes(_ships)


static func register_captured_minion(ship: Node) -> void:
	if not is_instance_valid(ship):
		return
	if not _captured_minions.has(ship):
		_captured_minions.append(ship)


static func unregister_captured_minion(ship: Node) -> void:
	_unregister_node(_captured_minions, ship)


static func get_captured_minions() -> Array:
	return _compact_nodes(_captured_minions)


static func count_captured_minions() -> int:
	return get_captured_minions().size()


static func get_soldiers() -> Array:
	return _compact_nodes(_soldiers)


static func get_soldiers_by_team(team_name: String) -> Array:
	var normalized_team := team_name.strip_edges().to_lower()
	if normalized_team.is_empty():
		return get_soldiers()
	var filtered: Array = []
	for soldier in get_soldiers():
		if _matches_team(soldier, normalized_team):
			filtered.append(soldier)
	return filtered


static func get_soldiers_by_ship(ship: Node) -> Array:
	if not is_instance_valid(ship):
		return []
	var ship_id: int = ship.get_instance_id()
	var bucket: Array = _soldiers_by_ship.get(ship_id, [])
	return _compact_nodes(bucket)


static func count_soldiers_by_ship(ship: Node) -> int:
	return get_soldiers_by_ship(ship).size()


static func count_ships() -> int:
	return get_ships().size()


static func count_soldiers() -> int:
	return get_soldiers().size()


static func register_projectile(projectile: Node) -> void:
	if not is_instance_valid(projectile):
		return
	if not _projectiles.has(projectile):
		_projectiles.append(projectile)


static func unregister_projectile(projectile: Node) -> void:
	_unregister_node(_projectiles, projectile)


static func get_projectiles() -> Array:
	return _compact_nodes(_projectiles)


static func count_projectiles() -> int:
	return get_projectiles().size()


static func get_ships_by_team(team_name: String) -> Array:
	var normalized_team := team_name.strip_edges().to_lower()
	if normalized_team.is_empty():
		return get_ships()
	var filtered: Array = []
	for ship in get_ships():
		if _matches_team(ship, normalized_team):
			filtered.append(ship)
	return filtered


static func get_first_ship_by_team(team_name: String) -> Node:
	var ships := get_ships_by_team(team_name)
	return ships[0] if not ships.is_empty() else null


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


static func _register_soldier_ship_bucket(soldier: Node, ship: Node) -> void:
	if not is_instance_valid(soldier) or not is_instance_valid(ship):
		return
	var ship_id: int = ship.get_instance_id()
	var bucket: Array = _soldiers_by_ship.get(ship_id, [])
	if not bucket.has(soldier):
		bucket.append(soldier)
	_soldiers_by_ship[ship_id] = bucket


static func _unregister_soldier_ship_bucket(soldier: Node, ship: Node) -> void:
	if not is_instance_valid(soldier) or not is_instance_valid(ship):
		return
	var ship_id: int = ship.get_instance_id()
	if not _soldiers_by_ship.has(ship_id):
		return
	var bucket: Array = _soldiers_by_ship[ship_id]
	_unregister_node(bucket, soldier)
	if bucket.is_empty():
		_soldiers_by_ship.erase(ship_id)
	else:
		_soldiers_by_ship[ship_id] = bucket


static func _matches_team(node: Node, normalized_team: String) -> bool:
	if not is_instance_valid(node):
		return false
	var team_value: Variant = node.get("team")
	if team_value != null:
		return str(team_value).strip_edges().to_lower() == normalized_team
	return node.is_in_group(normalized_team)
