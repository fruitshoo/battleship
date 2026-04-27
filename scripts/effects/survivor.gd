extends Area3D
const NavalUiTheme = preload("res://scripts/ui/naval_ui_theme.gd")
const RESCUE_CALL_LABEL_NAME := "RescueCallLabel"
const RESCUE_CALL_LINES: Array[String] = [
	"구해줘!",
	"여기야!",
	"살려줘!",
	"배로 올려줘!",
]

## 생존자(Survivor) 시스템
## 적함 침몰 시 발생하며, 플레이어가 다가가면 자석처럼 끌려와 병사로 합류함

@export var base_magnet_radius: float = 8.0 # 기본 자석 효과 범위
@export var magnet_speed: float = 7.5 # 끌려가는 기본 속도
@export var float_speed: float = 1.5 # 둥실거리는 속도
@export var float_height: float = 0.2 # 둥실거리는 진폭
@export var rotation_speed: float = 0.5 # 회전 속도
@export_range(-0.5, 2.0, 0.05) var waterline_offset: float = -0.05
@export_range(-0.5, 1.0, 0.05) var visual_waterline_offset: float = 0.22
@export_range(0.2, 3.0, 0.05) var wave_tilt_strength: float = 0.7
@export_range(0.5, 8.0, 0.1) var rescue_call_interval_min: float = 2.6
@export_range(0.5, 10.0, 0.1) var rescue_call_interval_max: float = 5.2
@export_range(0.4, 4.0, 0.1) var rescue_call_duration: float = 2.0
@export var rescue_contact_margin: float = 0.7
@export var rescue_finish_duration: float = 0.32

var target_player: Node3D = null
var current_magnet_speed: float = 0.0
var base_y: float = 0.0
var time_alive: float = 0.0
var is_collected: bool = false
var _cached_ocean: Node = null
var _cached_um: Node = null
var _cached_wave_height: float = 0.0
var _cached_wave_tilt := Vector2.ZERO
var _wave_sample_timer: float = 0.0
@export_range(0.03, 0.3) var wave_sample_interval: float = 0.1
@export_range(0.05, 0.5) var player_search_interval: float = 0.2
var _player_search_timer: float = 0.0
var _rescue_call_timer: float = 0.0
var _rescue_call_visible_timer: float = 0.0
var _rescue_call_label: Label3D = null
var _float_phase: float = 0.0

@onready var visual = $MeshInstance3D if has_node("MeshInstance3D") else self

func _ready() -> void:
	if _env_flag_enabled("BATTLESHIP_GAUNTLET_DISABLE_RECOVERY"):
		ScenePool.release(self)
		return
	# 획득 이벤트 연결 (한 번만 수행)
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)
	pool_reset()

func pool_capacity() -> int:
	return 60

