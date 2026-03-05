@tool
extends "res://scripts/entities/base_ship.gd"
class_name ChaserShip

## 추적선 (Chaser Ship)
## 플레이어를 단순 추적하고, 충돌 시 병사를 도선(Boarding)시키고 자폭

@export var team: String = "enemy" # "enemy" or "player"
@export var move_speed: float = 3.5
@export var soldier_scene: PackedScene = preload("res://scenes/soldier.tscn")
@export var boarders_count: int = 4 # 도선시킬 병사 수 (상향: 2 -> 4)

@export var cannon_scene: PackedScene = preload("res://scenes/entities/cannon_japanese.tscn")
@export var hull_scene: PackedScene = preload("res://scenes/ships/hulls/sekibune_hull.tscn")
@export var preferred_soldier_type: String = "general" ## "general", "melee", "ranged"
@export var ship_type: String = "sekibune_melee":
	set(value):
		ship_type = value
		if Engine.is_editor_hint():
			_update_editor_hull()
var has_cannons: bool = true ## JSON에서 로드됨

var target: Node3D = null

# 상태 (State)
var leaking_rate: float = 0.0


@export var minion_respawn_interval: float = 15.0
@export var max_minion_crew: int = 4 # 아군 나포함 최대 정원
var minion_respawn_timer: float = 0.0

@export var max_crew: int = 6 # 적선 최대 정원
var enemy_respawn_timer: float = 0.0
@export var enemy_respawn_interval: float = 12.0 # 적군 충원 간격 (12초)

# === 적 AI 조타 튜닝 ===
@export_range(0.5, 3.0) var ai_rudder_gain: float = 1.2
@export_range(20.0, 160.0) var ai_rudder_response_speed: float = 70.0
@export_range(10.0, 80.0) var ai_max_turn_rate: float = 30.0 # deg/s
@export_range(0.2, 1.0) var ai_turn_authority: float = 0.7
@export_range(4.0, 24.0) var ai_close_turn_soft_radius: float = 12.0
@export_range(0.2, 1.0) var ai_close_turn_scale: float = 0.6


# === 함대 진형 (Formation) 관련 ===
enum Formation {COLUMN, WING}
static var fleet_formation: Formation = Formation.COLUMN # 공유 진형 설정 (기본: 장사진)

var formation_spacing: float = 14.0 # 선박 간 간격 축소 (밀집 대형)

var _wave_timer: float = 0.0 # 물결 소리 타이머
var _last_ai_speed: float = 0.0 # 속도 평활화를 위한 이전 프레임 속도 저장
var _oar_time: float = 0.0

# [신규] 스태미나 시스템 (돌격용)
var stamina: float = 100.0
var max_stamina: float = 100.0
var is_sprinting: bool = false
var sprint_multiplier: float = 1.5

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
var _merit_granted: bool = false # 공적 중복 획득 방지

func get_radius() -> float:
	return 2.5 # 대략적인 선체 반경 (상황에 맞게 조정)

func _become_derelict() -> void:
	is_derelict = true
	
	# 도선 중지 (더 이상 밧줄 유지 안 함)
	is_boarding = false
	_clear_ropes()
	target = null
	
	# LevelManager 캐싱 (공적 획득 전에 먼저 찾아야 함)
	if not is_instance_valid(cached_lm):
		cached_lm = get_tree().root.find_child("LevelManager", true, false)
		if not cached_lm:
			var lm_nodes = get_tree().get_nodes_in_group("level_manager")
			if lm_nodes.size() > 0: cached_lm = lm_nodes[0]
	
	# 공적 포인트(Merit) 획득
	if not _merit_granted:
		if is_instance_valid(cached_lm) and cached_lm.has_method("add_merit"):
			cached_lm.add_merit(20) # 20 공적 포인트 스펙
			_merit_granted = true
	
	if wake_trail: wake_trail.emitting = false
	
	print("[Status] 선원 전멸! 적함이 폐선(Derelict) 상태가 되었습니다.")
	
	# 침몰 속도 대폭 증가 (누수 가속)
	leaking_rate += 1.5
	
	if boarders_count > 0:
		boarders_count = 0 # 폐선은 더 이상 도선시키지 않음
		
	# 물리적 저항 약화 (길막 방어 반경 축소)
	base_collision_radius *= 0.8
	_sync_profile_from_runtime()
	
	if wake_trail: wake_trail.emitting = false
	
	# 즉각적인 시각적 피드백: 더 많이 기울어지고 조금 가라앉음
	var tilt_tween = create_tween()
	tilt_tween.tween_property(self , "rotation_degrees:z", 15.0, 1.5).set_ease(Tween.EASE_OUT)
	tilt_tween.set_parallel(true)
	tilt_tween.tween_property(self , "position:y", base_y - 1.0, 2.0)
	
	# 5초 뒤 완전 침몰 (15s -> 5s)
	get_tree().create_timer(5.0).timeout.connect(func():
		if is_instance_valid(self ) and not is_sinking:
			_sink_derelict()
	)

