extends Area3D

const NavalUiTheme = preload("res://scripts/ui/naval_ui_theme.gd")
const PhysicsFrameProfiler = preload("res://scripts/debug/physics_frame_profiler.gd")

@export var interaction_range: float = 10.0
@export var hint_range: float = 38.0
@export var choice_count: int = 4
@export_enum("upgrade_choices", "repair_hull", "expand_crew_limit", "restore_crew", "minor_stat_bonus") var reward_type: String = "minor_stat_bonus"
@export_range(0.05, 1.0, 0.05) var hull_repair_ratio: float = 0.3
@export var hull_repair_minimum: float = 35.0
@export_range(1, 4, 1) var crew_limit_bonus: int = 1
@export_range(1, 4, 1) var crew_restore_count: int = 1
@export var site_label: String = "탐색 장소"
@export var completed_label: String = "탐색 완료"
@export var waterline_y: float = 0.0
@export var lock_to_waterline: bool = true
@export_range(0.05, 1.5, 0.05) var collection_fade_duration: float = 0.45

var is_collected: bool = false
var _target_player: Node3D = null
var _hint_label: Label3D = null
var _fade_tween: Tween = null


func _ready() -> void:
	add_to_group("sea_site")
	add_to_group("static_reward_site")
	if lock_to_waterline:
		global_position.y = waterline_y
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)
	_ensure_hint_label()


func _physics_process(_delta: float) -> void:
	var profile_start := PhysicsFrameProfiler.begin()
	_profiled_physics_process()
	PhysicsFrameProfiler.end("site_static_reward", profile_start)


func _profiled_physics_process() -> void:
	if not is_inside_tree():
		return
	_update_hint_visibility()
	if not is_collected:
		_try_collect_by_distance()


func _try_collect_by_distance() -> void:
	var player := _get_target_player()
	if not is_instance_valid(player):
		return
	var flat_self := Vector3(global_position.x, 0.0, global_position.z)
	var flat_player := Vector3(player.global_position.x, 0.0, player.global_position.z)
	if flat_self.distance_to(flat_player) <= interaction_range:
		_collect(player)


func _on_body_entered(body: Node3D) -> void:
	_try_collect_from_node(body)


func _on_area_entered(area: Area3D) -> void:
	_try_collect_from_node(area)


func _try_collect_from_node(node: Node) -> void:
	if is_collected:
		return
	var ship := _get_ship_from_node(node)
	if is_instance_valid(ship) and _is_flagship(ship):
		_collect(ship)


func _collect(_player_ship: Node3D) -> void:
	if is_collected:
		return
	if not _apply_site_reward(_player_ship):
		return
	is_collected = true
	if is_instance_valid(AudioManager):
		AudioManager.play_sfx("treasure_collect", null, randf_range(0.92, 1.05))
	var label := _ensure_hint_label()
	if is_instance_valid(label):
		label.text = completed_label
		label.modulate = Color(0.72, 1.0, 0.72, 0.0)
	_hide_after_collection()


func _apply_site_reward(player_ship: Node3D) -> bool:
	return SeaSiteRewardHelper.apply_reward(
		self,
		player_ship,
		reward_type,
		choice_count,
		hull_repair_ratio,
		hull_repair_minimum,
		crew_limit_bonus,
		crew_restore_count
	)


func _get_target_player() -> Node3D:
	if is_instance_valid(_target_player) and _is_flagship(_target_player):
		return _target_player
	for ship in EntityRegistry.get_ships_by_team("player"):
		if is_instance_valid(ship) and _is_flagship(ship):
			_target_player = ship as Node3D
			return _target_player
	_target_player = null
	return null


func _is_flagship(ship: Node) -> bool:
	if not is_instance_valid(ship):
		return false
	if not ship.is_in_group("player"):
		return false
	if ship.get("is_player_controlled") != null:
		return ship.get("is_player_controlled") == true
	return str(ship.name) == "PlayerShip"


func _get_ship_from_node(node: Node) -> Node3D:
	if node == null:
		return null
	if node is Node3D and _is_flagship(node):
		return node as Node3D
	var parent := node.get_parent()
	if parent is Node3D and _is_flagship(parent):
		return parent as Node3D
	if node.owner is Node3D and _is_flagship(node.owner):
		return node.owner as Node3D
	return null


func _ensure_hint_label() -> Label3D:
	if is_instance_valid(_hint_label):
		return _hint_label
	_hint_label = get_node_or_null("HintLabel") as Label3D
	if is_instance_valid(_hint_label):
		return _hint_label
	_hint_label = Label3D.new()
	_hint_label.name = "HintLabel"
	_hint_label.text = site_label
	_hint_label.position = Vector3(0.0, 2.0, 0.0)
	NavalUiTheme.style_world_hint(_hint_label, 24, Color(1.0, 0.92, 0.45, 0.0))
	_hint_label.visible = false
	add_child(_hint_label)
	return _hint_label


func _update_hint_visibility() -> void:
	if is_collected:
		if is_instance_valid(_hint_label):
			_hint_label.visible = false
		return
	var label := _ensure_hint_label()
	if not is_instance_valid(label):
		return
	var player := _get_target_player()
	if not is_instance_valid(player):
		label.visible = false
		return
	var flat_self := Vector3(global_position.x, 0.0, global_position.z)
	var flat_player := Vector3(player.global_position.x, 0.0, player.global_position.z)
	var dist := flat_self.distance_to(flat_player)
	var fade_start := interaction_range
	var alpha := clampf(1.0 - ((dist - fade_start) / maxf(1.0, hint_range - fade_start)), 0.0, 1.0)
	label.visible = alpha > 0.05
	label.text = site_label
	label.modulate = Color(1.0, 0.92, 0.45, alpha)


func _hide_after_collection() -> void:
	monitoring = false
	monitorable = false
	remove_from_group("sea_site")
	remove_from_group("static_reward_site")
	set_physics_process(false)
	_disable_collision_shapes(self)
	if is_instance_valid(_hint_label):
		_hint_label.visible = false
	_play_collection_fade()


func _play_collection_fade() -> void:
	if is_instance_valid(_fade_tween):
		_fade_tween.kill()
	var fade_targets := _collect_fade_targets(self)
	if fade_targets.is_empty():
		visible = false
		return
	_fade_tween = create_tween()
	_fade_tween.set_parallel(true)
	for target in fade_targets:
		if target is GeometryInstance3D:
			var geometry := target as GeometryInstance3D
			geometry.transparency = 0.0
			_fade_tween.tween_property(geometry, "transparency", 1.0, collection_fade_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var visual_root := get_node_or_null("Visual") as Node3D
	if is_instance_valid(visual_root):
		_fade_tween.tween_property(visual_root, "scale", visual_root.scale * 0.92, collection_fade_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_fade_tween.chain().tween_callback(func() -> void:
		visible = false
	)


func _collect_fade_targets(root: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child in root.get_children():
		if child is GeometryInstance3D:
			result.append(child)
		result.append_array(_collect_fade_targets(child))
	return result


func _disable_collision_shapes(root: Node) -> void:
	for child in root.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = true
		elif child is CollisionPolygon3D:
			(child as CollisionPolygon3D).disabled = true
		_disable_collision_shapes(child)
