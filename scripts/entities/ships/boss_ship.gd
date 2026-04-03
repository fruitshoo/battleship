@tool
extends "res://scripts/entities/ships/base_ship.gd"

## 보스 함선 (Boss Ship)
## 거대한 체력, 다수의 포대, 선회 포격 AI

signal boss_died

@export var move_speed: float = 3.0
@export var orbit_distance: float = 35.0 # 플레이어 주변을 도는 거리
@export_range(0.0, 1.0, 0.01) var orbit_inward_bias: float = 0.34 # 선회 중에도 플레이어 쪽으로 얼마나 파고들지
@export var cannon_scene: PackedScene = preload("res://scenes/entities/launchers/cannon_enemy_heavy.tscn")
@export var singigeon_scene: PackedScene = preload("res://scenes/entities/launchers/singigeon_launcher.tscn")
@export var soldier_scene: PackedScene = preload("res://scenes/entities/soldiers/soldier.tscn")
@export var hull_scene: PackedScene = preload("res://scenes/ships/hulls/atakebune_hull.tscn")

var target: Node3D = null
var orbit_angle: float = 0.0
var leaking_rate: float = 0.0
var _leak_tick_timer: float = 0.0
var cached_lm: Node = null
var _merit_granted: bool = false
var crew_composition: Array[String] = []

@export var ship_type: String = "atakebune_mid":
	set(value):
		ship_type = value
		if Engine.is_editor_hint():
			_update_editor_hull()
@export var tier: int = 1 ## 1: 중간 보스 (Front/L/R 1개씩), 2: 최종 보스 (고화력)

func _update_editor_hull() -> void:
	for child in get_children():
		if child.name.contains("Hull"):
			child.queue_free()
			
	var stats = load_ship_stats(ship_type)
	if stats.is_empty(): return
	
	var type_lower = ship_type.to_lower()
	var h_path = "res://scenes/ships/hulls/atakebune_hull.tscn"
	if type_lower.contains("sekibune"): h_path = "res://scenes/ships/hulls/sekibune_hull.tscn"
	elif type_lower.contains("panokseon"): h_path = "res://scenes/ships/hulls/panokseon_hull.tscn"
	elif type_lower.contains("maengseon"): h_path = "res://scenes/ships/hulls/maengseon_hull.tscn"
	
	var new_hull = load(h_path)
	if new_hull:
		var inst = new_hull.instantiate()
		inst.name = "EditorHull"
		add_child(inst)
		_cache_hull_references(self )

func _ready() -> void:
	if Engine.is_editor_hint():
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
		if stats.has("tier"): tier = stats["tier"]
		if stats.has("orbit_distance"): orbit_distance = stats["orbit_distance"]
		_load_crew_composition_from_stats(stats)
		if tier == 1:
			orbit_inward_bias = 0.42
		else:
			orbit_inward_bias = 0.32

	# 선체(Hull) 씬 인스턴스화 및 추가
	if is_instance_valid(hull_scene):
		var hull_inst = hull_scene.instantiate()
		add_child(hull_inst)
	else:
		_update_editor_hull()
		
	super._ready()
	hull_hp = max_hull_hp
	add_to_group("enemy")
	add_to_group("boss")
	add_to_group("ships")
	_find_player()
	
	cached_lm = get_tree().root.find_child("LevelManager", true, false)
	if not cached_lm:
		var lm_nodes = SceneGroupCache.get_nodes(get_tree(), "level_manager")
		if lm_nodes.size() > 0: cached_lm = lm_nodes[0]
		
	_setup_weapons()
	_setup_soldiers()
	_update_boss_hp_hud()
	call_deferred("_update_boss_hp_hud")

func _setup_weapons() -> void:
	# 다수의 대포 배치
	var cannons_node = Node3D.new()
	cannons_node.name = "Cannons"
	add_child(cannons_node)
	
	if tier == 1:
		# 중간 보스: 전방 1, 좌방 1, 우방 1 (총 3문)
		_spawn_boss_cannon(cannons_node, Vector3(0, 0.8, -5.0), 0)
		_spawn_boss_cannon(cannons_node, Vector3(-2.8, 0.8, 0), 90)
		_spawn_boss_cannon(cannons_node, Vector3(2.8, 0.8, 0), -90)
	else:
		# 최종 보스: 기존의 고화력 세팅 (좌우 각 3문 + 전방 신기전)
		for i in range(3):
			var z_pos = -2.0 + (i * 2.0)
			_spawn_boss_cannon(cannons_node, Vector3(-2.8, 0.8, z_pos), 90)
			_spawn_boss_cannon(cannons_node, Vector3(2.8, 0.8, z_pos), -90)
			
		# 전방 신기전 배치
		var singigeon = singigeon_scene.instantiate()
		add_child(singigeon)
		singigeon.position = Vector3(0, 1.0, -5.0)
		singigeon.team = "enemy"
		singigeon.detection_range = 36.0
		if singigeon.has_method("upgrade_to_level"):
			singigeon.upgrade_to_level(3) # 최고 레벨 신기전