func _sink_derelict() -> void:
	if is_sinking: return
	is_sinking = true
	print("[Ship] 폐선 침몰 시작!")
	
	# 침몰 화염 연산
	_set_fire_emitting(true)
	
	var sink_tween = create_tween()
	# 가라앉는 속도 대폭 상향 (10.0 -> 5.0)
	sink_tween.tween_property(self , "global_position:y", base_y - 15.0, 5.0).set_ease(Tween.EASE_IN)
	sink_tween.parallel().tween_property(self , "rotation_degrees:x", randf_range(-20.0, 20.0), 5.0)
	sink_tween.parallel().tween_property(self , "rotation_degrees:z", randf_range(20.0, 40.0) * (1 if randf() > 0.5 else -1), 5.0)
	
	await sink_tween.finished
	queue_free()

func _check_offscreen_despawn() -> void:
	var players = get_tree().get_nodes_in_group("player")
	if players.is_empty(): return
	var p = players[0]
	
	var dist = global_position.distance_to(p.global_position)
	if dist > 150.0: # 150미터 이상 멀어지면 화면 밖으로 간주하고 삭제
		print("[Ship] 폐선이 완전히 표류하여 사라집니다.")
		queue_free()

func _update_editor_hull() -> void:
	# 에디터 전용: 선체 미리보기 갱신
	for child in get_children():
		if child.name.contains("Hull"):
			child.free()
	
	var stats = load_ship_stats(ship_type)
	if stats.is_empty(): return
	
	# 함종에 따른 선체 씬 경로 결정 (임시 매핑 - 나포 시스템 등에서 정의한 것과 동일하게)
	var type_lower = ship_type.to_lower()
	var h_path = "res://scenes/ships/hulls/sekibune_hull.tscn"
	if type_lower.contains("panokseon"): h_path = "res://scenes/ships/hulls/panokseon_hull.tscn"
	elif type_lower.contains("atakebune"): h_path = "res://scenes/ships/hulls/atakebune_hull.tscn"
	elif type_lower.contains("maengseon"): h_path = "res://scenes/ships/hulls/maengseon_hull.tscn"
	
	var new_hull = load(h_path)
	if new_hull:
		var inst = new_hull.instantiate()
		inst.name = "EditorHull"
		add_child(inst)
		_cache_hull_references(self ) # BaseShip 메서드 호출

func _ready() -> void:
	if Engine.is_editor_hint():
		# 이미 에디터용 Hull이 있다면 중복 생성 방지
		var has_hull = false
		for child in get_children():
			if child.name.contains("Hull"):
				has_hull = true
				break
		if not has_hull:
			_update_editor_hull()
		return

	# JSON 데이터 로드 및 적용
	var stats = load_ship_stats(ship_type)
	if not stats.is_empty():
		if stats.has("hull_hp"): max_hull_hp = stats["hull_hp"]
		if stats.has("move_speed"): move_speed = stats["move_speed"]
		if stats.has("boarders"): boarders_count = stats["boarders"]
		if stats.has("has_cannons"): has_cannons = stats["has_cannons"]
		if stats.has("soldier_type"): preferred_soldier_type = stats["soldier_type"]
		
	# 선체(Hull) 씬 인스턴스화 및 추가 (런타임)
	# 수동으로 지정된 hull_scene이 있으면 사용, 없으면 ship_type에 맞게 로드
	if is_instance_valid(hull_scene):
		var hull_inst = hull_scene.instantiate()
		add_child(hull_inst)
	else:
		_update_editor_hull()
		
	super._ready()
	if max_hull_hp <= 0: max_hull_hp = 60.0 # Default fallback
	global_position.y = base_y # Keep base_y assignment from BaseShip valid
	_find_player()
	
	# 대포 없는 함선(Chaser)일 경우 자식 중 Cannon 노드들 제거
	if not has_cannons:
		_remove_all_cannons()
	
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
		_equip_minion_cannons()
		if is_instance_valid(UpgradeManager):
			UpgradeManager.apply_fleet_upgrades_to_ship(self )
	else:
		add_to_group("enemy")
	
	_setup_soldiers() # 모든 함선 초기 병사 배치 (팀 속성 반영)
		
	_find_player()
	
	cached_lm = get_tree().root.find_child("LevelManager", true, false)
	if not cached_lm:
		var lm_nodes = get_tree().get_nodes_in_group("level_manager")
		if lm_nodes.size() > 0: cached_lm = lm_nodes[0]
	
	_cached_wind_manager = get_node_or_null("/root/WindManager")
	_sync_contact_area_layers()
	_set_contact_areas_enabled(true)

func _sync_contact_area_layers(layer_override: int = -1) -> void:
	var current_layer: int = layer_override
	if current_layer < 0:
		var layer_val = get("collision_layer")
		current_layer = int(layer_val) if layer_val != null else 4
	var proximity_area = get_node_or_null("ProximityArea")
	if proximity_area is Area3D:
		proximity_area.set_deferred("collision_layer", current_layer)
		# 도선/접근 감지는 플레이어 레이어(2)만 본다.
		proximity_area.set_deferred("collision_mask", 2)
		
	var hit_area = get_node_or_null("HitArea")
	if hit_area is Area3D:
		hit_area.set_deferred("collision_layer", current_layer)
		# 피격 영역은 다른 Area를 능동 감지할 필요가 없다.
		hit_area.set_deferred("collision_mask", 0)

