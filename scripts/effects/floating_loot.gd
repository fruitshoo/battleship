extends Area3D
const PhysicsFrameProfiler = preload("res://scripts/debug/physics_frame_profiler.gd")

## 부유물(Floating Loot) 시스템
## 적 함선이 침몰할 때 바다에 스폰되며, 플레이어가 다가가면 자석처럼 끌려와 획득됨

@export var gold_amount: int = 5
@export var xp_amount: int = 0
@export var hull_repair_amount: float = 20.0
@export var base_magnet_radius: float = 8.0 # 기본 자석 효과 범위
@export var magnet_speed: float = 8.5 # 끌려가는 기본 속도
@export var float_speed: float = 2.0 # 둥실거리는 속도
@export var float_height: float = 0.3 # 둥실거리는 진폭
@export var rotation_speed: float = 1.0 # 회전 속도
@export_range(-0.5, 2.0, 0.05) var waterline_offset: float = -0.08
@export_range(-0.5, 1.0, 0.05) var visual_waterline_offset: float = 0.16
@export_range(0.2, 3.0, 0.05) var wave_tilt_strength: float = 0.7
@export var collection_contact_margin: float = 0.85

var target_player: Node3D = null
var current_magnet_speed: float = 0.0
var base_y: float = 0.0
var time_alive: float = 0.0
var is_collected: bool = false
var _cached_lm: Node = null
var _cached_um: Node = null
var _cached_ocean: Node = null
var _cached_wave_height: float = 0.0
var _cached_wave_tilt := Vector2.ZERO
var _wave_sample_timer: float = 0.0
var _visual_rest_scale: Vector3 = Vector3.ONE
@export_range(0.03, 0.3) var wave_sample_interval: float = 0.1
@export_range(0.05, 0.5) var player_search_interval: float = 0.2
var _player_search_timer: float = 0.0
var _float_phase: float = 0.0

@onready var visual: Node3D = $Visual if has_node("Visual") else ($MeshInstance3D if has_node("MeshInstance3D") else self)

func _ready() -> void:
	if _env_flag_enabled("BATTLESHIP_GAUNTLET_DISABLE_RECOVERY"):
		ScenePool.release(self)
		return
	# 획득 이벤트 연결 (한 번만 수행)
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	pool_reset()

func pool_capacity() -> int:
	return 80

func configure(next_hull_repair_amount: int = -1, next_gold_amount: int = -1) -> void:
	if next_hull_repair_amount >= 0:
		hull_repair_amount = float(next_hull_repair_amount)
	if next_gold_amount >= 0:
		gold_amount = next_gold_amount

