@tool
extends "res://scripts/entities/ships/chaser_ship.gd"
class_name SupportShip

## Player support fleet ship.
## Keeps support-fleet identity in the scene instead of borrowing enemy_base_ship.tscn.

func _ready() -> void:
	team = "player"
	if ship_type.strip_edges().is_empty() or ship_type == "sekibune_melee":
		ship_type = "maengseon_ally"
	set_ally_ship_role("support_fleet")
	limbo_ai_pilot_tree_path = ShipLimboAIPilot.resolve_tree_path(self, limbo_ai_pilot_tree_path)
	super._ready()
	set_ally_ship_role("support_fleet")


func refresh_support_fleet_profile_runtime(_profile: Dictionary = {}) -> void:
	if Engine.is_editor_hint() or not is_inside_tree():
		return

	var previous_max_hull_hp: float = maxf(float(max_hull_hp), 1.0)
	var previous_hull_ratio: float = clampf(float(hull_hp) / previous_max_hull_hp, 0.0, 1.0)
	var previous_speed: float = float(current_speed)
	var previous_target: Node3D = target if is_instance_valid(target) else null
	var desired_crew_count: int = maxi(1, int(initial_crew_count))
	var soldiers_node := get_soldiers_container()
	if is_instance_valid(soldiers_node):
		desired_crew_count = maxi(1, soldiers_node.get_child_count())

	var stats := load_ship_stats(ship_type)
	if stats.is_empty():
		return

	ShipBlueprintHelper.apply_chaser_stats(self, stats)
	_load_enemy_crew_composition_from_stats(stats)
	_apply_combat_profile_from_stats(stats)
	_apply_formation_role_profile()
	_rebuild_runtime_hull(stats)
	_cache_hull_references(self)
	_refresh_collision_bounds_from_hull()

	if not has_cannons:
		_remove_all_cannons()
	else:
		_equip_minion_cannons()

	initial_crew_count = clampi(desired_crew_count, 1, max(1, max_crew))
	_reconcile_support_crew_count(initial_crew_count)
	hull_hp = minf(max_hull_hp, maxf(1.0, max_hull_hp * previous_hull_ratio))
	current_speed = previous_speed
	_last_ai_speed = previous_speed
	if is_instance_valid(previous_target):
		target = previous_target
	elif has_method("_find_player"):
		_find_player()

	set_ally_ship_role("support_fleet")
	if has_method("add_to_group"):
		add_to_group("captured_minion")
	EntityRegistry.register_captured_minion(self)
	_apply_minion_visuals()
	_refresh_deck_light()


func _rebuild_runtime_hull(stats: Dictionary) -> void:
	for child in get_children():
		if str(child.name).contains("Hull"):
			remove_child(child)
			child.queue_free()
	var runtime_hull_scene: PackedScene = ShipBlueprintHelper.load_hull_scene(ship_type, hull_scene, stats)
	if not is_instance_valid(runtime_hull_scene):
		return
	var hull_inst = runtime_hull_scene.instantiate()
	add_child(hull_inst)


func _reconcile_support_crew_count(target_count: int) -> void:
	var soldiers_node := get_soldiers_container()
	if not is_instance_valid(soldiers_node):
		return
	while soldiers_node.get_child_count() > target_count:
		var trailing_soldier := soldiers_node.get_child(soldiers_node.get_child_count() - 1)
		if is_instance_valid(trailing_soldier):
			soldiers_node.remove_child(trailing_soldier)
			trailing_soldier.queue_free()
		else:
			break
	while soldiers_node.get_child_count() < target_count:
		_spawn_one_soldier(team)