func _set_contact_areas_enabled(enabled: bool) -> void:
	var proximity_area = get_node_or_null("ProximityArea")
	if proximity_area is Area3D:
		proximity_area.set_deferred("monitoring", enabled)
		proximity_area.set_deferred("monitorable", enabled)
		var prox_shape = proximity_area.get_node_or_null("CollisionShape3D")
		if prox_shape is CollisionShape3D:
			prox_shape.set_deferred("disabled", not enabled)
			
	var hit_area = get_node_or_null("HitArea")
	if hit_area is Area3D:
		hit_area.set_deferred("monitoring", enabled)
		hit_area.set_deferred("monitorable", enabled)
		var hit_shape = hit_area.get_node_or_null("CollisionShape3D")
		if hit_shape is CollisionShape3D:
			hit_shape.set_deferred("disabled", not enabled)

func _setup_soldiers() -> void:
	if not soldier_scene: return
	var soldiers_node = get_node_or_null("Soldiers")
	if not soldiers_node: return
	
	# ✅ 기존에 씬에 배치된 병사가 있다면 제거 (중복 및 팀 믹스 방지)
	for child in soldiers_node.get_children():
		child.queue_free()
	
	# 함선 팀에 맞춰 초기 4명 배치
	for i in range(4):
		_spawn_one_soldier(team)

func _spawn_one_soldier(s_team: String) -> void:
	var s = soldier_scene.instantiate()
	$Soldiers.add_child(s)
	s.set_team(s_team)
	s.owned_ship = self
	s.home_ship = self
	
	# 함선 설정에 따른 병종 설정
	if preferred_soldier_type == "melee":
		s.is_melee_only = true
	elif preferred_soldier_type == "ranged":
		s.is_ranged_only = true
		
	var offset = Vector3(randf_range(-1.0, 1.0), 0.5, randf_range(-2.5, 2.5))
	s.position = offset


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
		if team == "enemy" and cached_lm.has_method("add_ship_sunk"):
			cached_lm.add_ship_sunk(1)
		if cached_lm.has_method("add_score"):
			cached_lm.add_score(100)
		if cached_lm.has_method("add_xp"):
			cached_lm.add_xp(30)
			
		# 공적 포인트(Merit) 추가 (격침 시에도 부여, 중복 방지)
		if not _merit_granted and cached_lm.has_method("add_merit"):
			cached_lm.add_merit(20)
			_merit_granted = true
	
	# 물리 및 충돌 비활성화 (Area3D 대응)
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	_set_contact_areas_enabled(false)
		
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
		
	if team == "player":
		_update_minion_respawn(delta)
	elif team == "enemy" and not is_derelict:
		_update_enemy_reinforcement(delta)

