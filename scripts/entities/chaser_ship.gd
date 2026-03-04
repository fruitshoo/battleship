extends "res://scripts/entities/base_ship.gd"
class_name ChaserShip

## 추적선 (Chaser Ship)
## 플레이어를 단순 추적하고, 충돌 시 병사를 도선(Boarding)시키고 자폭

@export var team: String = "enemy" # "enemy" or "player"
@export var move_speed: float = 3.5
@export var soldier_scene: PackedScene = preload("res://scenes/soldier.tscn")
@export var boarders_count: int = 2 # 도선시킬 병사 수

@export var cannon_scene: PackedScene = preload("res://scenes/entities/cannon.tscn")

var target: Node3D = null

# 상태 (State)
var leaking_rate: float = 0.0


@export var max_minion_crew: int = 4
var minion_respawn_timer: float = 0.0
@export var minion_respawn_interval: float = 15.0 # 아군 배보다 조금 더 느림


# === 함대 진형 (Formation) 관련 ===
enum Formation {COLUMN, WING}
static var fleet_formation: Formation = Formation.COLUMN # 공유 진형 설정 (기본: 장사진)

var formation_spacing: float = 14.0 # 선박 간 간격 축소 (밀집 대형)

var _wave_timer: float = 0.0 # 물결 소리 타이머
var _last_ai_speed: float = 0.0 # 속도 평활화를 위한 이전 프레임 속도 저장
var _oar_time: float = 0.0

# === 성능 최적화용 캐싱 (성능 저하 방지) ===
static var _cached_minion_list: Array = []
static var _last_minion_cache_frame: int = -1
static var _cached_ships_list: Array = []
static var _last_ships_cache_frame: int = -1

var _cached_wind_manager: Node = null

static func get_minions_cached(tree: SceneTree) -> Array:
	var current_frame = Engine.get_physics_frames()
	if current_frame != _last_minion_cache_frame:
		_cached_minion_list = tree.get_nodes_in_group("captured_minion")
		_last_minion_cache_frame = current_frame
	return _cached_minion_list

static func get_ships_cached(tree: SceneTree) -> Array:
	var current_frame = Engine.get_physics_frames()
	if current_frame != _last_ships_cache_frame:
		_cached_ships_list = tree.get_nodes_in_group("ships")
		_last_ships_cache_frame = current_frame
	return _cached_ships_list


# 최적화 변수
var cached_lm: Node = null
var separation_force: Vector3 = Vector3.ZERO
var separation_timer: float = 0.0
var logic_timer: float = 0.0 # 타겟 체크 등 일반 로직용

# 도선 로직 변수 (base_ship.gd에서 상속)
var has_rammed: bool = false # 중복 데미지 방지

func get_radius() -> float:
	return 2.5 # 대략적인 선체 반경 (상황에 맞게 조정)

func _become_derelict() -> void:
	is_derelict = true
	is_boarding = false
	if wake_trail: wake_trail.emitting = false
	
	print("[Status] 선원 전멸! 적함이 폐선(Derelict) 상태가 되었습니다.")
	
	# 파티클 하나 띄워줄 수 있다면 좋음 (검은 연기 등)
	# 돛을 내리거나 색상을 어둡게 하는 등의 시각적 처리도 연출 가능
	
	# 임시로 시각적 피드백: 약간 기울어지고 가라앉음 (반파 효과)
	var tilt_tween = create_tween()
	tilt_tween.tween_property(self , "rotation_degrees:z", 5.0, 2.0).set_ease(Tween.EASE_OUT)
	tilt_tween.set_parallel(true)
	tilt_tween.tween_property(self , "global_position:y", global_position.y - 0.2, 2.0).set_ease(Tween.EASE_OUT)
	
	# 도선 방지를 위해 이동 및 회전 정지
	move_speed = 0.0
	
	# 빈 배는 스스로 서서히 침몰하도록 누수 설정 (초당 최대 체력의 5% 데미지 -> 약 20초 뒤 침몰)
	leaking_rate = max_hull_hp * 0.05
	
	cached_lm = get_tree().root.find_child("LevelManager", true, false)
	if not cached_lm:
		var lm_nodes = get_tree().get_nodes_in_group("level_manager")
		if lm_nodes.size() > 0: cached_lm = lm_nodes[0]

func _ready() -> void:
	if max_hull_hp <= 0: max_hull_hp = 60.0 # Default fallback
	global_position.y = base_y # Keep base_y assignment from BaseShip valid
	_find_player()
	
	# 초기 돛 색상 설정 (Enemy 기본: Red)
	for mast in masts:
		if mast.has_method("set_sail_color"):
			mast.set_sail_color(Color(0.7, 0.1, 0.1, 1.0))
		if mast.has_method("set_team_color"):
			mast.set_team_color("enemy")
	add_to_group("ships")
	if team == "player":
		add_to_group("player")
		add_to_group("captured_minion")
		_apply_minion_visuals()
	else:
		add_to_group("enemy")
		
	_find_player()
	
	cached_lm = get_tree().root.find_child("LevelManager", true, false)
	if not cached_lm:
		var lm_nodes = get_tree().get_nodes_in_group("level_manager")
		if lm_nodes.size() > 0: cached_lm = lm_nodes[0]
	
	_cached_wind_manager = get_node_or_null("/root/WindManager")