func _spawn_boss_cannon(container: Node, pos: Vector3, rot_y: float) -> void:
	var c = cannon_scene.instantiate()
	container.add_child(c)
	c.position = pos
	c.rotation_degrees.y = rot_y
	c.team = "enemy"
	c.detection_range = 23.0
	c.detection_arc = 50.0

func _setup_soldiers() -> void:
	if not soldier_scene: return
	
	var soldiers_node = get_node_or_null("Soldiers")
	if not soldiers_node:
		soldiers_node = Node3D.new()
		soldiers_node.name = "Soldiers"
		add_child(soldiers_node)
		soldiers_node.position = Vector3(0, 1.0, 0)
	
	# 보스 함선 갑판에 4명의 병사 배치
	var spawn_points = [
		Vector3(-1.5, 0, -3),
		Vector3(1.5, 0, -3),
		Vector3(-1.5, 0, 3),
		Vector3(1.5, 0, 3)
	]
	
	var i = 0
	for pos in spawn_points:
		var s = soldier_scene.instantiate()
		var soldier_type_name: String = _get_crew_type_for_index(i)
		s.team = "enemy"
		s.owned_ship = self
		s.home_ship = self
		_configure_boss_soldier(s, soldier_type_name)
		s.position = pos
		
		# 보스 병사는 엘리트급 체력/데미지 보너스
		s.max_health = 150.0
		s.current_health = s.max_health
		s.attack_damage = 15.0
			
		soldiers_node.add_child(s)
		s.set_team("enemy")
		_configure_boss_soldier(s, soldier_type_name)
		i += 1


func _load_crew_composition_from_stats(stats: Dictionary) -> void:
	crew_composition.clear()
	var composition_variant: Variant = stats.get("crew_composition", {})
	if typeof(composition_variant) != TYPE_DICTIONARY:
		return
	var composition: Dictionary = composition_variant as Dictionary
	var ordered_types: Array[String] = ["general", "melee", "ranged"]
	for soldier_type_name in ordered_types:
		var count: int = int(composition.get(soldier_type_name, 0))
		for _i in range(maxi(count, 0)):
			crew_composition.append(soldier_type_name)


func _get_crew_type_for_index(index: int) -> String:
	if crew_composition.is_empty():
		return "ranged" if index % 2 == 0 else "general"
	return crew_composition[index % crew_composition.size()]