func _update_enemy_reinforcement(delta: float) -> void:
	var alive_count = get_alive_crew_count()
	if alive_count < max_crew:
		enemy_respawn_timer += delta
		if enemy_respawn_timer >= enemy_respawn_interval:
			enemy_respawn_timer = 0.0
			_spawn_one_soldier("enemy")
			print("[Reinforcement] 적 함선에 병사가 보충되었습니다. (현재: %d)" % (alive_count + 1))


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint(): return
	
	if is_dying: return
	
	_update_wave_sounds(delta)
	
	# 1. 고비용 로직 스로틀링 (0.2초 간격) - 모든 상태(미니언/적/도선/폐선) 공통
	logic_timer -= delta
	var do_logic_update = false
	if logic_timer <= 0:
		logic_timer = 0.2
		do_logic_update = true
		
	# === 폐선(Derelict) 체크 ===
	if is_derelict:
		# 폐선 상태면 조종(AI)을 멈추고 바람 방향을 따라 표류함
		if is_instance_valid(WindManager):
			var wind_dir_v2 = WindManager.wind_direction
			var wind_dir = Vector3(wind_dir_v2.x, 0, wind_dir_v2.y)
			var wind_force = WindManager.wind_strength * 0.4 # 최대 속도 미만으로 천천히 표류
			position += wind_dir * wind_force * delta
			
			# 선수 방향도 바람 방향으로 서서히 돌아가게 함
			var target_rot = atan2(-wind_dir.x, -wind_dir.z)
			rotation.y = lerp_angle(rotation.y, target_rot, delta * 0.5)
			
		if wake_trail: wake_trail.emitting = false
		
		# 멀리 떨어지면 삭제 (Despawn)
		if do_logic_update:
			_check_offscreen_despawn()
		return

	# 공통 로직 업데이트 실행 (분리력 계산, 타겟 최신화 등)
	if do_logic_update:
		_update_logic_throttled()

	# 0. 아군 나포함(Minion)은 전용 AI 수행 (최우선)
	if team == "player":
		_process_minion_ai(delta)
		return

	# 도선(Boarding) 상태 로직
	if is_boarding:
		_process_boarding(delta)
		return

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

	# 3. 이동 및 회전 (Rudder 물리 기반)
	var move_dir = (target_pos - global_position).normalized()
	
	# Separation (함선 간 겹침 방지) - 계산은 스로틀링됨
	if separation_force.length_squared() > 0.001:
		# 분리력을 이동 방향에 부드럽게 합성 (강도 1.5배 적용)
		move_dir = (move_dir + separation_force * 1.5).normalized()
	
	# 목표 각도 계산 (단순 추적)
	var target_rotation_y = atan2(-move_dir.x, -move_dir.z)
	
	# 러더(Rudder) 조향 시스템 적용
	var angle_diff = wrapf(target_rotation_y - rotation.y, -PI, PI)
	var desired_rudder = clamp(-rad_to_deg(angle_diff) * ai_rudder_gain, -40.0, 40.0)
	var close_turn_blend = 0.0
	if ai_close_turn_soft_radius > 0.01:
		close_turn_blend = clamp(1.0 - (dist_to_player / ai_close_turn_soft_radius), 0.0, 1.0)
	var close_turn_factor = lerp(1.0, ai_close_turn_scale, close_turn_blend)
	desired_rudder *= close_turn_factor
	var rudder_speed_adjusted = ai_rudder_response_speed
	rudder_angle = move_toward(rudder_angle, desired_rudder, rudder_speed_adjusted * delta)
	
	# 전진 (누수율에 비례하여 기본 목표 속도 감소)
	var leak_speed_mult = clamp(1.0 - (leaking_rate * 0.05), 0.3, 1.0)
	var desired_speed = move_speed * leak_speed_mult
	
	# 목표와 매우 가까울 때만 약하게 감속 (충돌 전 멈춤 방지)
	if dist_to_player < 4.4:
		var slow_factor = clamp((dist_to_player - 1.4) / 3.0, 0.88, 1.0)
		desired_speed *= slow_factor
		is_sprinting = false # 가까우면 돌격 중지
	else:
		# [신규] 스태미나 기반 돌격(Sprint) 로직 (적군 전용, 미니언 제외)
		if team == "enemy":
			if not is_sprinting and dist_to_player > 10.0 and dist_to_player < 28.0 and stamina > 30.0:
				is_sprinting = true
			if is_sprinting and (stamina <= 0.0 or dist_to_player <= 8.0):
				is_sprinting = false
				
			if is_sprinting:
				stamina = max(0.0, stamina - 20.0 * delta)
				desired_speed *= sprint_multiplier
			else:
				stamina = min(max_stamina, stamina + 15.0 * delta)
		
	# 가감속 처리
	if desired_speed > current_speed:
		current_speed = move_toward(current_speed, desired_speed, acceleration * delta)
	else:
		current_speed = move_toward(current_speed, desired_speed, deceleration * delta)
	
	# 속도가 있어야 회전 가능 (실제 배처럼)
	if current_speed > 0.1:
		var speed_ratio = clamp(current_speed / maxf(max_speed, 0.01), 0.0, 1.0)
		var turn_scale = ai_turn_authority * close_turn_factor
		var actual_turn = (rudder_angle / 45.0) * turn_rate * speed_ratio * turn_mult * turn_scale * delta
		var max_turn_this_frame = ai_max_turn_rate * delta
		actual_turn = clamp(actual_turn, -max_turn_this_frame, max_turn_this_frame)
		rotation.y -= deg_to_rad(actual_turn)
	
	# === 바람 영향(Wind Force) 적용 ===
	var wind_mult = 1.0
	if is_instance_valid(_cached_wind_manager) and _cached_wind_manager.has_method("get_wind_direction"):
		var wind_dir: Vector2 = _cached_wind_manager.get_wind_direction()
		var wind_str: float = _cached_wind_manager.get_wind_strength()
		
		# 배의 전방 벡터 (2D 평면 기준)
		var ship_forward = Vector2(-sin(rotation.y), -cos(rotation.y)).normalized()
		var dot_prod = wind_dir.dot(ship_forward)
		var base_wind_influence = remap(dot_prod, -1.0, 1.0, 0.4, 1.5)
		wind_mult = lerp(1.0, base_wind_influence, wind_str)
	
	# 선체 전진 벡터를 사용 (Vector 물리 방식에서 Kinematic 물리 방식으로 전환)
	var forward_vec = Vector3(-sin(rotation.y), 0, -cos(rotation.y))
	var velocity = forward_vec * current_speed * wind_mult
	
	# === 겹침 방지 (Separation) 적용 ===
	# 겹침 방지 밀어냄은 속도 벡터에 더해 밀리게 함
	velocity += separation_force
	
	# === 도선 인동력(Pull) 및 겹침 방지 반발력(Collision Repulsion) 적용 ===
	velocity += _calculate_boarding_pull() * delta
	var collision_repulsion = _calculate_collision_repulsion()
	# 교전 직전에는 반발력을 일부 완화해 실제 선체 접촉이 일어나게 함
	if dist_to_player < max_boarding_distance + 1.2:
		var to_target_flat = target.global_position - global_position
		to_target_flat.y = 0.0
		if to_target_flat.length_squared() > 0.001:
			var approach_dot = forward_vec.normalized().dot(to_target_flat.normalized())
			if approach_dot > 0.3:
				collision_repulsion *= 0.35
	velocity += collision_repulsion * delta
	
	# === 위치 업데이트 ===
	var prev_pos = global_position
	var next_pos = prev_pos + velocity * delta
	if is_instance_valid(target):
		next_pos = _apply_ship_collision_guard(target, prev_pos, next_pos, 0.985, velocity.length())
	# 타겟 외 주변 함선과의 겹침도 보정 (적함-적함 통과/겹침 방지)
	next_pos = _apply_neighbor_ship_guards(prev_pos, next_pos, target)
	global_position = next_pos
	
	# 비주얼 타륜 업데이트 (시각 효과)
	_update_rudder_visual()
	
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
	
	var _max_checks = min(neighbors.size(), 15)
	for i in range(_max_checks):
		var other = neighbors[i]
		if other == self or not is_instance_valid(other) or other.get("is_dying"):
			continue
			
		# 도선 중인 상대와는 분리력(Separation)을 적용하지 않음 (가까이 붙어야 하므로)
		if is_boarding and other == boarding_target:
			continue
		if other.get("boarding_attacker") == self:
			continue

		var offset = global_position - other.global_position
		offset.y = 0.0
		var dist_sq = offset.length_squared()
		if dist_sq <= 0.01:
			continue
		
		var dist = sqrt(dist_sq)
		var coll_dist = get_collision_distance_to(other)
		# 현재 추격 타겟과는 접촉 직전까지 분리력을 제거해 정박/충돌이 가능하도록 함
		if is_instance_valid(target) and other == target and dist < coll_dist + 1.2:
			continue
		var separation_trigger_dist = coll_dist + 0.35
		
		if dist < separation_trigger_dist:
			var push_dir = offset.normalized()
			var ratio = (separation_trigger_dist - dist) / max(separation_trigger_dist, 0.001)
			var strength = pow(ratio, 2.0)
			force += push_dir * strength
			count += 1
			
	if count > 0:
		force = (force / count) * 2.2
		
	return force

