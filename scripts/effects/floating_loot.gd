extends Area3D
const LevelManagerRegistry = preload("res://scripts/helpers/level_manager_registry.gd")
const EntityRegistry = preload("res://scripts/helpers/entity_registry.gd")
const NodeContractHelper = preload("res://scripts/helpers/node_contract_helper.gd")
const ScenePool = preload("res://scripts/helpers/scene_pool.gd")

## 부유물(Floating Loot) 시스템
## 적을 물리쳤을 때 바다에 스폰되며, 플레이어가 다가가면 자석처럼 끌려와 획득됨

@export var gold_amount: int = 15
@export var xp_amount: int = 15 # Deprecated: 부유물에서는 XP를 지급하지 않음(규칙 단순화용)
@export var base_magnet_radius: float = 8.0 # 기본 자석 효과 범위
@export var magnet_speed: float = 8.5 # 끌려가는 기본 속도
@export var float_speed: float = 2.0 # 둥실거리는 속도
@export var float_height: float = 0.3 # 둥실거리는 진폭
@export var rotation_speed: float = 1.0 # 회전 속도

var target_player: Node3D = null
var current_magnet_speed: float = 0.0
var base_y: float = 0.0
var time_alive: float = 0.0
var is_collected: bool = false
var _cached_lm: Node = null
var _cached_um: Node = null
var _cached_ocean: Node = null
var _cached_wave_height: float = 0.0
var _wave_sample_timer: float = 0.0
var _visual_rest_scale: Vector3 = Vector3.ONE
@export_range(0.03, 0.3) var wave_sample_interval: float = 0.1
@export_range(0.05, 0.5) var player_search_interval: float = 0.2
var _player_search_timer: float = 0.0

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

func pool_reset() -> void:
	time_alive = 0.0
	is_collected = false
	is_expiring = false
	target_player = null
	current_magnet_speed = 0.0
	_player_search_timer = randf_range(0.0, player_search_interval)
	
	base_y = global_position.y
	if base_y < 0.2: base_y = 0.5
	
	# 초기에는 크기를 0으로 시작해서 나타남 (스폰 연출)
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
			var desired_magnet_speed: float = magnet_speed + ship_speed_bonus + (22.0 / max(dist, 0.8))
			current_magnet_speed = move_toward(current_magnet_speed, desired_magnet_speed, 28.0 * delta)
			var direction: Vector3 = (target_player.global_position - global_position).normalized()
			global_position += direction * current_magnet_speed * delta
			
			# 근거리 자동 획득 (충돌 미감지 보완)
			if dist < 3.5:
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
	tween.chain().tween_callback(func(): ScenePool.release(self))


func _apply_floating(delta: float) -> void:
	if not is_inside_tree():
		return
	var target_y = base_y + sin(time_alive * float_speed) * float_height
	
	if is_instance_valid(_cached_ocean) and _cached_ocean.has_method("get_wave_height"):
		if _wave_sample_timer <= 0.0:
			_cached_wave_height = _cached_ocean.get_wave_height(global_position)
			_wave_sample_timer = wave_sample_interval
		target_y += _cached_wave_height
		
	# lerp를 사용하여 부드럽게 파도와 기본 높이를 따라감
	position.y = lerp(position.y, target_y, 5.0 * delta)
	
	if visual:
		visual.rotation.y += rotation_speed * delta
		visual.rotation.z = sin(time_alive * float_speed * 1.5) * 0.1 # 살짝 갸우뚱


func _find_target_player() -> void:
	if not is_inside_tree():
		target_player = null
		return
	var players = EntityRegistry.get_ships_by_team("player")
	var closest_dist = INF
	var closest_p = null
	
	for p in players:
		if not is_instance_valid(p) or not p.is_inside_tree():
			continue
		if NodeContractHelper.is_sinking_or_dying(p): continue
		
		var d = global_position.distance_to(p.global_position)
		if d < closest_dist:
			closest_dist = d
			closest_p = p
			
	# 가장 가까운 아군 배를 타겟으로 함 (본선/나포함 구분 없음)
	if closest_dist <= _get_current_magnet_radius() * 1.5:
		target_player = closest_p
	else:
		target_player = null