func pool_reset() -> void:
	time_alive = 0.0
	is_collected = false
	is_expiring = false
	target_player = null
	current_magnet_speed = 0.0
	_player_search_timer = randf_range(0.0, player_search_interval)
	_rescue_call_timer = randf_range(0.2, 0.8)
	_rescue_call_visible_timer = 0.0
	_hide_rescue_call()
	_float_phase = randf_range(0.0, TAU)
	
	base_y = global_position.y
	
	# 파란색 캡슐 이미지 설정 (병사 캐릭터와 동일하게)
	if visual and visual is MeshInstance3D:
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.4, 0.8) # Blue (Player Team Color)
		mat.emission_enabled = true
		mat.emission = Color(0.2, 0.4, 0.8)
		mat.emission_energy_multiplier = 0.5
		visual.set_surface_override_material(0, mat)
		visual.position.y = visual_waterline_offset
		
		# 초기 등장 페이드인 및 스케일 업
		visual.scale = Vector3.ZERO
		var tween = create_tween().set_parallel(true)
		tween.tween_property(visual, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		
		# 컬링 방지 마진 추가
		visual.extra_cull_margin = 1.0
		
	# OceanPlane 캐싱
	_cached_ocean = get_tree().get_first_node_in_group("ocean")
	_cached_um = get_node_or_null("/root/UpgradeManager")
	_player_search_timer = randf_range(0.0, player_search_interval)
	_ensure_rescue_call_label()


@export var lifetime: float = 90.0 # 소멸 시간 (초, 생존자는 조금 더 길게)
var is_expiring: bool = false # 소멸 진행 중 여부

func _physics_process(delta: float) -> void:
	if is_collected or not is_inside_tree():
		return
	time_alive += delta
	_wave_sample_timer = maxf(0.0, _wave_sample_timer - delta)
	_player_search_timer = maxf(0.0, _player_search_timer - delta)
	_update_rescue_call(delta)
	
	if not is_expiring and time_alive > lifetime:
		_expire_and_free()
		
	if is_expiring:
		return

	if is_instance_valid(target_player) and NodeContractHelper.is_sinking_or_dying(target_player):
		target_player = null
	if not is_instance_valid(target_player) and _player_search_timer <= 0.0:
		_player_search_timer = player_search_interval
		_find_target_player()
	
	if is_instance_valid(target_player) and target_player.is_inside_tree():
		var dist: float = global_position.distance_to(target_player.global_position)
		var current_radius: float = _get_current_magnet_radius()
		var magnet_lock_radius: float = current_radius * 1.35
		var within_pull_zone: bool = dist <= current_radius or (current_magnet_speed > 0.1 and dist <= magnet_lock_radius)
		if within_pull_zone:
			# 자석 효과: 거리가 가까울수록 더 빠르게 가속
			var ship_speed_bonus: float = 0.0
			ship_speed_bonus = maxf(0.0, NodeContractHelper.get_current_speed_value(target_player)) * 0.75
			var pull_target: Vector3 = FieldItemHelper.get_ship_side_anchor(self, target_player, false)
			var pull_distance: float = global_position.distance_to(pull_target)
			var desired_magnet_speed: float = magnet_speed + ship_speed_bonus + (16.0 / max(pull_distance, 0.8))
			current_magnet_speed = move_toward(current_magnet_speed, desired_magnet_speed, 24.0 * delta)
			FieldItemHelper.move_item_toward_ship_side_anchor(self, target_player, current_magnet_speed * delta)
			_apply_floating(delta)
			
			# 근거리 자동 획득 (충돌 미감지 보완)
			if _is_close_enough_to_collect(target_player):
				_collect_by_proximity()
		else:
			current_magnet_speed = 0.0
			_apply_floating(delta)
	else:
		if is_instance_valid(target_player) and not target_player.is_inside_tree():
			target_player = null
		_apply_floating(delta)


func _expire_and_free() -> void:
	is_expiring = true
	is_collected = true # 획득 방지
	_hide_rescue_call()
	var tween = create_tween().set_parallel(true)
	# 천천히 가라앉으며 사라짐 (깜빡임 대신)
	tween.tween_property(self , "position:y", position.y - 2.0, 4.0)
	if visual:
		tween.tween_property(visual, "scale", Vector3.ZERO, 4.0)
	var self_id: int = get_instance_id()
	tween.chain().tween_callback(func(): ScenePool.release_by_instance_id(self_id))


func _env_flag_enabled(name: String) -> bool:
	var value := OS.get_environment(name).strip_edges().to_lower()
	return value == "1" or value == "true" or value == "yes" or value == "on"


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
	# 수면을 살짝 늦게 따라가야 물 위에 떠 있는 느낌이 난다.
	position.y = lerp(position.y, target_y, 4.0 * delta)
	FieldItemHelper.apply_floating_visual_motion(visual, delta, time_alive, float_speed, _float_phase, _cached_wave_tilt, wave_tilt_strength, rotation_speed)


func _sample_ocean_surface() -> void:
	if not is_instance_valid(_cached_ocean) or not _cached_ocean.has_method("get_wave_height"):
		_cached_wave_height = 0.0
		_cached_wave_tilt = Vector2.ZERO
		return
	var sample := FieldItemHelper.sample_ocean_surface(self, _cached_ocean)
	_cached_wave_height = float(sample.get("height", 0.0))
	_cached_wave_tilt = sample.get("tilt", Vector2.ZERO)


func _ensure_rescue_call_label() -> Label3D:
	if is_instance_valid(_rescue_call_label):
		return _rescue_call_label
	_rescue_call_label = get_node_or_null(RESCUE_CALL_LABEL_NAME) as Label3D
	if _rescue_call_label != null:
		return _rescue_call_label
	_rescue_call_label = Label3D.new()
	_rescue_call_label.name = RESCUE_CALL_LABEL_NAME
	_rescue_call_label.position = Vector3(0.0, 2.15, 0.0)
	NavalUiTheme.style_world_callout(_rescue_call_label, 84, Color(1.0, 0.96, 0.58, 0.0))
	_rescue_call_label.visible = false
	add_child(_rescue_call_label)
	return _rescue_call_label


func _update_rescue_call(delta: float) -> void:
	if is_collected or is_expiring:
		_hide_rescue_call()
		return
	var label := _ensure_rescue_call_label()
	if label == null:
		return
	if _rescue_call_visible_timer > 0.0:
		_rescue_call_visible_timer = maxf(0.0, _rescue_call_visible_timer - delta)
		var fade_in: float = clampf((rescue_call_duration - _rescue_call_visible_timer) / 0.22, 0.0, 1.0)
		var fade_out: float = clampf(_rescue_call_visible_timer / 0.35, 0.0, 1.0)
		var alpha: float = minf(fade_in, fade_out)
		label.visible = alpha > 0.03
		label.modulate = Color(1.0, 0.96, 0.58, alpha)
		label.position.y = 2.15 + (1.0 - alpha) * 0.16 + sin(time_alive * 3.1) * 0.035
		return

	_hide_rescue_call()
	_rescue_call_timer -= delta
	if _rescue_call_timer > 0.0:
		return
	_rescue_call_timer = randf_range(rescue_call_interval_min, rescue_call_interval_max)
	_rescue_call_visible_timer = rescue_call_duration
	label.text = RESCUE_CALL_LINES.pick_random()
	label.visible = true
	label.modulate = Color(1.0, 0.96, 0.58, 0.0)


func _hide_rescue_call() -> void:
	if is_instance_valid(_rescue_call_label):
		_rescue_call_label.visible = false
		_rescue_call_label.modulate = Color(1.0, 0.96, 0.58, 0.0)


func _find_target_player() -> void:
	target_player = FieldItemHelper.find_closest_player_ship(self, _get_current_magnet_radius())


func _get_current_magnet_radius() -> float:
	return FieldItemHelper.get_current_magnet_radius(self, base_magnet_radius, _cached_um)


func _on_body_entered(body: Node3D) -> void:
	if is_collected: return
	var ship = _get_ship_from_node(body)
	if ship and ship.is_in_group("player"):
		_try_collect(ship)

func _on_area_entered(area: Area3D) -> void:
	if is_collected: return
	var ship = _get_ship_from_node(area)
	if ship and ship.is_in_group("player"):
		_try_collect(ship)

func _collect_by_proximity() -> void:
	if is_collected: return
	if is_instance_valid(target_player):
		_try_collect(target_player)

func _get_ship_from_node(node: Node) -> Node3D:
	return FieldItemHelper.get_ship_from_node(node)


func _is_close_enough_to_collect(player_ship: Node3D) -> bool:
	if not is_instance_valid(player_ship):
		return false
	return FieldItemHelper.is_item_close_to_ship_edge(self, player_ship, rescue_contact_margin)


func _get_ship_rescue_anchor(ship: Node3D, lift_to_deck: bool) -> Vector3:
	if not is_instance_valid(ship):
		return global_position
	return FieldItemHelper.get_ship_side_anchor(self, ship, lift_to_deck, 0.25, 0.75)


func _try_collect(player_ship: Node3D) -> void:
	if is_collected: return
	if not is_instance_valid(player_ship) or not player_ship.has_method("add_survivor"):
		return
	if not _is_close_enough_to_collect(player_ship):
		target_player = player_ship
		return

	is_collected = true
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	_finish_collection(player_ship)


func _finish_collection(player_ship: Node3D) -> void:
	var anchor: Vector3 = _get_ship_rescue_anchor(player_ship, true)
	if visual:
		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(self, "global_position", anchor, rescue_finish_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(visual, "scale", Vector3(0.25, 0.25, 0.25), rescue_finish_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tween.tween_property(visual, "rotation:z", 0.0, rescue_finish_duration)
		tween.chain().tween_callback(func(): _complete_collection(player_ship))
	else:
		_complete_collection(player_ship)


func _complete_collection(player_ship: Node3D) -> void:
	if not is_instance_valid(player_ship) or not player_ship.has_method("add_survivor"):
		ScenePool.release(self)
		return

	# 플레이어 배에 병사 추가 시도
	if player_ship and player_ship.has_method("add_survivor"):
		if player_ship.add_survivor(false):
			_finish_collection_effect()
		else:
			# 정원이 가득 찬 경우: 획득하지 않고 그냥 밀려남 (튕겨나가는 연출)
			var bounce_dir = (global_position - player_ship.global_position).normalized()
			global_position += bounce_dir * 2.0
			current_magnet_speed = 0.0
			is_collected = false
			set_deferred("monitoring", true)
			set_deferred("monitorable", true)


func _finish_collection_effect() -> void:
	_hide_rescue_call()
	# 획득 시 사라지는 연출
	if visual:
		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(visual, "scale", Vector3.ZERO, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tween.tween_property(visual, "position:y", position.y + 2.0, 0.3)
		var self_id: int = get_instance_id()
		tween.chain().tween_callback(func(): ScenePool.release_by_instance_id(self_id))
	else:
		ScenePool.release(self)
