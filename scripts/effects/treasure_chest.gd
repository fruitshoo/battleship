extends Node3D
const LevelManagerRegistry = preload("res://scripts/helpers/level_manager_registry.gd")
const EntityRegistry = preload("res://scripts/helpers/entity_registry.gd")
const FieldItemHelper = preload("res://scripts/effects/field_item_helper.gd")

## 보물 상자 (Treasure Chest)
## 플레이어가 닿으면 특별한 업그레이드 보상을 제공

@export var collection_range: float = 0.65
@export var magnet_range: float = 6.0
@export var magnet_speed: float = 12.0
@export_range(0.3, 4.0, 0.05) var float_speed: float = 1.35
@export_range(0.02, 0.6, 0.02) var float_height: float = 0.16
@export_range(0.05, 2.0, 0.05) var rotation_speed: float = 0.35
@export_range(-0.5, 2.0, 0.05) var waterline_offset: float = -0.12
@export_range(-0.5, 1.0, 0.05) var visual_waterline_offset: float = 0.18
@export_range(0.2, 3.0, 0.05) var wave_tilt_strength: float = 0.55
@export_range(0.03, 0.3, 0.01) var wave_sample_interval: float = 0.1

var _is_collected: bool = false
var _target_player: Node3D = null
var base_y: float = 0.0
var time_alive: float = 0.0
var _cached_ocean: Node = null
var _cached_wave_height: float = 0.0
var _cached_wave_tilt := Vector2.ZERO
var _wave_sample_timer: float = 0.0
var _float_phase: float = 0.0

@onready var visual: Node3D = $MeshInstance3D if has_node("MeshInstance3D") else self

func _ready() -> void:
	if _env_flag_enabled("BATTLESHIP_GAUNTLET_DISABLE_RECOVERY"):
		queue_free()
		return
	add_to_group("treasure_chest")
	base_y = global_position.y
	time_alive = 0.0
	_wave_sample_timer = randf_range(0.0, wave_sample_interval)
	_float_phase = randf_range(0.0, TAU)
	_cached_ocean = get_tree().get_first_node_in_group("ocean")
	if visual:
		visual.position.y = visual_waterline_offset
		if visual is GeometryInstance3D:
			(visual as GeometryInstance3D).extra_cull_margin = 1.0

func _process(delta: float) -> void:
	if _is_collected: return
	time_alive += delta
	_wave_sample_timer = maxf(0.0, _wave_sample_timer - delta)
	_apply_floating(delta)
	
	var p := _get_target_player()
	if not is_instance_valid(p):
		return
	var edge_distance: float = FieldItemHelper.get_ship_edge_distance(self, p)
	var effective_collection_range: float = collection_range
	var effective_magnet_range: float = _get_effective_magnet_range(p)
	if edge_distance <= effective_collection_range:
		_collect()
	elif edge_distance <= effective_magnet_range:
		var pull_speed: float = magnet_speed + (effective_magnet_range - maxf(edge_distance, 0.0)) * 0.55
		FieldItemHelper.move_item_toward_ship_side_anchor(self, p, pull_speed * delta)

func _collect() -> void:
	_is_collected = true
	
	# 시스템 알림
	print("[Treasure] 보물 상자 획득!")
	
	# 사운드
	if is_instance_valid(AudioManager):
		AudioManager.play_sfx("treasure_collect")
	
	# 레벨 매니저를 통해 업그레이드 메뉴 호출 (보물 상자 전용)
	var lm = LevelManagerRegistry.get_level_manager(get_tree())
	if lm and lm.has_method("_show_upgrade_ui"):
		# 보물 상자는 5개의 선택지 제공 및 특별 보너스
		lm.call_deferred("_show_upgrade_ui", 5)
	
	# 파티클 효과 (필요 시) 생성 후 제거
	queue_free()


func _get_target_player() -> Node3D:
	if is_instance_valid(_target_player) and _target_player.is_inside_tree():
		return _target_player
	_target_player = EntityRegistry.get_first_ship_by_team("player") as Node3D
	return _target_player


func _get_effective_collection_range(player_ship: Node3D) -> float:
	return collection_range if is_instance_valid(player_ship) else INF


func _get_effective_magnet_range(player_ship: Node3D) -> float:
	if not is_instance_valid(player_ship):
		return 0.0
	return maxf(magnet_range, collection_range + 2.0)


func _apply_floating(delta: float) -> void:
	var has_ocean_surface := is_instance_valid(_cached_ocean) and _cached_ocean.has_method("get_wave_height")
	if has_ocean_surface:
		if _wave_sample_timer <= 0.0:
			_sample_ocean_surface()
			_wave_sample_timer = wave_sample_interval
	var target_y := FieldItemHelper.get_floating_waterline_target_y(
		base_y,
		time_alive,
		float_speed,
		float_height,
		_float_phase,
		waterline_offset,
		_cached_wave_height,
		has_ocean_surface
	)
	position.y = lerp(position.y, target_y, 4.0 * delta)
	FieldItemHelper.apply_floating_visual_motion(visual, delta, time_alive, float_speed, _float_phase, _cached_wave_tilt, wave_tilt_strength, rotation_speed)


func _sample_ocean_surface() -> void:
	var sample := FieldItemHelper.sample_ocean_surface(self, _cached_ocean)
	_cached_wave_height = float(sample.get("height", 0.0))
	_cached_wave_tilt = sample.get("tilt", Vector2.ZERO)


func _env_flag_enabled(name: String) -> bool:
	var value := OS.get_environment(name).strip_edges().to_lower()
	return value == "1" or value == "true" or value == "yes" or value == "on"