func _process_boarding(delta: float) -> void:
	if not is_instance_valid(boarding_target):
		die()
		return
	var target_pos = boarding_target.global_position
	var flat_to_target = target_pos - global_position
	flat_to_target.y = 0.0
	var dist_to_target = flat_to_target.length()
	
	# 회전: 플레이어 바라보기
	var look_dir = flat_to_target.normalized() if dist_to_target > 0.001 else Vector3.FORWARD
	var target_rot = atan2(-look_dir.x, -look_dir.z)
	rotation.y = lerp_angle(rotation.y, target_rot, delta * 2.0)
	
	# 도선 중에는 정박 거리까지 능동적으로 붙고, 이후에는 밧줄 장력으로 유지한다.
	var desired_boarding_speed := 0.0
	if dist_to_target > (max_boarding_distance - 0.6):
		desired_boarding_speed = clamp((dist_to_target - (max_boarding_distance - 0.6)) * 1.6, 1.1, move_speed * 0.9)
	elif dist_to_target > 6.5:
		desired_boarding_speed = 0.9
	current_speed = move_toward(current_speed, desired_boarding_speed, acceleration * 2.0 * delta)
	
	var approach_velocity = look_dir * current_speed
	var pull_force = _calculate_boarding_pull()
	var prev_pos = global_position
	var next_pos = prev_pos + (approach_velocity + pull_force * delta) * delta
	if is_instance_valid(boarding_target):
		next_pos = _apply_ship_collision_guard(boarding_target, prev_pos, next_pos, 0.975, approach_velocity.length())
	next_pos = _apply_neighbor_ship_guards(prev_pos, next_pos, boarding_target)
	global_position = next_pos
	
	# 시각 효과
	_apply_bobbing_effect()
	
	# 베이스의 공통 도선 처리 (타이머, 전이, 밧줄 끊어짐 등)
	_process_boarding_common(delta)

func _apply_neighbor_ship_guards(prev_pos: Vector3, proposed_pos: Vector3, excluded_ship: Node3D = null) -> Vector3:
	var corrected_pos = proposed_pos
	var neighbors = get_ships_cached(get_tree())
	var check_count = 0
	
	for other in neighbors:
		if other == self or not is_instance_valid(other):
			continue
		if other == excluded_ship:
			continue
		if other.get("is_dying") or other.get("is_sinking"):
			continue
			
		# 가까운 후보만 처리해서 연산량을 제한
		var safe_probe = get_collision_distance_to(other) * 1.25
		var diff = corrected_pos - other.global_position
		diff.y = 0.0
		if diff.length_squared() > safe_probe * safe_probe:
			continue
			
		corrected_pos = _apply_ship_collision_guard(other, prev_pos, corrected_pos, 0.99, current_speed, false)
		check_count += 1
		if check_count >= 6:
			break
			
	return corrected_pos

