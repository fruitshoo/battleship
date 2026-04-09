extends Area3D
const EntityRegistry = preload("res://scripts/helpers/entity_registry.gd")
const NodeContractHelper = preload("res://scripts/helpers/node_contract_helper.gd")
const ScenePool = preload("res://scripts/helpers/scene_pool.gd")

## 생존자(Survivor) 시스템
## 적함 침몰 시 발생하며, 플레이어가 다가가면 자석처럼 끌려와 병사로 합류함

@export var base_magnet_radius: float = 8.0 # 기본 자석 효과 범위
@export var magnet_speed: float = 7.5 # 끌려가는 기본 속도
@export var float_speed: float = 1.5 # 둥실거리는 속도
@export var float_height: float = 0.2 # 둥실거리는 진폭
@export var rotation_speed: float = 0.5 # 회전 속도

var target_player: Node3D = null
var current_magnet_speed: float = 0.0
var base_y: float = 0.0
var time_alive: float = 0.0
var is_collected: bool = false
var _cached_ocean: Node = null
var _cached_um: Node = null
var _cached_wave_height: float = 0.0
var _wave_sample_timer: float = 0.0
@export_range(0.03, 0.3) var wave_sample_interval: float = 0.1
@export_range(0.05, 0.5) var player_search_interval: float = 0.2
var _player_search_timer: float = 0.0

@onready var visual = $MeshInstance3D if has_node("MeshInstance3D") else self

func _ready() -> void:
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
	
	base_y = global_position.y
	if base_y < 0.2: base_y = 0.5
	
	# 파란색 캡슐 이미지 설정 (병사 캐릭터와 동일하게)
	if visual and visual is MeshInstance3D:
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.4, 0.8) # Blue (Player Team Color)
		mat.emission_enabled = true
		mat.emission = Color(0.2, 0.4, 0.8)
		mat.emission_energy_multiplier = 0.5
		visual.set_surface_override_material(0, mat)
		
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


@export var lifetime: float = 90.0 # 소멸 시간 (초, 생존자는 조금 더 길게)
var is_expiring: bool = false # 소멸 진행 중 여부

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
			var desired_magnet_speed: float = magnet_speed + ship_speed_bonus + (16.0 / max(dist, 0.8))
			current_magnet_speed = move_toward(current_magnet_speed, desired_magnet_speed, 24.0 * delta)
			var direction: Vector3 = (target_player.global_position - global_position).normalized()
			global_position += direction * current_magnet_speed * delta
			
			# 근거리 자동 획득 (충돌 미감지 보완)
			if dist < 3.0:
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
	var tween = create_tween().set_parallel(true)
	# 천천히 가라앉으며 사라짐 (깜빡임 대신)
	tween.tween_property(self , "position:y", position.y - 2.0, 4.0)
	if visual:
		tween.tween_property(visual, "scale", Vector3.ZERO, 4.0)
	tween.chain().tween_callback(func(): ScenePool.release(self))


func _apply_floating(delta: float) -> void:
	var target_y = base_y + sin(time_alive * float_speed) * float_height
	
	if is_instance_valid(_cached_ocean) and _cached_ocean.has_method("get_wave_height"):
		if _wave_sample_timer <= 0.0:
			_cached_wave_height = _cached_ocean.get_wave_height(global_position)
			_wave_sample_timer = wave_sample_interval
		target_y += _cached_wave_height
		
	# lerp를 사용하여 부드럽게 파도와 기본 높이를 따라감
	position.y = lerp(position.y, target_y, 4.0 * delta)
	
	if visual:
		visual.rotation.y += rotation_speed * delta
		visual.rotation.z = sin(time_alive * float_speed * 1.2) * 0.15


func _find_target_player() -> void:
	var players = EntityRegistry.get_ships_by_team("player")
	var closest_dist = INF
	var closest_p = null
	
	for p in players:
		if NodeContractHelper.is_sinking_or_dying(p): continue
		
		var d = global_position.distance_to(p.global_position)
		if d < closest_dist:
			closest_dist = d
			closest_p = p
			
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
	if not node: return null
	if node.is_in_group("player"): return node
	
	# 부모나 주인(owner)이 함선인지 확인
	var p = node.get_parent()
	if p and p.is_in_group("player"): return p
	
	if node is CollisionShape3D or node is Area3D:
		var pp = node.get_parent()
		if pp and pp.is_in_group("player"): return pp
		
	if node.owner and node.owner.is_in_group("player"):
		return node.owner
		
	return null


func _try_collect(player_ship: Node3D) -> void:
	if is_collected: return
	
	# 플레이어 배에 병사 추가 시도
	if player_ship and player_ship.has_method("add_survivor"):
		if player_ship.add_survivor():
			is_collected = true
			
			# 생존자 구조 시에도 체력 소폭 회복 로직 추가
			if "hull_hp" in player_ship and "max_hull_hp" in player_ship:
				var um = get_node_or_null("/root/UpgradeManager")
				var heal_amount: float = 5.0
				var stamina_recover: float = 0.0
				if is_instance_valid(um) and um.has_method("get_supply_bonus_stats"):
					var supply_stats: Dictionary = um.get_supply_bonus_stats()
					heal_amount += float(supply_stats.get("heal_bonus", 0.0))
					stamina_recover += float(supply_stats.get("stamina_recovery_bonus", 0.0))
				player_ship.hull_hp = minf(player_ship.hull_hp + heal_amount, player_ship.max_hull_hp)
				if "rowing_stamina" in player_ship and "max_rowing_stamina" in player_ship:
					player_ship.rowing_stamina = minf(player_ship.max_rowing_stamina, player_ship.rowing_stamina + stamina_recover)
				
				if player_ship.has_method("_find_hud"):
					var hud = player_ship._find_hud()
					if hud and hud.has_method("update_hull_hp"):
						hud.update_hull_hp(player_ship.hull_hp, player_ship.max_hull_hp)
			
			_finish_collection()
		else:
			# 정원이 가득 찬 경우: 획득하지 않고 그냥 밀려남 (튕겨나가는 연출)
			var bounce_dir = (global_position - player_ship.global_position).normalized()
			global_position += bounce_dir * 2.0
			current_magnet_speed = 0.0


func _finish_collection() -> void:
	# 획득 시 사라지는 연출
	if visual:
		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(visual, "scale", Vector3.ZERO, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tween.tween_property(visual, "position:y", position.y + 2.0, 0.3)
		tween.chain().tween_callback(func(): ScenePool.release(self))
	else:
		ScenePool.release(self)