func _configure_boss_soldier(soldier, soldier_type_name: String) -> void:
	var normalized_type: String = soldier_type_name.strip_edges().to_lower()
	soldier.crew_role = "general"
	soldier.is_melee_only = false
	soldier.is_ranged_only = false
	match normalized_type:
		"melee":
			soldier.is_melee_only = true
		"ranged":
			soldier.is_ranged_only = true
	if soldier.is_node_ready():
		soldier._apply_role_loadout()
		soldier._update_role_visual()

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint(): return
	if is_dying: return
	
	_update_fire_effect()
	_update_sail_visual()
	_update_burning_status(delta)
	_update_hull_regeneration(delta)
	_update_boarding_state(delta)
	
	if not is_instance_valid(target) or target.get("is_sinking") == true or target.get("is_dying") == true or target.get("is_dead") == true:
		target = null
		_find_player()
		_set_wake_state(false)
		return
		
	# === 선회(Orbiting) AI ===
	# 플레이어를 중심으로 원을 그리며 이동
	var to_player = target.global_position - global_position
	to_player.y = 0.0
	if to_player.length_squared() <= 0.001:
		_set_wake_state(false)
		return
	to_player = to_player.normalized()
	var dist = global_position.distance_to(target.global_position)
	
	# 거리가 너무 멀면 접근, 적절하면 선회, 너무 가까우면 뒤로
	var move_dir = Vector3.ZERO
	if dist > orbit_distance + 5.0:
		move_dir = to_player
	elif dist < orbit_distance - 5.0:
		move_dir = - to_player
	else:
		# 플레이어 주변을 시계 방향으로 선회
		var side_dir = Vector3(-to_player.z, 0, to_player.x)
		move_dir = (side_dir + to_player * orbit_inward_bias).normalized()
		
	# === 이동 및 회전 (Separation 및 Hard Collision 포함) ===
	# 1. Separation (부드러운 충돌 방지)
	var sep = _calculate_separation()
	
	# 2. Collision Repulsion (강체 충돌 및 충각 데미지)
	var hard_rep = _calculate_collision_repulsion()
	
	if (sep + hard_rep).length_squared() > 0.001:
		# 보스는 질량이 크므로 다른 배들에 비해 밀려나는 정도를 적게 함 (0.5배 -> 0.3배)
		move_dir = (move_dir.normalized() + (sep + hard_rep) * 0.3).normalized()
	
	# 이동 및 회전
	var target_look = global_position + move_dir
	if not global_position.is_equal_approx(target_look):
		target_look.y = global_position.y
		var look_target = lerp(global_position + -basis.z, target_look, delta * 2.0)
		look_target.y = global_position.y
		look_at(look_target, Vector3.UP)
		
	# 이동 (누수율에 비례하여 속도 감소)
	var leak_speed_mult = clamp(1.0 - (leaking_rate * 0.03), 0.4, 1.0)
	
	# === 바람 영향(Wind Force) 적용 ===
	var wind_mult = 1.0
	var wind_manager = get_node_or_null("/root/WindManager")
	if is_instance_valid(wind_manager) and wind_manager.has_method("get_wind_direction"):
		var wind_dir: Vector2 = wind_manager.get_wind_direction()
		var wind_str: float = wind_manager.get_wind_strength()
		
		var ship_forward = Vector2(move_dir.x, move_dir.z).normalized()
		var dot_prod = wind_dir.dot(ship_forward)
		
		# 보스는 덩치가 커서 바람의 영향을 조금 덜 받도록 완화 (0.6 ~ 1.3)
		var base_wind_influence = remap(dot_prod, -1.0, 1.0, 0.6, 1.3)
		wind_mult = lerp(1.0, base_wind_influence, wind_str)
		
	# velocity 계산 및 적용
	var final_velocity = move_dir * move_speed * leak_speed_mult * wind_mult
	global_position += (final_velocity + hard_rep) * delta
	
	_update_leaking_damage(delta)
		
	# === 둥실둥실 및 기울기 효과 ===
	_apply_bobbing_effect()

func _calculate_separation() -> Vector3:
	if bool(get_meta("derelict_nonblocking", false)):
		return Vector3.ZERO

	var force = Vector3.ZERO
	var neighbors = SceneGroupCache.get_nodes(get_tree(), "ships")
	
	for other in neighbors:
		if other == self or not is_instance_valid(other) or other.get("is_dead") or other.get("is_sinking"):
			continue
		if bool(other.get_meta("derelict_nonblocking", false)):
			continue
			
		var offset = global_position - other.global_position
		offset.y = 0.0
		var dist_sq = offset.length_squared()
		if dist_sq <= 0.01:
			continue
		
		var dist = sqrt(dist_sq)
		var coll_dist = get_collision_distance_to(other)
		var separation_trigger_dist = coll_dist + 0.2
		
		if dist < separation_trigger_dist:
			var push_dir = offset.normalized()
			var ratio = (separation_trigger_dist - dist) / max(separation_trigger_dist, 0.001)
			force += push_dir * pow(ratio, 2.0) * 1.5
			
	return force

func _find_player() -> void:
	var players = SceneGroupCache.get_nodes(get_tree(), "player")
	var closest_dist = INF
	var closest_player = null
	
	for p in players:
		if p == self: continue # 자기 자신 제외
		if not p.get("is_sinking") and not p.get("is_dead"):
			var dist = global_position.distance_squared_to(p.global_position)
			var weight = 1.0
			if p.get("is_player_controlled") == true:
				weight = 0.8 # 본선 어그로 약간 높음
				
			var weighted_dist = dist * weight
			
			if weighted_dist < closest_dist:
				closest_dist = weighted_dist
				closest_player = p
				
	target = closest_player

	# 타겟 갱신과 무관하게 HUD 체력바는 즉시 동기화한다.
	_update_boss_hp_hud()

func _update_boss_hp_hud() -> void:
	if not is_instance_valid(cached_lm):
		cached_lm = get_tree().root.find_child("LevelManager", true, false)
		if not cached_lm:
			var lm_nodes = SceneGroupCache.get_nodes(get_tree(), "level_manager")
			if lm_nodes.size() > 0:
				cached_lm = lm_nodes[0]
	if is_instance_valid(cached_lm) and cached_lm.has_method("update_boss_hp"):
		cached_lm.update_boss_hp(maxf(hull_hp, 0.0), max_hull_hp)

func take_damage(amount: float, hit_position: Vector3 = Vector3.ZERO, damage_source: String = "") -> void:
	super.take_damage(amount, hit_position, damage_source)
	_update_boss_hp_hud()