func _apply_ship_collision_guard(other_ship: Node3D, prev_pos: Vector3, proposed_pos: Vector3, safe_ratio: float = 0.94, impact_speed_hint: float = 0.0, emit_collision_event: bool = true) -> Vector3:
	if not is_instance_valid(other_ship):
		return proposed_pos
	if other_ship.get("is_dying") or other_ship.get("is_sinking"):
		return proposed_pos
		
	var target_pos = other_ship.global_position
	var safe_dist = get_collision_distance_to(other_ship) * safe_ratio
	if safe_dist <= 0.01:
		return proposed_pos
		
	var from_2d = Vector2(prev_pos.x - target_pos.x, prev_pos.z - target_pos.z)
	var to_2d = Vector2(proposed_pos.x - target_pos.x, proposed_pos.z - target_pos.z)
	var move_2d = to_2d - from_2d
	var a = move_2d.dot(move_2d)
	
	# 1) 스윕 교차 검사: 한 프레임에 경계를 건너뛰는 통과(터널링) 방지
	if a > 0.00001:
		var b = 2.0 * from_2d.dot(move_2d)
		var c = from_2d.dot(from_2d) - safe_dist * safe_dist
		if c > 0.0:
				var disc = b * b - 4.0 * a * c
				if disc >= 0.0:
					var sqrt_disc = sqrt(disc)
					var t = (-b - sqrt_disc) / (2.0 * a)
					if t >= 0.0 and t <= 1.0:
						var hit_t = maxf(0.0, t - 0.02)
						var hit_pos = prev_pos.lerp(proposed_pos, hit_t)
						var n2 = Vector2(hit_pos.x - target_pos.x, hit_pos.z - target_pos.z)
						if n2.length_squared() < 0.0001:
							n2 = Vector2(-sin(rotation.y), -cos(rotation.y))
						n2 = n2.normalized()
						hit_pos.x = target_pos.x + n2.x * safe_dist
						hit_pos.z = target_pos.z + n2.y * safe_dist
						if emit_collision_event:
							_emit_guarded_collision(other_ship, impact_speed_hint)
						_soften_collision_speed()
						return hit_pos
	
	# 2) 이동 후 겹침 보정: 이미 파고든 상태면 경계까지 밀어냄
	var diff = proposed_pos - target_pos
	diff.y = 0.0
	var dist = diff.length()
	if dist < safe_dist:
		var n = diff.normalized() if dist > 0.001 else Vector3(-sin(rotation.y), 0.0, -cos(rotation.y))
		proposed_pos.x = target_pos.x + n.x * safe_dist
		proposed_pos.z = target_pos.z + n.z * safe_dist
		if emit_collision_event:
			_emit_guarded_collision(other_ship, impact_speed_hint)
		_soften_collision_speed()
		
	return proposed_pos

func _emit_guarded_collision(other_ship: Node3D, impact_speed_hint: float) -> void:
	# 가드에 막히는 순간을 실제 충돌로 처리해 '닿지 않는 느낌'을 줄인다.
	if not is_instance_valid(other_ship):
		return
	# 가드 충돌은 실제 충돌과 동일하게 양쪽 피해를 적용한다.
	# 근접 보정으로 접근 속도가 깎였더라도 최소 충돌 속도는 확보한다.
	var impact_speed = maxf(impact_speed_hint, min_ramming_speed * 0.72)
	apply_ramming_damage(other_ship, impact_speed)
	if other_ship.has_method("apply_ramming_damage"):
		other_ship.call("apply_ramming_damage", self, impact_speed)

func _soften_collision_speed() -> void:
	current_speed = min(current_speed, move_speed * 0.84)


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
	
	# 기존 함대 수 체크 (정예 함선 1척 체제)
	var minions = get_tree().get_nodes_in_group("captured_minion")
	if minions.size() >= 1:
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
	
	# ✅ 나포 완료 시 도선 상태 및 밧줄 강제 해제 (공격자/방어자 모두)
	_cancel_boarding()
	if is_instance_valid(boarding_attacker):
		boarding_attacker._cancel_boarding()
		boarding_attacker = null
	
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
	
	# (is_boarding, boarding_target, _clear_ropes 등은 _cancel_boarding()에서 이미 처리됨)
	
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
	_sync_contact_area_layers(2)

	
	# 자식들(대포, 병사) 팀 변경 및 UI 알림
	_update_children_team_for_capture()
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
	
	# ✅ 나포함 무장 자동 장착 및 현재 함대 업그레이드 적용
	_equip_minion_cannons()
	if is_instance_valid(UpgradeManager):
		UpgradeManager.apply_fleet_upgrades_to_ship(self )
		
	print("[Capture] 나포 성공! 함대에 합류합니다. (target: %s)" % str(target))