func die() -> void:
	if is_dying: return
	is_dying = true
	
	# ✅ 배 위의 병사들을 원래 배로 복귀시키고, 복귀 불가 시 생존자로 전환
	_evacuate_soldiers_to_home()
	_evacuate_player_soldiers_as_survivors()
	
	# 밧줄 및 도선 공격자 정보 제거
	if is_instance_valid(boarding_target) and boarding_target.get("boarding_attacker") == self:
		boarding_target.set("boarding_attacker", null)
	_clear_ropes()
	
	# 침몰 시작 시 타겟 그룹에서 제외 (대포가 시체를 쏘지 않게 함)
	if is_in_group("enemy"):
		remove_from_group("enemy")
	if is_in_group("player"):
		remove_from_group("player")
	if is_in_group("captured_minion"):
		remove_from_group("captured_minion")
	
	# 점수 및 XP 추가
	if is_instance_valid(cached_lm):
		if cached_lm.has_method("add_score"):
			cached_lm.add_score(100)
		if cached_lm.has_method("add_xp"):
			cached_lm.add_xp(30)
	
	# 물리 및 충돌 비활성화 (Area3D 대응)
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	
	if get_node_or_null("CollisionShape3D"):
		get_node("CollisionShape3D").set_deferred("disabled", true)
		
	# 항적 끄기
	if wake_trail:
		wake_trail.emitting = false
		
	# 가라앉는 연출 (침몰 애니메이션)
	var sink_tween = create_tween()
	sink_tween.set_parallel(true)
	
	# 무작위 기울기
	var tilt_x = randf_range(-15.0, 15.0)
	var tilt_z = randf_range(-10.0, 10.0)
	sink_tween.tween_property(self , "rotation_degrees:x", tilt_x, 3.0).set_ease(Tween.EASE_OUT)
	sink_tween.tween_property(self , "rotation_degrees:z", tilt_z, 3.0).set_ease(Tween.EASE_OUT)
	
	# 아래로 깊게 가라앉음 + 페이드 아웃
	var sink_duration = 6.0
	sink_tween.tween_property(self , "global_position:y", global_position.y - 15.0, sink_duration).set_ease(Tween.EASE_IN)
	
	# (메쉬 투명도 조절 대신 셰이더 수심 효과로 대체)
	
	leaking_rate = 0.0 # 사망 시 누수 중단
	
	_drop_floating_loot()
	
	sink_tween.set_parallel(false)
	sink_tween.tween_callback(queue_free)


func _drop_floating_loot() -> void:
	if not loot_scene: return
	
	# 1~3개의 부유물 드랍
	var loot_count = randi_range(1, 3)
	for i in range(loot_count):
		var loot = loot_scene.instantiate()
		var offset_x = randf_range(-2.0, 2.0)
		var offset_z = randf_range(-2.0, 2.0)
		var spawn_pos = Vector3(global_position.x + offset_x, 0.5, global_position.z + offset_z)
		
		get_tree().root.add_child.call_deferred(loot)
		loot.set_deferred("global_position", spawn_pos)
		
	# 4. 생존자(Survivor) 스폰 추가 (30% 확률)
	if survivor_scene and randf() < 0.3:
		var survivor = survivor_scene.instantiate()
		var s_offset = Vector3(randf_range(-1.0, 1.0), 0.5, randf_range(-1.0, 1.0))
		var survivor_pos = global_position + s_offset
		get_tree().root.add_child.call_deferred(survivor)
		survivor.set_deferred("global_position", survivor_pos)
		print("[Rescue] 구출 가능한 생존자가 발생했습니다!")

## 침몰 시 배 위의 아군(player) 병사를 Survivor로 전환
func _evacuate_player_soldiers_as_survivors() -> void:
	if not survivor_scene: return
	var soldiers_node = get_node_or_null("Soldiers")
	if not soldiers_node: return
	
	var converted_count = 0
	for child in soldiers_node.get_children():
		if child.get("team") == "player" and child.get("current_state") != 4: # NOT DEAD
			# 병사 위치 저장 후 생존자 스폰
			var spawn_pos = child.global_position
			spawn_pos.y = 0.5 # 수면 높이
			
			var survivor = survivor_scene.instantiate()
			get_tree().root.add_child.call_deferred(survivor)
			survivor.set_deferred("global_position", spawn_pos)
			
			# 병사 즉시 제거
			child.queue_free()
			converted_count += 1
	
	if converted_count > 0:
		print("[Critical] 아군 병사 %d명이 바다로 뛰어들었습니다!" % converted_count)