func _get_current_magnet_radius() -> float:
	var meta_bonus := 0.0
	var meta_manager = get_node_or_null("/root/MetaManager")
	if is_instance_valid(meta_manager) and meta_manager.has_method("get_collection_radius_bonus"):
		meta_bonus = float(meta_manager.get_collection_radius_bonus())
	if is_instance_valid(_cached_um) and _cached_um.has_method("get_supply_bonus_stats"):
		var supply_stats: Dictionary = _cached_um.get_supply_bonus_stats()
		return base_magnet_radius + meta_bonus + float(supply_stats.get("radius_bonus", 0.0))
	return base_magnet_radius + meta_bonus


func _on_body_entered(body: Node3D) -> void:
	if is_collected: return
	var ship = _get_ship_from_node(body)
	if ship and ship.is_in_group("player"):
		is_collected = true
		_collect_loot()

func _on_area_entered(area: Area3D) -> void:
	if is_collected: return
	var ship = _get_ship_from_node(area)
	if ship and ship.is_in_group("player"):
		is_collected = true
		_collect_loot()

func _collect_by_proximity() -> void:
	if is_collected: return
	if is_instance_valid(target_player) and target_player.is_inside_tree():
		is_collected = true
		_collect_loot()

func _get_ship_from_node(node: Node) -> Node3D:
	if not node: return null
	if node.is_in_group("player"): return node
	
	var p = node.get_parent()
	if p and p.is_in_group("player"): return p
	
	if node is CollisionShape3D or node is Area3D:
		var pp = node.get_parent()
		if pp and pp.is_in_group("player"): return pp
		
	if node.owner and node.owner.is_in_group("player"):
		return node.owner
		
	return null


func _collect_loot() -> void:
	# 획득 효과음 재생 (카메라 거리에 상관없이 잘 들리도록 2D 사운드(null)로 재생)
	var audio_manager = get_node_or_null("/root/AudioManager")
	if is_instance_valid(audio_manager):
		audio_manager.play_sfx("treasure_collect", null, randf_range(1.1, 1.3))
	
	# 보상 지급
	if is_instance_valid(_cached_lm):
		if _cached_lm.has_method("add_score"):
			_cached_lm.add_score(gold_amount)
			
	# 선체 수리 (supply_bonus 업그레이드 수치 반영)
	if is_instance_valid(target_player) and target_player.is_inside_tree() and "hull_hp" in target_player and "max_hull_hp" in target_player:
		var heal_amount: float = 5.0
		var stamina_recover: float = 0.0
		if is_instance_valid(_cached_um) and _cached_um.has_method("get_supply_bonus_stats"):
			var supply_stats: Dictionary = _cached_um.get_supply_bonus_stats()
			heal_amount += float(supply_stats.get("heal_bonus", 0.0))
			stamina_recover += float(supply_stats.get("stamina_recovery_bonus", 0.0))
		target_player.hull_hp = minf(target_player.hull_hp + heal_amount, target_player.max_hull_hp)
		if "rowing_stamina" in target_player and "max_rowing_stamina" in target_player:
			target_player.rowing_stamina = minf(target_player.max_rowing_stamina, target_player.rowing_stamina + stamina_recover)
		
		# HUD 연동
		if target_player.has_method("_find_hud"):
			var hud = target_player._find_hud()
			if hud and hud.has_method("update_hull_hp"):
				hud.update_hull_hp(target_player.hull_hp, target_player.max_hull_hp)
				
	# 파티클이나 시각적인 먹는 효과 (크기가 줄어들면서 사라짐)
	if visual:
		var tween = create_tween()
		tween.tween_property(visual, "scale", Vector3.ZERO, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tween.tween_callback(func(): ScenePool.release(self))
	else:
		ScenePool.release(self)