func _equip_minion_cannons() -> void:
	if not cannon_scene: return
	
	# 중복 방지: 선체에 미리 달려있는 대포가 있다면 제거 후 FleetCannon으로 통일
	_remove_all_cannons()
	
	# 장착 위치 정의 (전방, 좌측, 우측)
	var spawn_points = [
		{"pos": Vector3(0, 0.8, -3.5), "rot": 0}, # 전방
		{"pos": Vector3(-1.0, 0.8, -0.5), "rot": 90}, # 좌측 (90도 회전)
		{"pos": Vector3(1.0, 0.8, -0.5), "rot": - 90} # 우측 (-90도 회전)
	]
	
	var i = 0
	for p in spawn_points:
		var cannon = cannon_scene.instantiate()
		cannon.name = "FleetCannon_" + str(i)
		add_child(cannon)
		cannon.position = p["pos"]
		cannon.rotation_degrees.y = p["rot"]
		# 팀 설정
		if cannon.has_method("set_team"):
			cannon.set_team("player")
		
		# 초기 레벨에선 전방 대포(index 0) 외에는 비활성
		if i > 0:
			cannon.visible = false
			cannon.set_process(false)
			cannon.set_physics_process(false)
		i += 1

func _update_children_team_for_capture() -> void:
	# 나포 시에 명시적으로 다시 한 번 호출 (BaseShip의 것을 사용)
	_update_children_team()
	
	# 병사 팀 변경
	if has_node("Soldiers"):
		for s in $Soldiers.get_children():
			if s.has_method("set_team"):
				s.set_team("player")
				s.owned_ship = self

func _remove_all_cannons() -> void:
	# 선체 내부에 포함된 대포들까지 모두 찾아서 제거
	_recursive_remove_cannons(self )

func _recursive_remove_cannons(node: Node) -> void:
	for child in node.get_children():
		if child.has_method("fire") or "cannonball_scene" in child: # 대포 노드 판별
			child.queue_free()
		else:
			_recursive_remove_cannons(child)

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
	
	# player_ship.gd의 로직과 유사하게 자동 조절
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
		# 적함은 조금 더 느리고 장중하게 노를 저음 (돌격 시 2배 가속)
		var oar_speed = 3.6 if is_sprinting else 1.8
		_oar_time += delta * oar_speed
		
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
	
	# 3. 다른 미니언들과의 분리력(Separation Force) 계산
	var sep_force = Vector3.ZERO
	for other in minions:
		if other != self and is_instance_valid(other):
			var dist = global_position.distance_to(other.global_position)
			if dist < 12.0 and dist > 0.1: # 12m 이내면 밀어냄
				var push_dir = (global_position - other.global_position).normalized()
				# 가까울수록 강하게 밀어냄 (지수적)
				var strength = (1.0 - (dist / 12.0)) * 5.0
				sep_force += push_dir * strength
				
	# 4. 월드 목표 지점 계산
	var target_pos = target.to_global(offset)
	# 목표 지점에 분리력(회피력) 더하기
	target_pos += sep_force
	
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
		# 0m(1.0배) ~ 60m(1.3배) 사이를 부드럽게 연결 (1.6배에서 하향)
		var lag_factor = clamp(rel_depth / 60.0, 0.0, 1.0)
		var sync_speed_mult = lerp(1.0, 1.3, lag_factor)
		target_final_speed = max(player_speed * sync_speed_mult, move_speed * 0.8)
		
	# 시간차 부드러움 적용 (Temporal Smoothing)
	# 가속도를 낮추어 "급격히 튀어나가는" 느낌 완화 (2.5 -> 1.2)
	_last_ai_speed = lerp(_last_ai_speed, target_final_speed, delta * 1.2)
	var final_move_speed = _last_ai_speed
		
	# B. 러더(Rudder) 조향 시스템 (Broadside Alignment 대체)
	var target_head_rot = atan2(-direction.x, -direction.z) # 목표 슬롯을 향하는 기본 각도
	var player_head_rot = rotation.y # 기본값은 자기 자신
	if target and "rotation" in target:
		player_head_rot = target.rotation.y
		
	# 거리가 가까울수록 목표지점을 보는 대신, 플레이어와 완벽하게 수평을 맞춤(Broadside 유지)
	var rotation_blend = clamp(dist_to_target / 15.0, 0.0, 1.0)
	var blended_target_rot = lerp_angle(player_head_rot, target_head_rot, rotation_blend)
	
	# 러더 계산 (부호 반전 적용)
	var angle_diff = wrapf(blended_target_rot - rotation.y, -PI, PI)
	var desired_rudder = clamp(-rad_to_deg(angle_diff) * 2.0, -45.0, 45.0)
	var rudder_speed_adjusted = 120.0 # 회전 속도
	rudder_angle = move_toward(rudder_angle, desired_rudder, rudder_speed_adjusted * delta)
	
	# 속도가 있어야 회전 가능
	if final_move_speed > 0.1:
		var speed_ratio = final_move_speed / max_speed
		var actual_turn = (rudder_angle / 45.0) * turn_rate * speed_ratio * turn_mult * delta
		rotation.y -= deg_to_rad(actual_turn)
	else:
		# 제자리에서는 부드럽게 정렬만
		if dist_to_target <= 1.5:
			rotation.y = lerp_angle(rotation.y, player_head_rot, delta * 3.0)

	# 선체 전진 벡터 및 이동
	var forward_vec = Vector3(-sin(rotation.y), 0, -cos(rotation.y))
	var velocity = forward_vec * final_move_speed
	
	position += (velocity + separation_force) * delta
	
	# [추가] 러더 및 수면 비주얼 효과 업데이트
	_update_rudder_visual()
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
				_cached_audio_manager.play_sfx("wave_splash", global_position, randf_range(0.8, 1.2), 3.0)
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
	_spawn_one_soldier("player")
	print("[Crew] 나포함 병사 자생적 보충 완료.")