## 침몰 시 배 위의 병사들을 원래 배(home_ship)로 복귀시킴
func _evacuate_soldiers_to_home() -> void:
	var soldiers_node = get_node_or_null("Soldiers")
	if not soldiers_node: return
	
	var returned_count = 0
	for child in soldiers_node.get_children():
		if child.get("current_state") == 4: continue # DEAD
		
		var h_ship = child.get("home_ship")
		# home_ship이 유효하고, 아직 가라앉지 않았으며, 현재 배가 아닌 경우 복귀
		if is_instance_valid(h_ship) and h_ship != self and not h_ship.get("is_sinking") and not h_ship.get("is_dying"):
			var target_soldiers = h_ship.get_node_or_null("Soldiers")
			if not target_soldiers: continue
			
			# 점프 애니메이션으로 복귀
			var start_pos = child.global_position
			child.call_deferred("reparent", target_soldiers)
			
			var jump_offset = Vector3(randf_range(-1.0, 1.0), 0.5, randf_range(-1.5, 1.5))
			var end_pos = h_ship.global_transform * jump_offset
			
			var tween = create_tween()
			tween.set_parallel(true)
			tween.tween_property(child, "global_position:x", end_pos.x, 0.5).set_trans(Tween.TRANS_LINEAR)
			tween.tween_property(child, "global_position:z", end_pos.z, 0.5).set_trans(Tween.TRANS_LINEAR)
			
			var mid_y = max(start_pos.y, end_pos.y) + 2.0
			var y_tween = create_tween()
			y_tween.tween_property(child, "global_position:y", mid_y, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			y_tween.tween_property(child, "global_position:y", end_pos.y, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
			
			child.set("owned_ship", h_ship)
			if child.get("is_stationary"): child.set("is_stationary", false)
			returned_count += 1
			print("[Evacuation] 병사가 원래 배(%s)로 복귀합니다!" % h_ship.name)
	
	if returned_count > 0:
		print("[Evacuation] 총 %d명의 병사가 원래 배로 복귀했습니다." % returned_count)


## 생존자 구조 및 병사 합류 처리 (나포함용)
func add_survivor() -> bool:
	if is_dying: return false
	
	var soldiers_node = get_node_or_null("Soldiers")
	if not soldiers_node: return false
	
	# 현재 살아있는 병사 수 체크
	var alive_count = 0
	for child in soldiers_node.get_children():
		if child.get("current_state") != 4: # NOT DEAD
			alive_count += 1
		else:
			child.queue_free() # 시체 정리
			
	# 나포함 전용 정원(max_minion_crew) 체크
	if alive_count >= max_minion_crew:
		print("[Rescue] 정원 초과 합류! (현재 인원: %d/%d)" % [alive_count + 1, max_minion_crew])
		# 정원 초과 시에도 합류는 허용하여 생존자가 배에 부딪혀 튕겨나가는 것을 방지함
		
	# 병사 생성
	var s = soldier_scene.instantiate()
	soldiers_node.add_child(s)
	s.set_team("player")
	
	# 위치 설정 (갑판 위 랜덤)
	var offset = Vector3(randf_range(-0.8, 0.8), 0.5, randf_range(-1.5, 1.5))
	s.position = offset
	
	print("[Crew] 나포함이 생존자를 구조했습니다! (현재: %d/%d)" % [alive_count + 1, max_minion_crew])
	return true

func _process(delta: float) -> void:
	if is_dying: return
	
	_update_fire_effect()
	_auto_adjust_sail(delta)
	_update_sail_visual()
	_update_oar_visual(delta)
	_update_burning_status(delta)
	_update_hull_regeneration(delta)
	
	if is_derelict:
		leaking_rate += 0.2 * delta
		# 폐선 상태일 때는 타겟 초기화 (공격 중단)
		target = null
		is_boarding = false
		_clear_ropes()
		
	if team == "player":
		_update_minion_respawn(delta)


func _physics_process(delta: float) -> void:
	if is_dying: return
	
	_update_wave_sounds(delta)
	
	# 0. 아군 나포함(Minion)은 전용 AI 수행 (최우선)
	if team == "player":
		_process_minion_ai(delta)
		return
	
	# === 폐선(Derelict) 체크 (적군 전용) ===
	if is_derelict:
		# 폐선 상태면 둥둥 떠있기만 함 (로직 정지)
		# 바다에 천천히 떠밀려감
		position += Vector3.BACK * 0.2 * delta
		if wake_trail: wake_trail.emitting = false
		return
	
	# === 모든 소속 병사 전멸 시 폐선화 ===
	# (갑판 위뿐 아니라, 다른 배로 도선간 병사도 포함해서 체크)
	if logic_timer <= 0:
		var all_crew_dead = true
		var all_soldiers = get_tree().get_nodes_in_group("soldiers")
		for s in all_soldiers:
			if s.get("home_ship") == self and s.get("current_state") != 4: # NOT DEAD
				all_crew_dead = false
				break
		if all_crew_dead:
			_become_derelict()
			return


	# 도선(Boarding) 상태 로직
	if is_boarding:
		_process_boarding(delta)
		return

	# 1. 고비용 로직 스로틀링 (0.2초마다)
	logic_timer -= delta
	if logic_timer <= 0:
		logic_timer = 0.2
		_update_logic_throttled()

	if not is_instance_valid(target):
		if wake_trail: wake_trail.emitting = false
		return
	
	# 2. 목표 지점 계산 (Galley Intercept Logic)
	var target_pos = target.global_position
	var dist_to_player = global_position.distance_to(target_pos)
	
	if dist_to_player >= 25.0:
		# 예측 이동 (Intercept)
		var target_speed = target.get("current_speed")
		if target_speed:
			var target_forward = Vector3(-sin(target.rotation.y), 0, -cos(target.rotation.y))
			var time_to_reach = min(dist_to_player / move_speed, 3.0)
			target_pos += target_forward * target_speed * time_to_reach

	# 3. 이동 및 회전 (Separation 포함)
	var move_dir = (target_pos - global_position).normalized()
	
	# Separation (함선 간 겹침 방지) - 계산은 스로틀링됨
	if separation_force.length_squared() > 0.001:
		# 분리력을 이동 방향에 부드럽게 합성 (강도 1.5배 적용)
		move_dir = (move_dir + separation_force * 1.5).normalized()
	
	var target_rotation_y = atan2(-move_dir.x, -move_dir.z)
	rotation.y = lerp_angle(rotation.y, target_rotation_y, delta * 3.0)
	
	# 전진 (누수율에 비례하여 속도 감소)
	var leak_speed_mult = clamp(1.0 - (leaking_rate * 0.05), 0.3, 1.0)
	
	# === 바람 영향(Wind Force) 적용 ===
	var wind_mult = 1.0
	if is_instance_valid(_cached_wind_manager) and _cached_wind_manager.has_method("get_wind_direction"):
		var wind_dir: Vector2 = _cached_wind_manager.get_wind_direction()
		var wind_str: float = _cached_wind_manager.get_wind_strength()
		
		# 배의 전방 벡터 (2D 평면 기준)
		var ship_forward = Vector2(move_dir.x, move_dir.z).normalized()
		# 바람과 배 전방 방향의 내적 (1.0=순풍, -1.0=역풍)
		var dot_prod = wind_dir.dot(ship_forward)
		
		# 역풍(-1) ~ 순풍(1)에 따라 0.4 ~ 1.5 배율 적용 (플레이어보다 약간 완화된 페널티)
		# 즉, 역풍에도 최소 40%의 속도는 낼 수 있게 하여 아예 멈추지 않도록 함
		var base_wind_influence = remap(dot_prod, -1.0, 1.0, 0.4, 1.5)
		
		# 바람의 세기(wind_str)가 강할수록 영향력이 커짐
		# wind_str이 0이면 무조건 1.0(영향 없음)
		wind_mult = lerp(1.0, base_wind_influence, wind_str)
	
	var velocity = move_dir * move_speed * leak_speed_mult * wind_mult
	
	# === 겹침 방지 (Separation) 적용 ===
	# 이제 방향에 합치는 게 아니라, 속도에 직접 더해서 물리적으로 밀쳐내게 함
	velocity += separation_force
	
	position += velocity * delta
	
	# === 누수(Leaking) 데미지 ===
	if leaking_rate > 0:
		take_damage(leaking_rate * delta)
		
	# === 시각적 효과 (둥실둥실 및 기울기) ===
	_apply_bobbing_effect()

	# 수면 위 높이 유지 (사망 시 tween에 의해 덮어씌워짐)
	if not is_dying:
		rotation.z += tilt_offset # Add tilt_offset since base handles bobbing
		pass

	# 항적 제어
	if wake_trail:
		wake_trail.emitting = move_speed > 0.5

func _update_logic_throttled() -> void:
	# 타겟 유효성 및 침몰 상태 체크
	if not is_instance_valid(target) or target.get("is_sinking"):
		target = null
		_find_player()
	
	# Separation 계산 (전체 함선 대상)
	separation_force = _calculate_separation()

## 주변 함선들로부터 멀어지려는 힘 계산
func _calculate_separation() -> Vector3:
	var force = Vector3.ZERO
	var neighbors = get_ships_cached(get_tree())
	var count = 0
	var separation_dist = 8.0 # 함선 폭/길이 고려 (8m)
	
	var max_checks = min(neighbors.size(), 15)
	for i in range(max_checks):
		var other = neighbors[i]
		if other == self or not is_instance_valid(other) or other.get("is_dying"):
			continue
			
		# 도선 중인 상대와는 분리력(Separation)을 적용하지 않음 (가까이 붙어야 하므로)
		if is_boarding and other == boarding_target:
			continue
		if other.get("boarding_attacker") == self:
			continue

			
		var dist = global_position.distance_to(other.global_position)
		if dist < separation_dist and dist > 0.001:
			var push_dir = (global_position - other.global_position).normalized()
			# 가까울수록 사정없이 강하게 밀어냄 (Quadratic curve 적용)
			var ratio = (separation_dist - dist) / separation_dist
			var strength = pow(ratio, 2.0)
			force += push_dir * strength
			count += 1
			
	if count > 0:
		force = (force / count) * 12.0 # 밀어내는 강도 계수 상향 (4.0 -> 12.0)
		
	return force

func _process_boarding(delta: float) -> void:
	if not is_instance_valid(boarding_target):
		die()
		return
	
	# 선체 고정 (플레이어 배 근처에 머물기)
	var target_pos = boarding_target.global_position
	var dist = global_position.distance_to(target_pos)
	
	if dist > 8.0: # 회피 거리(6.0)보다 약간 먼 거리까지 접근을 허용 (7.0 -> 8.0)
		var dir = (target_pos - global_position).normalized()
		global_position += dir * move_speed * 0.5 * delta
		
	# 회전도 플레이어 바라보게 유지
	var look_dir = (target_pos - global_position).normalized()
	var target_rot = atan2(-look_dir.x, -look_dir.z)
	rotation.y = lerp_angle(rotation.y, target_rot, delta * 2.0)
	
	# 베이스의 공통 도선 처리 (타이머, 전이, 밧줄 끊어짐 등)
	_process_boarding_common(delta)


func _find_player() -> void:
	var players = get_tree().get_nodes_in_group("player")
	
	# 나포된 미니언인 경우, 호위 대상인 플레이어 본선만 타겟으로 삼음
	if is_in_group("captured_minion") or team == "player":
		for p in players:
			if p.get("is_player_controlled") == true:
				target = p
				break
		return
		
	# 적군인 경우: 가장 가까운 아군(본선 및 나포함) 탐색
	var closest_dist = INF
	var closest_player = null
	
	for p in players:
		if p == self: continue # 자기 자신 제외
		if not p.get("is_sinking") and not p.get("is_dead"):
			var dist = global_position.distance_squared_to(p.global_position)
			# 본선(is_player_controlled)일 경우 약간의 스텔스 페널티(어그로 가중치)를 주어
			# 동일 거리면 본선을 더 치게 만들 수도 있지만, 일단 순수 거리 기반으로 가장 가까운 적을 찾음
			var weight = 1.0
			if p.get("is_player_controlled") == true:
				weight = 0.8 # 본선은 20% 더 가까운 것으로 취급 (어그로 약간 높음)
				
			var weighted_dist = dist * weight
			
			if weighted_dist < closest_dist:
				closest_dist = weighted_dist
				closest_player = p
				
	target = closest_player

## 나포(Capture) 처리
func capture_ship() -> void:
	if team == "player": return
	
	# 기존 함대 수 체크
	var minions = get_tree().get_nodes_in_group("captured_minion")
	if minions.size() >= 3:
		# ✅ 정원 초과 시 나포 대신 배를 파괴함
		print("[Limitation] 함대 정원 초과! 적함을 파괴합니다.")
		die()
		return
			
	team = "player"
	
	# ✅ 상태 초기화 및 긴급 수리 (나포 후 즉시 가라앉는 현상 방지)
	is_dying = false
	is_derelict = false
	is_burning = false
	fire_build_up = 0.0
	leaking_rate = 0.0
	hull_hp = max(hull_hp, max_hull_hp * 0.3) # 최소 30% 체력으로 복구
	
	# 철저한 물리적/시각적 리셋 (잠수함화 및 기울기 고정 방지)
	tilt_offset = 0.0
	rotation.x = 0.0
	rotation.z = 0.0
	base_y = 0.0 # 수면 높이 기준점 재설정
	global_position.y = 0.0
	
	# 실행 중일 수 있는 모든 트윈 애니메이션(침몰 모션 등) 강제 종료
	var tweens = get_tree().get_processed_tweens()
	for tween in tweens:
		# 이 노드나 관련 속성을 다루는 트윈이라고 확신할 순 없지만
		# Godot 4에서는 bind_node를 통해 엮인 트윈은 자동으로 정리되긴 함
		pass
	# 대신 명시적으로 y 위치를 고정해버림
	
	is_boarding = false
	boarding_target = null
	_clear_ropes()
	
	# 플레이어의 현재 업그레이드된 최대 속도를 상속받아 평준화 (기본치 3.2 대신)
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0 and players[0].get("is_player_controlled"):
		move_speed = players[0].get("max_speed")
	else:
		move_speed = 10.0 # 하드코딩된 예비값
	
	# 그룹 변경
	if is_in_group("enemy"): remove_from_group("enemy")
	add_to_group("player")
	add_to_group("captured_minion")
	
	# ✅ 물리 레이어 및 마스크 변경 (적군이 나포함을 인식하고 도선할 수 있게 함)
	# PlayerShip.tscn 기준: layer=2, mask=21 (1|4|16)
	# EnemyShip.tscn 기준: layer=4, mask=2 (도선 감지용)
	# 나포되면 레이어를 "Player" 레이어(비트값 2)로 변경하여 적의 mask=2에 걸리게 함
	set_deferred("collision_layer", 2)
	set_deferred("collision_mask", 21) # 1(환경) + 4(적선) + 16(기타)

	
	# 자식들(대포, 병사) 팀 변경 및 UI 알림
	_update_children_team()
	_apply_minion_visuals()
	
	if is_instance_valid(cached_lm) and cached_lm.has_method("show_message"):
		cached_lm.show_message("적군 함선을 나포했습니다!", 3.0)
	
	# 플레이어 업그레이드 스탯 적용 (수리 등)
	var upgrade_manager = get_node_or_null("/root/UpgradeManager")
	if is_instance_valid(upgrade_manager) and upgrade_manager.has_method("apply_fleet_stats_to_minion"):
		upgrade_manager.apply_fleet_stats_to_minion(self )
	
	# 나포 직후 플레이어를 찾아 즉시 따라가기 시작
	target = null
	_find_player()
	
	# ✅ 나포함 무장 자동 장착 (전방, 좌, 우)
	_equip_minion_cannons()
	
	print("[Capture] 나포 성공! 함대에 합류합니다. (target: %s)" % str(target))

func _equip_minion_cannons() -> void:
	if not cannon_scene: return
	
	# 장착 위치 정의 (전방, 좌측, 우측)
	var spawn_points = [
		{"pos": Vector3(0, 0.8, -3.5), "rot": 0}, # 전방
		{"pos": Vector3(-1.0, 0.8, -0.5), "rot": 90}, # 좌측 (90도 회전)
		{"pos": Vector3(1.0, 0.8, -0.5), "rot": - 90} # 우측 (-90도 회전)
	]
	
	for p in spawn_points:
		var cannon = cannon_scene.instantiate()
		add_child(cannon)
		cannon.position = p["pos"]
		cannon.rotation_degrees.y = p["rot"]
		# 팀 설정 (중요: 아군 오사 방지)
		if cannon.has_method("set_team"):
			cannon.set_team("player")
		elif "team" in cannon:
			cannon.set("team", "player")

func _update_children_team() -> void:
	# 대포 및 기타 컴포넌트 팀 변경 (재귀적 수행)
	for child in get_children():
		_recursive_set_team(child, "player")
			
	# 병사 팀 변경
	if has_node("Soldiers"):
		for s in $Soldiers.get_children():
			if s.has_method("set_team"):
				s.set_team("player")
				s.owned_ship = self

func _recursive_set_team(node: Node, new_team: String) -> void:
	if node.has_method("set_team"):
		node.set_team(new_team)
	if "team" in node:
		node.set("team", new_team)
	for child in node.get_children():
		_recursive_set_team(child, new_team)

func _apply_minion_visuals() -> void:
	# 돛 색상 변경 (흰색/파란색 조화) - instance uniform 사용
	for mast in masts:
		if mast.has_method("set_sail_color"):
			mast.set_sail_color(Color(0.9, 0.9, 1.0, 1.0)) # 밝은 하늘색/흰색
		if mast.has_method("set_team_color"):
			mast.set_team_color("player")
			
	# 연기 효과 중지 (폐선 상태에서 났던 것)
	if is_instance_valid(_fire_instance):
		_set_fire_emitting(false)


func _auto_adjust_sail(delta: float) -> void:
	if not is_instance_valid(_cached_wind_manager) or not _cached_wind_manager.has_method("get_wind_direction"): return
	var wind_dir = _cached_wind_manager.get_wind_direction()
	
	# ship.gd의 로직과 유사하게 자동 조절
	var ship_angle_rad = rotation.y
	var wind_angle_rad = atan2(wind_dir.x, wind_dir.y)
	
	var rel_wind_angle = rad_to_deg(wrapf(wind_angle_rad - ship_angle_rad, -PI, PI))
	var target_sail_angle = rel_wind_angle / 2.0
	target_sail_angle = clamp(target_sail_angle, -90, 90)
	
	sail_angle = move_toward(sail_angle, target_sail_angle, 60.0 * delta)

## 동양식 노(Ro/Yuloh) 8자 젓기 애니메이션
func _update_oar_visual(delta: float) -> void:
	var has_oars = oar_pivot_left or oar_pivot_right
	if not has_oars: return
	
	var is_moving = not is_derelict and move_speed > 0.5 and is_instance_valid(target)
	
	if is_moving:
		_oar_time += delta * 1.8 # 적함은 조금 더 느리고 장중하게 노를 저음
		
		# 8자 모션 (Lissajous curve 기반 Sculling)
		var sweep_angle = sin(_oar_time) * 0.2
		var twist_angle = sin(_oar_time * 2.0) * 0.1
		
		if oar_pivot_left:
			oar_pivot_left.rotation.x = sweep_angle
			oar_pivot_left.rotation.z = twist_angle
		if oar_pivot_right:
			oar_pivot_right.rotation.x = sweep_angle
			oar_pivot_right.rotation.z = - twist_angle
	else:
		if oar_pivot_left:
			oar_pivot_left.rotation.x = lerp_angle(oar_pivot_left.rotation.x, 0.0, delta * 2.0)
			oar_pivot_left.rotation.z = lerp_angle(oar_pivot_left.rotation.z, 0.0, delta * 2.0)
		if oar_pivot_right:
			oar_pivot_right.rotation.x = lerp_angle(oar_pivot_right.rotation.x, 0.0, delta * 2.0)
			oar_pivot_right.rotation.z = lerp_angle(oar_pivot_right.rotation.z, 0.0, delta * 2.0)

## 나포함 AI 로직 (플레이어 호위 및 적 탐지)
func _process_minion_ai(delta: float) -> void:
	if not is_instance_valid(target):
		_find_player()
		return
		
	# 1. 내 순번(Index) 확인 (캐시 사용으로 성능 최적화)
	var minions = get_minions_cached(get_tree())
	var my_index = minions.find(self )
	if my_index == -1: my_index = 0
	
	# 2. 진형에 따른 목표 상대 위치(Relative Target) 계산
	var offset = Vector3.ZERO
	
	# 2번째 배부터 적당한 간격으로 모이게 조절 (기존 너무 좁았던 것을 완화, 간격 통일)
	var base_spacing = 10.0
	var formation_dist = base_spacing + (my_index * base_spacing)
	
	match fleet_formation:
		Formation.COLUMN:
			# 군집(Swarm) 유지: 뒤로 길게 뻗지 않고 플레이어 바로 뒤쪽으로 밀집
			offset = Vector3(0, 0, formation_dist)
		Formation.WING:
			# 학익진: 좌우 번갈아가며 V자 배치 (간격 축소)
			var side = 1 if my_index % 2 == 0 else -1
			var row = floor(my_index / 2.0) + 1
			offset = Vector3(base_spacing * side * row, 0, base_spacing * row)
	
	# 3. 월드 목표 지점 계산
	var target_pos = target.to_global(offset)
	var dist_to_target = global_position.distance_to(target_pos)
	
	# 플레이어의 실제 현재 속도 가져오기 (동기화 용도)
	var player_speed = target.get("current_speed")
	if player_speed == null: player_speed = 0.0
	
	# 거리 및 위치 관계 상세 분석 (Overshoot Detection)
	var to_target_vec = (target_pos - global_position)
	var direction = to_target_vec.normalized()
	var player_fwd = - target.global_transform.basis.z # 플레이어가 바라보는 방향
	# 목표 지점이 내 뒤에 있는지 앞에 있는지 판별 (내적 이용)
	# rel_depth > 0: 내가 슬롯보다 뒤에 있음 (추격 필요)
	# rel_depth < 0: 내가 슬롯보다 앞에 있음 (브레이크 필요)
	var rel_depth = to_target_vec.dot(player_fwd)
	var dist_to_player = global_position.distance_to(target.global_position)
	
	# A. 속도 조절 (연속적 보간 및 평활화 적용)
	var target_final_speed = player_speed
	
	if dist_to_player < 10.0:
		# 최우선 순위: 물리적 충돌 방지 (완전 정지, 거리 대폭 단축)
		target_final_speed = 0.0
	elif rel_depth < -0.5:
		# 슬롯을 지나쳐 플레이어쪽으로 파고드는 경우 (연속적 브레이크)
		# 0m ~ 10m 사이를 보간하여 서서히 속도 감소
		var brake_factor = clamp(abs(rel_depth) / 10.0, 0.0, 0.9)
		target_final_speed = player_speed * (1.0 - brake_factor)
	else:
		# 뒤처졌거나 정렬 상태 (연속적 가속)
		# 0m(1.0배) ~ 40m(1.6배) 사이를 부드럽게 연결
		var lag_factor = clamp(rel_depth / 40.0, 0.0, 1.0)
		var sync_speed_mult = lerp(1.0, 1.6, lag_factor)
		target_final_speed = max(player_speed * sync_speed_mult, move_speed * 0.8)
		
	# 시간차 부드러움 적용 (Temporal Smoothing)
	# 이전 프레임 속도에서 목표 속도로 서서히 변화시켜 '멈칫'하는 현상 제거
	_last_ai_speed = lerp(_last_ai_speed, target_final_speed, delta * 2.5)
	var final_move_speed = _last_ai_speed
		
	# B. 방향 조절 (Broadside Alignment)
	var target_head_rot = atan2(-direction.x, -direction.z) # 목표 슬롯을 향하는 기본 각도
	var player_head_rot = rotation.y # 기본값은 자기 자신
	if target and "rotation" in target:
		player_head_rot = target.rotation.y
		
	# 거리가 가까울수록 목표지점을 보는 대신, 플레이어와 완벽하게 수평을 맞춤(Broadside 유지)
	var rotation_blend = clamp(dist_to_target / 15.0, 0.0, 1.0)
	
	if dist_to_target > 1.5:
		# 멀 때는 슬롯을 향해 주로 보고, 가까워질수록 플레이어와 나란해짐
		var blended_rot = lerp_angle(player_head_rot, target_head_rot, rotation_blend)
		rotation.y = lerp_angle(rotation.y, blended_rot, delta * 2.5)
		# 실제 이동 (플레이어 속도 동기화 + 반발력 적용)
		var velocity = Vector3.FORWARD * final_move_speed
		# translate는 로컬 좌표계 기준이므로, separation_force(월드)를 로컬로 변환하거나 
		# 혹은 global_position을 직접 조작하는 편이 안전함. 여기서는 translate를 global_translate로 대체 고려.
		global_translate(velocity.rotated(Vector3.UP, rotation.y) * delta + separation_force * delta)
	elif dist_to_target > 0.4:
		# 근접 정렬 단계 (플레이어와 거의 평행 유지)
		rotation.y = lerp_angle(rotation.y, player_head_rot, delta * 3.0)
		var sync_speed = lerp(move_speed * 0.5, player_speed, 0.5)
		global_translate(Vector3.FORWARD.rotated(Vector3.UP, rotation.y) * sync_speed * delta + separation_force * delta)
	else:
		# 완전 안착 상태 (플레이어와 완벽 동기화)
		rotation.y = lerp_angle(rotation.y, player_head_rot, delta * 4.0)
		if player_speed > 0.1:
			global_translate(Vector3.FORWARD.rotated(Vector3.UP, rotation.y) * player_speed * delta + separation_force * delta)
			
	# [추가] 나포함 이동 시에도 수면 높이 유지 및 둥실둥실 효과 적용
	_apply_bobbing_effect()
	
	if wake_trail:
		wake_trail.emitting = dist_to_target > 2.0 or player_speed > 1.0

func _update_wave_sounds(delta: float) -> void:
	if is_dying or is_derelict: return
	
	# 현재 속도 대략적 파악 (적함/나포함 공통 로직을 위해)
	# 여기서는 move_speed와 이동 여부로 판단
	var speed = move_speed
	# 멈춰있을 때는 소리 안나게 (target 없거나 거리 가까워서 멈춘 경우 등)
	if not is_instance_valid(target): speed = 0.0
	
	if speed > 0.5:
		_wave_timer -= delta
		if _wave_timer <= 0:
			if is_instance_valid(_cached_audio_manager) and _cached_audio_manager.has_method("play_sfx"):
				_cached_audio_manager.play_sfx("wave_splash", global_position, randf_range(0.8, 1.2))
			var speed_mod = clamp(speed / 5.0, 0.4, 1.5)
			_wave_timer = randf_range(2.0, 4.5) / speed_mod

func _update_minion_respawn(delta: float) -> void:
	var soldiers_node = get_node_or_null("Soldiers")
	if not soldiers_node: return
	
	var alive_count = 0
	for child in soldiers_node.get_children():
		if child.get("current_state") != 4: # NOT DEAD
			alive_count += 1
			
	if alive_count < max_minion_crew:
		minion_respawn_timer += delta
		if minion_respawn_timer >= minion_respawn_interval:
			minion_respawn_timer = 0.0
			_respawn_minion_soldier()

func _respawn_minion_soldier() -> void:
	if not soldier_scene: return
	var s = soldier_scene.instantiate()
	$Soldiers.add_child(s)
	s.set_team("player")
	s.owned_ship = self
	var offset = Vector3(randf_range(-1.0, 1.0), 0, randf_range(-2.0, 2.0))
	s.position = offset
	print("[Crew] 나포함 병사 자생적 보충 완료.")


## 충돌 감지 (Area3D signal 연결 필요)
func _on_body_entered(body: Node3D) -> void:
	# 플레이어와 충돌했는지 확인 (StaticBody/CharacterBody 등)
	if body.is_in_group("player") or (body.get_parent() and body.get_parent().is_in_group("player")):
		_board_ship(body)

func _on_area_entered(area: Area3D) -> void:
	# 본선(ProximityArea 자식) 또는 나포함(Area3D 본체)과 충돌했는지 확인
	if area.is_in_group("player"):
		_board_ship(area)
	else:
		var parent = area.get_parent()
		if parent and parent.is_in_group("player"):
			_board_ship(parent)


func remove_stuck_object(_obj: Node3D, _s_mult: float, _t_mult: float) -> void:
	tilt_offset *= 0.5
	if tilt_offset < 0.01: tilt_offset = 0.0

func _board_ship(target_ship: Node3D) -> void:
	if is_dying or is_boarding: return
	
	var ship_node = target_ship
	if not ship_node.is_in_group("player"):
		ship_node = target_ship.get_parent()
		if not (ship_node and ship_node.is_in_group("player")):
			return
			
	# === 아군 체크 (동일 팀이면 도선 무시) ===
	if ship_node.get("team") == team:
		return
		
	# === 플레이어 팀 체크 (상대 배에 올라타는 것 제한) ===
	# 나포(Capture) 상황이 아닌 일반 전투 중에는 아군 병사가 적선으로 넘어가지 않게 함
	if team == "player":
		return

	# === 무력화(폐선) 상태인 배는 이미 도선이 불필요함 (나포는 ship.gd의 boarding scan으로 처리) ===
	if is_derelict:
		return

	# 1. 초기 충돌 효과 (최초 1회만)
	if not has_rammed:
		has_rammed = true
		var ram_damage = move_speed * 4.0
		if ship_node.has_method("take_damage"):
			ship_node.take_damage(ram_damage, global_position)
			# 상대 배 갑판 병사들에게 광역 데미지 (충돌 위치 기준, 15 고정데미지)
			if ship_node.has_method("apply_ramming_aoe"):
				ship_node.apply_ramming_aoe(15.0, global_position)
				
		# 자신 자신에게 시각적 파편 효과를 위해 데미지 (죽지는 않을 정도)
		take_damage(1.0, global_position)
		# 자기 배 갑판 병사들에게도 여파 (5 데미지)
		apply_ramming_aoe(5.0, global_position)
		
		# 충격 피드백 강화 (화면 흔들림 및 묵직한 사운드)
		if is_instance_valid(_cached_audio_manager) and _cached_audio_manager.has_method("play_sfx"):
			_cached_audio_manager.play_sfx("impact_wood", global_position, randf_range(0.6, 0.8)) # 더 낮고 묵직한 피치
		
		var cam = get_viewport().get_camera_3d()
		if cam and cam.has_method("shake"):
			# 대포보다는 길고 묵직한 진동 (세기 0.4, 시간 0.3초)
			cam.shake(0.4, 0.3)
			
		print("[Impact] 충격적 충돌 발생! 도선 시작.")

	# 2. 도선 상태 진입
	is_boarding = true
	boarding_target = ship_node
	
	# 도선 대상에게 내가 공격자임을 알림 (사격 중지 규칙용)
	if boarding_target.has_method("set") or "boarding_attacker" in boarding_target:
		boarding_target.set("boarding_attacker", self )
		
	boarding_timer = 0.0
	boarding_prep_timer = 0.0
	
	# 그레플링 훅 생성
	if is_instance_valid(boarding_target):
		_spawn_ropes()

# 누수 추가/제거
func add_leak(amount: float) -> void:
	leaking_rate += amount
	print("[Status] 누수 발생! 초당 데미지: %.1f" % leaking_rate)

func remove_leak(amount: float) -> void:
	leaking_rate = maxf(0.0, leaking_rate - amount)
	print("[Status] 누수 완화. 남은 누수율: %.1f" % leaking_rate)
