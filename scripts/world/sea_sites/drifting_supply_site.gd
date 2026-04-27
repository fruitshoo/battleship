extends Area3D

const NavalUiTheme = preload("res://scripts/ui/naval_ui_theme.gd")

@export var collection_range: float = 9.0
@export var hint_range: float = 34.0
@export var choice_count: int = 4
@export_enum("upgrade_choices", "repair_hull", "train_crew", "expand_crew_limit", "restore_crew", "minor_stat_bonus") var reward_type: String = "repair_hull"
@export_range(0.05, 1.0, 0.05) var hull_repair_ratio: float = 0.28
@export var hull_repair_minimum: float = 35.0
@export var crew_xp_amount: float = 45.0
@export_range(1, 4, 1) var crew_limit_bonus: int = 1
@export_range(1, 4, 1) var crew_restore_count: int = 1
@export var waterline_offset: float = 0.28
@export var float_speed: float = 1.35
@export var float_height: float = 0.24
@export var rotation_speed: float = 0.12
@export_range(0.03, 0.3) var wave_sample_interval: float = 0.12

var is_collected: bool = false
var _target_player: Node3D = null
var _cached_ocean: Node = null
var _cached_wave_height: float = 0.0
var _cached_wave_tilt := Vector2.ZERO
var _wave_sample_timer: float = 0.0
var _float_phase: float = 0.0
var _hint_label: Label3D = null

@onready var visual: Node3D = $Visual if has_node("Visual") else self


func _ready() -> void:
	add_to_group("sea_site")
	add_to_group("drifting_supply_site")
	_cached_ocean = get_tree().get_first_node_in_group("ocean")
	_float_phase = randf_range(0.0, TAU)
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)
	_ensure_hint_label()


func _physics_process(delta: float) -> void:
	if is_collected or not is_inside_tree():
		return
	_wave_sample_timer = maxf(0.0, _wave_sample_timer - delta)
	_apply_floating(delta)
	_update_hint_visibility()
	_try_collect_by_distance()


func _apply_floating(delta: float) -> void:
	var time := Time.get_ticks_msec() * 0.001
	var target_y := waterline_offset + sin((time * float_speed) + _float_phase) * float_height
	if is_instance_valid(_cached_ocean) and _cached_ocean.has_method("get_wave_height"):
		if _wave_sample_timer <= 0.0:
			_sample_ocean_surface()
			_wave_sample_timer = wave_sample_interval
		target_y += _cached_wave_height
	global_position.y = lerpf(global_position.y, target_y, 3.6 * delta)

	if is_instance_valid(visual):
		visual.rotation.y += rotation_speed * delta
		var target_pitch: float = clampf(_cached_wave_tilt.y * 0.6, -0.28, 0.28)
		var target_roll: float = clampf(-_cached_wave_tilt.x * 0.6, -0.28, 0.28)
		target_pitch += sin((time * float_speed * 1.4) + _float_phase) * 0.04
		target_roll += sin((time * float_speed * 1.1) + _float_phase * 0.8) * 0.08
		visual.rotation.x = lerp_angle(visual.rotation.x, target_pitch, 3.8 * delta)
		visual.rotation.z = lerp_angle(visual.rotation.z, target_roll, 3.8 * delta)


func _sample_ocean_surface() -> void:
	if not is_instance_valid(_cached_ocean) or not _cached_ocean.has_method("get_wave_height"):
		_cached_wave_height = 0.0
		_cached_wave_tilt = Vector2.ZERO
		return
	var sample_distance := 1.25
	var center := global_position
	var center_height: float = float(_cached_ocean.get_wave_height(center))
	var right_height: float = float(_cached_ocean.get_wave_height(center + Vector3(sample_distance, 0.0, 0.0)))
	var forward_height: float = float(_cached_ocean.get_wave_height(center + Vector3(0.0, 0.0, sample_distance)))
	_cached_wave_height = center_height
	_cached_wave_tilt = Vector2(
		(right_height - center_height) / sample_distance,
		(forward_height - center_height) / sample_distance
	)


func _try_collect_by_distance() -> void:
	var player := _get_target_player()
	if not is_instance_valid(player):
		return
	var flat_self := Vector3(global_position.x, 0.0, global_position.z)
	var flat_player := Vector3(player.global_position.x, 0.0, player.global_position.z)
	if flat_self.distance_to(flat_player) <= collection_range:
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
		AudioManager.play_sfx("treasure_collect", null, randf_range(1.0, 1.15))
	if is_instance_valid(_hint_label):
		_hint_label.visible = false
	if is_instance_valid(visual):
		var tween := create_tween()
		tween.tween_property(visual, "scale", Vector3.ZERO, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tween.tween_callback(queue_free)
	else:
		queue_free()


func _apply_site_reward(player_ship: Node3D) -> bool:
	return SeaSiteRewardHelper.apply_reward(
		self,
		player_ship,
		reward_type,
		choice_count,
		hull_repair_ratio,
		hull_repair_minimum,
		crew_xp_amount,
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
	_hint_label.text = "표류 보급품"
	_hint_label.position = Vector3(0.0, 1.55, 0.0)
	NavalUiTheme.style_world_hint(_hint_label, 24, Color(1.0, 0.92, 0.45, 0.0))
	_hint_label.visible = false
	add_child(_hint_label)
	return _hint_label


func _update_hint_visibility() -> void:
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
	var alpha := clampf(1.0 - ((dist - collection_range) / maxf(1.0, hint_range - collection_range)), 0.0, 1.0)
	label.visible = alpha > 0.05
	label.modulate = Color(1.0, 0.92, 0.45, alpha)