## 충돌 감지 (Area3D signal 연결 필요)
## 함대 업그레이드 (대포 수량 조절 등)
func apply_fleet_weapon_upgrade(level: int) -> void:
	# 대포 노드들 찾기
	var cannons = []
	for child in get_children():
		if child.name.begins_with("FleetCannon_"):
			cannons.append(child)
	
	# 레벨에 따라 활성화 (Lv1: 1문, Lv2: 2문, Lv3+: 3문)
	var active_count = 1
	if level >= 2: active_count = 2
	if level >= 3: active_count = 3
	
	for i in range(cannons.size()):
		var cannon = cannons[i]
		if i < active_count:
			cannon.visible = true
			cannon.set_process(true)
			cannon.set_physics_process(true)
		else:
			cannon.visible = false
			cannon.set_process(false)
			cannon.set_physics_process(false)
	
	print("[Fleet] 함대 무장 업그레이드 적용: Lv.%d (대포 %d문 활성화)" % [level, active_count])


## 함선 수리 (초요기/공적 보너스)
func repair_ship(percent: float) -> void:
	var amt = max_hull_hp * percent
	hull_hp = minf(hull_hp + amt, max_hull_hp)
	print("[Fleet] 함선 수리됨: +%d HP" % amt)


func _on_body_entered(body: Node3D) -> void:
	# 플레이어와 충돌했는지 확인 (StaticBody/CharacterBody 등)
	if body.is_in_group("player") or (body.get_parent() and body.get_parent().is_in_group("player")):
		_board_ship(body)

func _on_area_entered(area: Area3D) -> void:
	# 피격용 히트박스는 도선 트리거에서 제외
	if area.is_in_group("ship_hitbox"):
		return
	
	# 플레이어 선박의 접근 영역과 접촉했는지 확인
	if area.is_in_group("player"):
		_board_ship(area)
	elif area.is_in_group("ship_proximity"):
		var role_parent = area.get_parent()
		if role_parent and role_parent.is_in_group("player"):
			_board_ship(role_parent)


func remove_stuck_object(_obj: Node3D, _s_mult: float, _t_mult: float) -> void:
	tilt_offset *= 0.5
	if tilt_offset < 0.01: tilt_offset = 0.0

func _board_ship(target_ship: Node3D) -> void:
	if is_dying or is_boarding: return
	
	# 생존 병사가 없으면 도선 시도 불가
	if get_alive_crew_count() <= 0:
		return
	
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

	# === 무력화(폐선) 상태인 배는 이미 도선이 불필요함 (나포는 player_ship.gd의 boarding scan으로 처리) ===
	if is_derelict:
		return

	# 1. 초기 충돌 효과 (최초 1회만)
	if not has_rammed:
		has_rammed = true
		print("[Impact] 충돌 발생! 도선 시작.")
		
	# 2. 도선(Boarding) 연결 로직
	if ship_node != boarding_target:
		boarding_target = ship_node

	# 2. 도선 상태 진입 (조건부)
	var my_crew = get_alive_crew_count()
	var enemy_crew = 0
	if ship_node.has_method("get_alive_crew_count"):
		enemy_crew = ship_node.get_alive_crew_count()
		
	if my_crew > enemy_crew:
		is_boarding = true
		boarding_target = ship_node
		
		# 도선 대상에게 내가 공격자임을 알림 (사격 중지 규칙용)
		if boarding_target.has_method("set") or "boarding_attacker" in boarding_target:
			boarding_target.set("boarding_attacker", self )
			
		_clear_ropes()
		boarding_timer = 0.0
		boarding_prep_timer = 0.0
		boarding_contact_timer = 0.0
		boarding_hook_timer = 0.0
		boarding_secondary_rope_timer = 0.0
		_initial_rope_deployed = false
		_full_rope_deployed = false
		
		print("[Boarding] 병력 우위! 접현 후 갈고리 투척을 준비합니다. (아군 %d vs 적군 %d)" % [my_crew, enemy_crew])
	else:
		print("[Skirmish] 병력 우위 부족으로 도선하지 않고 대치합니다. (아군 %d vs 적군 %d)" % [my_crew, enemy_crew])

# 누수 추가/제거
func add_leak(amount: float) -> void:
	leaking_rate += amount
	print("[Status] 누수 발생! 초당 데미지: %.1f" % leaking_rate)

func remove_leak(amount: float) -> void:
	leaking_rate = maxf(0.0, leaking_rate - amount)
	print("[Status] 누수 완화. 남은 누수율: %.1f" % leaking_rate)