func pool_reset() -> void:
	time_alive = 0.0
	is_collected = false
	is_expiring = false
	target_player = null
	current_magnet_speed = 0.0
	_player_search_timer = randf_range(0.0, player_search_interval)
	_wave_sample_timer = randf_range(0.0, wave_sample_interval)
	_float_phase = randf_range(0.0, TAU)
	
	base_y = global_position.y
	if visual:
		_visual_rest_scale = visual.scale
	if visual and visual is MeshInstance3D:
		var mat = visual.get_active_material(0)
		if mat == null:
			mat = StandardMaterial3D.new()
			visual.set_surface_override_material(0, mat)
		
		# 예시 재질 (나무통/상자 느낌 - 불투명하게 설정)
		if mat is StandardMaterial3D:
			mat.albedo_color = Color(0.7, 0.5, 0.3) # 색상을 조금 더 밝게 조정
			mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED # 투명도 비활성화
			
		# 스케일 애니메이션 적용 (투명도 버그 회피)
	if visual:
		visual.position.y = visual_waterline_offset
		visual.scale = Vector3.ZERO
		var tween = create_tween()
		tween.tween_property(visual, "scale", _visual_rest_scale, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			
		# 컬링 방지 마진 추가
		if visual is GeometryInstance3D:
			(visual as GeometryInstance3D).extra_cull_margin = 1.0
	
	# 레벨 매니저 캐싱
	_cached_lm = LevelManagerRegistry.get_level_manager(get_tree())
	
	# UpgradeManager 캐싱
	_cached_um = get_node_or_null("/root/UpgradeManager")
	
	# OceanPlane 캐싱
	_cached_ocean = get_tree().get_first_node_in_group("ocean")
	_player_search_timer = randf_range(0.0, player_search_interval)


@export var lifetime: float = 60.0 # 소멸 시간 (초)
var is_expiring: bool = false # 소멸 진행 중 여부


func _env_flag_enabled(name: String) -> bool:
	var value := OS.get_environment(name).strip_edges().to_lower()
	return value == "1" or value == "true" or value == "yes" or value == "on"

func _physics_process(delta: float) -> void:
	var profile_start := PhysicsFrameProfiler.begin()
	_profiled_physics_process(delta)
	PhysicsFrameProfiler.end("floating_loot_physics", profile_start)


func _profiled_physics_process(delta: float) -> void:
	if is_collected or not is_inside_tree():
		return
	time_alive += delta
	_wave_sample_timer = maxf(0.0, _wave_sample_timer - delta)
	_player_search_timer = maxf(0.0, _player_search_timer - delta)
	
	if not is_expiring and time_alive > lifetime:
		_expire_and_free()
		
	if is_expiring:
		return

	# 플레이어 탐색은 주기적으로 수행하여 비용을 줄임
	if is_instance_valid(target_player) and (not target_player.is_inside_tree() or NodeContractHelper.is_sinking_or_dying(target_player)):
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
			# 자석 효과 발동: 가속도가 붙으면서 끌려감
			var ship_speed_bonus: float = 0.0
			ship_speed_bonus = maxf(0.0, NodeContractHelper.get_current_speed_value(target_player)) * 0.9
			var pull_target: Vector3 = FieldItemHelper.get_ship_side_anchor(self, target_player, false)
			var pull_distance: float = global_position.distance_to(pull_target)
			var desired_magnet_speed: float = magnet_speed + ship_speed_bonus + (22.0 / max(pull_distance, 0.8))
			current_magnet_speed = move_toward(current_magnet_speed, desired_magnet_speed, 28.0 * delta)
			FieldItemHelper.move_item_toward_ship_side_anchor(self, target_player, current_magnet_speed * delta)
			_apply_floating(delta)
			
			# 근거리 자동 획득 (충돌 미감지 보완)
			if FieldItemHelper.is_item_close_to_ship_edge(self, target_player, collection_contact_margin):
				_collect_by_proximity()
		else:
			# 범위를 벗어나면 가속도 초기화 및 제자리 둥실거림
			current_magnet_speed = 0.0
			_apply_floating(delta)
	else:
		_apply_floating(delta)


func _expire_and_free() -> void:
	is_expiring = true
	is_collected = true # 획득 방지
	var tween = create_tween().set_parallel(true)
	# 천천히 가라앉으며 사라짐 (깜빡임 대신)
	tween.tween_property(self , "position:y", position.y - 2.0, 3.0)
	if visual:
		tween.tween_property(visual, "scale", Vector3.ZERO, 3.0)
	var self_id: int = get_instance_id()
	tween.chain().tween_callback(func(): ScenePool.release_by_instance_id(self_id))


func _apply_floating(delta: float) -> void:
	if not is_inside_tree():
		return
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
	position.y = lerp(position.y, target_y, 5.0 * delta)
	FieldItemHelper.apply_floating_visual_motion(visual, delta, time_alive, float_speed, _float_phase, _cached_wave_tilt, wave_tilt_strength, rotation_speed)


func _sample_ocean_surface() -> void:
	var sample := FieldItemHelper.sample_ocean_surface(self, _cached_ocean)
	_cached_wave_height = float(sample.get("height", 0.0))
	_cached_wave_tilt = sample.get("tilt", Vector2.ZERO)


func _find_target_player() -> void:
	if not is_inside_tree():
		target_player = null
		return
	target_player = FieldItemHelper.find_closest_player_ship(self, _get_current_magnet_radius())


func _get_current_magnet_radius() -> float:
	return FieldItemHelper.get_current_magnet_radius(self, base_magnet_radius, _cached_um)


func _on_body_entered(body: Node3D) -> void:
	if is_collected: return
	var ship = _get_ship_from_node(body)
	if ship and ship.is_in_group("player"):
		_try_collect_or_target(ship)

func _on_area_entered(area: Area3D) -> void:
	if is_collected: return
	var ship = _get_ship_from_node(area)
	if ship and ship.is_in_group("player"):
		_try_collect_or_target(ship)

func _collect_by_proximity() -> void:
	if is_collected: return
	if is_instance_valid(target_player) and target_player.is_inside_tree() and FieldItemHelper.is_item_close_to_ship_edge(self, target_player, collection_contact_margin):
		is_collected = true
		_collect_loot()

func _get_ship_from_node(node: Node) -> Node3D:
	return FieldItemHelper.get_ship_from_node(node)

func _try_collect_or_target(ship: Node3D) -> void:
	if is_collected or not is_instance_valid(ship):
		return
	target_player = ship
	if not FieldItemHelper.is_item_close_to_ship_edge(self, ship, collection_contact_margin):
		return
	is_collected = true
	_collect_loot()


func _collect_loot() -> void:
	# 획득 효과음 재생 (카메라 거리에 상관없이 잘 들리도록 2D 사운드(null)로 재생)
	var audio_manager = get_node_or_null("/root/AudioManager")
	if is_instance_valid(audio_manager):
		audio_manager.play_sfx("treasure_collect", null, randf_range(1.1, 1.3))
	
	# 보상 지급
	var repaired_amount := _repair_player_hull(target_player)
	if is_instance_valid(_cached_lm):
		if _cached_lm.has_method("add_score"):
			_cached_lm.add_score(gold_amount)
		if _cached_lm.get("hud") != null:
			var hud: Variant = _cached_lm.get("hud")
			if is_instance_valid(hud) and hud.has_method("show_message"):
				var message := LocaleManager.t("hud.loot.recovered", "침몰 부유물 회수")
				if repaired_amount > 0.0:
					message = LocaleManager.t("hud.loot.recovered_hull", "침몰 부유물 회수: 선체 +{amount}", {"amount": int(round(repaired_amount))})
				hud.call("show_message", message, 1.5)
				
	# 파티클이나 시각적인 먹는 효과 (크기가 줄어들면서 사라짐)
	if visual:
		var tween = create_tween()
		tween.tween_property(visual, "scale", Vector3.ZERO, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		var self_id: int = get_instance_id()
		tween.tween_callback(func(): ScenePool.release_by_instance_id(self_id))
	else:
		ScenePool.release(self)


func _repair_player_hull(player_ship: Node3D) -> float:
	if not is_instance_valid(player_ship):
		return 0.0
	if player_ship.get("hull_hp") == null or player_ship.get("max_hull_hp") == null:
		return 0.0
	var max_hull: float = maxf(1.0, float(player_ship.get("max_hull_hp")))
	var before: float = clampf(float(player_ship.get("hull_hp")), 0.0, max_hull)
	var after: float = minf(max_hull, before + maxf(0.0, hull_repair_amount))
	player_ship.set("hull_hp", after)
	var repaired_amount := after - before
	if repaired_amount > 0.001:
		var hud: Node = _cached_lm.get("hud") if is_instance_valid(_cached_lm) and _cached_lm.get("hud") != null else null
		if is_instance_valid(hud) and hud.has_method("update_hull_hp"):
			hud.call("update_hull_hp", after, max_hull)
	return repaired_amount