func die() -> void:
	if is_dying: return
	is_dying = true
	if is_instance_valid(cached_lm) and cached_lm.has_method("update_boss_hp"):
		cached_lm.update_boss_hp(0.0, max_hull_hp)
	
	# ✅ 배 위의 아군(player) 병사를 Survivor로 전환 (침몰 전 처리)
	_evacuate_player_soldiers_as_survivors()
	
	# 침몰 시작 시 타겟 그룹에서 제외
	if is_in_group("enemy"):
		remove_from_group("enemy")
	
	boss_died.emit()
	print("[Boss] 보스 격침!")
	if is_instance_valid(cached_lm):
		if cached_lm.has_method("add_ship_sunk"):
			cached_lm.add_ship_sunk(1)
		# 규칙 통일: 함선 격침은 XP/점수 지급
		if cached_lm.has_method("add_score"):
			cached_lm.add_score(400)
		if cached_lm.has_method("add_xp"):
			cached_lm.add_xp(100)
	
	# 공적 포인트(Merit) 추가 (보스는 대량의 공적 부여)
	if not _merit_granted and is_instance_valid(cached_lm) and cached_lm.has_method("add_merit"):
		cached_lm.add_merit(50)
		_merit_granted = true
	
	# 침몰 효과 (회전하며 가라앉음)
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self , "position:y", -5.0, 4.0)
	tween.tween_property(self , "rotation:z", deg_to_rad(25.0), 3.0)
	
	tween.chain().tween_callback(func():
		# 중간 보스(tier 1) 격침은 승리 조건이 아니다.
		if tier >= 2 and is_instance_valid(cached_lm) and cached_lm.has_method("show_victory"):
			cached_lm.show_victory()
	)
	
	# 아이템은 최종 보스(tier 2 이상)만 드롭한다.
	if tier >= 2 and is_instance_valid(UpgradeManager) and UpgradeManager.has_method("grant_final_boss_item"):
		UpgradeManager.grant_final_boss_item()
	
	# 생존자 대량 스폰 (보스 격침 보너스: 3~5명)
	if survivor_scene:
		var count = randi_range(3, 5)
		for i in range(count):
			var survivor = ScenePool.acquire(get_tree(), survivor_scene)
			get_tree().root.add_child.call_deferred(survivor)
			var offset = Vector3(randf_range(-4.0, 4.0), 0.5, randf_range(-4.0, 4.0))
			survivor.set_deferred("global_position", global_position + offset)
	
	# 삭제 지연
	leaking_rate = 0.0 # 사망 시 누수 중단
	get_tree().create_timer(5.0).timeout.connect(queue_free)

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
			
			var survivor = ScenePool.acquire(get_tree(), survivor_scene)
			get_tree().root.add_child.call_deferred(survivor)
			survivor.set_deferred("global_position", spawn_pos)
			
			# 병사 즉시 제거
			child.queue_free()
			converted_count += 1
	
	if converted_count > 0:
		print("[Critical] 보함 침몰! 아군 병사 %d명이 바다로 뛰어들었습니다!" % converted_count)


# 누수 추가/제거
func add_leak(amount: float) -> void:
	leaking_rate += amount
	print("[Status] 보스 함선에 누수 발생! 초당 데미지: %.1f" % leaking_rate)

func remove_leak(amount: float) -> void:
	leaking_rate = maxf(0.0, leaking_rate - amount)
	if leaking_rate <= 0.0:
		_leak_tick_timer = 0.0
	print("[Status] 보스 누수 완화. 남은 누수율: %.1f" % leaking_rate)

func _update_leaking_damage(delta: float) -> void:
	if leaking_rate <= 0.0:
		_leak_tick_timer = 0.0
		return
	_leak_tick_timer += delta
	while _leak_tick_timer >= 1.0:
		_leak_tick_timer -= 1.0
		take_damage(leaking_rate, global_position, "leak")

# === 장군전 등 특수 피격 로직 ===
func add_stuck_object(obj: Node3D, _s_mult: float, _t_mult: float) -> void:
	# 보스는 속도 저하보다는 시각적 기울기만 적용
	var tilt_dir = 1.0 if obj.global_position.x > global_position.x else -1.0
	var new_tilt = deg_to_rad(randf_range(3.0, 6.0)) * tilt_dir # 보스는 덜 기웃거림
	tilt_offset = clamp(tilt_offset + new_tilt, -deg_to_rad(10.0), deg_to_rad(10.0))

func remove_stuck_object(_obj: Node3D, _s_mult: float, _t_mult: float) -> void:
	tilt_offset *= 0.5
	if tilt_offset < 0.01: tilt_offset = 0.0
