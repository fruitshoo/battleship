extends "res://scripts/entities/base_ship.gd"

## 보스 함선 (Boss Ship)
## 거대한 체력, 다수의 포대, 선회 포격 AI

signal boss_died

@export var move_speed: float = 3.0
@export var orbit_distance: float = 35.0 # 플레이어 주변을 도는 거리
@export var cannon_scene: PackedScene = preload("res://scenes/entities/cannon.tscn")
@export var singigeon_scene: PackedScene = preload("res://scenes/entities/singigeon_launcher.tscn")
@export var soldier_scene: PackedScene = preload("res://scenes/soldier.tscn")

var target: Node3D = null
var orbit_angle: float = 0.0

# 누수(Leaking) 시스템 변수
var leaking_rate: float = 0.0 # 초당 피해량

var cached_lm: Node = null

func _ready() -> void:
	if max_hull_hp <= 0: max_hull_hp = 1000.0
	hull_hp = max_hull_hp
	base_y = global_position.y
	add_to_group("enemy")
	add_to_group("boss")
	add_to_group("ships")
	_find_player()
	
	cached_lm = get_tree().root.find_child("LevelManager", true, false)
	if not cached_lm:
		var lm_nodes = get_tree().get_nodes_in_group("level_manager")
		if lm_nodes.size() > 0: cached_lm = lm_nodes[0]
		
	_setup_weapons()
	_setup_soldiers()

func _setup_weapons() -> void:
	# 다수의 대포 배치 (좌우 각 3개)
	var cannons_node = Node3D.new()
	cannons_node.name = "Cannons"
	add_child(cannons_node)
	
	for i in range(3):
		var z_pos = -2.0 + (i * 2.0)
		# 좌측 대포
		var cl = cannon_scene.instantiate()
		cannons_node.add_child(cl)
		cl.position = Vector3(-2.5, 0.8, z_pos)
		cl.rotation.y = deg_to_rad(90)
		cl.team = "enemy"
		cl.detection_range = 45.0
		cl.detection_arc = 40.0
		# 우측 대포
		var cr = cannon_scene.instantiate()
		cannons_node.add_child(cr)
		cr.position = Vector3(2.5, 0.8, z_pos)
		cr.rotation.y = deg_to_rad(-90)
		cr.team = "enemy"
		cr.detection_range = 45.0
		cr.detection_arc = 40.0
		
	# 전방 신기전 배치
	var singigeon = singigeon_scene.instantiate()
	add_child(singigeon)
	singigeon.position = Vector3(0, 1.0, -5.0)
	singigeon.team = "enemy"
	singigeon.detection_range = 45.0
	if singigeon.has_method("upgrade_to_level"):
		singigeon.upgrade_to_level(3) # 최고 레벨 신기전

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
	
	for pos in spawn_points:
		var s = soldier_scene.instantiate()
		s.position = pos
		s.team = "enemy"
		# 보스 병사는 엘리트급 체력/데미지 보너스
		s.max_health = 150.0
		s.attack_damage = 15.0
		soldiers_node.add_child(s)

func _process(delta: float) -> void:
	if is_dying: return
	
	_update_fire_effect()
	_update_sail_visual()
	_update_burning_status(delta)
	_update_hull_regeneration(delta)
	
	if not is_instance_valid(target):
		_find_player()
		return
		
	# === 선회(Orbiting) AI ===
	# 플레이어를 중심으로 원을 그리며 이동
	var to_player = (target.global_position - global_position).normalized()
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
		move_dir = side_dir
		
	# 3. 이동 및 회전 (Separation 포함)
	# Separation (충돌 방지)
	var sep = _calculate_separation()
	if sep.length_squared() > 0.001:
		# 보스는 질량이 크므로 다른 배들에 비해 밀려나는 정도를 적게 함
		move_dir = (move_dir.normalized() + sep * 0.5).normalized()
	
	# 이동 및 회전
	var target_look = global_position + move_dir
	if not global_position.is_equal_approx(target_look):
		var look_target = lerp(global_position + -basis.z, target_look, delta * 2.0)
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
		
	global_position += move_dir * move_speed * leak_speed_mult * wind_mult * delta
	
	# === 누수(Leaking) 데미지 ===
	if leaking_rate > 0:
		take_damage(leaking_rate * delta)
		
	# === 둥실둥실 및 기울기 효과 ===
	_apply_bobbing_effect()

func _calculate_separation() -> Vector3:
	var force = Vector3.ZERO
	var neighbors = get_tree().get_nodes_in_group("ships")
	var separation_dist = 8.0 # 보스는 덩치가 크므로 회피 반경을 넓게 설정
	
	for other in neighbors:
		if other == self or not is_instance_valid(other) or other.get("is_dead") or other.get("is_sinking"):
			continue
			
		var dist = global_position.distance_to(other.global_position)
		if dist < separation_dist and dist > 0.1:
			var push_dir = (global_position - other.global_position).normalized()
			# 거리에 따른 반성능(Repulsion) 계산
			force += push_dir * (separation_dist - dist) / separation_dist
			
	return force

func _find_player() -> void:
	var players = get_tree().get_nodes_in_group("player")
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

	# HUD에 보스 체력 업데이트 (LevelManager를 통해)
	if is_instance_valid(cached_lm) and cached_lm.has_method("update_boss_hp"):
		cached_lm.update_boss_hp(hull_hp, max_hull_hp)

func die() -> void:
	if is_dying: return
	is_dying = true
	
	# ✅ 배 위의 아군(player) 병사를 Survivor로 전환 (침몰 전 처리)
	_evacuate_player_soldiers_as_survivors()
	
	# 침몰 시작 시 타겟 그룹에서 제외
	if is_in_group("enemy"):
		remove_from_group("enemy")
	
	boss_died.emit()
	print("[Boss] 보스 격침!")
	
	# 침몰 효과 (회전하며 가라앉음)
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self , "position:y", -5.0, 4.0)
	tween.tween_property(self , "rotation:z", deg_to_rad(25.0), 3.0)
	
	tween.chain().tween_callback(func():
		if is_instance_valid(cached_lm) and cached_lm.has_method("show_victory"):
			cached_lm.show_victory()
	)
	
	# 생존자 대량 스폰 (보스 격침 보너스: 3~5명)
	if survivor_scene:
		var count = randi_range(3, 5)
		for i in range(count):
			var survivor = survivor_scene.instantiate()
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
			
			var survivor = survivor_scene.instantiate()
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
	print("[Status] 보스 누수 완화. 남은 누수율: %.1f" % leaking_rate)

# === 장군전 등 특수 피격 로직 ===
func add_stuck_object(obj: Node3D, _s_mult: float, _t_mult: float) -> void:
	# 보스는 속도 저하보다는 시각적 기울기만 적용
	var tilt_dir = 1.0 if obj.global_position.x > global_position.x else -1.0
	var new_tilt = deg_to_rad(randf_range(3.0, 6.0)) * tilt_dir # 보스는 덜 기웃거림
	tilt_offset = clamp(tilt_offset + new_tilt, -deg_to_rad(10.0), deg_to_rad(10.0))

func remove_stuck_object(_obj: Node3D, _s_mult: float, _t_mult: float) -> void:
	tilt_offset *= 0.5
	if tilt_offset < 0.01: tilt_offset = 0.0
