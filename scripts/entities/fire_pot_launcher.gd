extends Node3D

## 화통 발사기 (Fire Pot Launcher)
## 일정 반경 내의 적선 갑판(병사들이 모여있는 곳)으로 화통을 투척합니다.

@export var fire_pot_scene: PackedScene = preload("res://scenes/projectiles/fire_pot.tscn")
@export var base_cooldown: float = 6.0
@export var detection_range: float = 12.0
@export var team: String = "player"

var cooldown_timer: float = 0.0

func _process(delta: float) -> void:
	var um = get_node_or_null("/root/UpgradeManager")
	var current_cooldown = base_cooldown
	
	if is_instance_valid(um) and "current_levels" in um:
		var level = um.current_levels.get("fire_pot", 0)
		if level > 0:
			# 업그레이드 수치 반영 (Lv1: 6s, Lv2: 5s, Lv3: 4s, Lv4: 3.5s, Lv5: 3s)
			var s = um.UPGRADES["fire_pot"]["stats"]
			current_cooldown = s.get("base_cooldown", 6.0) - (level - 1) * s.get("cooldown_reduce_per_lv", 1.0)
			# 4렙부터 감소폭 조정 (임시 예외 처리, 기획안 기준)
			if level == 4: current_cooldown = 3.5
			if level >= 5: current_cooldown = 3.0
	
	if cooldown_timer > 0:
		cooldown_timer -= delta
		return
	
	# 사거리 내의 적 병사 찾기
	var target_soldier = _find_best_target_soldier()
	if target_soldier:
		fire(target_soldier.global_position, current_cooldown)

func _find_best_target_soldier() -> Node3D:
	var enemy_group = "enemy" if team == "player" else "player"
	var all_soldiers = get_tree().get_nodes_in_group("soldier")
	var best_target: Node3D = null
	var min_dist: float = detection_range
	
	for soldier in all_soldiers:
		if not is_instance_valid(soldier): continue
		if soldier.get("team") != enemy_group: continue
		if soldier.get("current_state") == 3: continue # 3 = DEAD (상수 참조 대신 매직넘버 사용, 가벼운 체크)
		
		# 도중에 공중에 뜬 상태(점프 중)이거나 바다에 빠진 상태는 제외
		if soldier.global_position.y < 0.2 or soldier.global_position.y > 2.0:
			continue
			
		# 내 배에 타고 있는 적 병사에게 던지면 안 됨 (화통은 상대 배 갑판으로)
		var parent_ship = _get_ship_of_node(soldier)
		var my_ship = _get_ship_of_node(self )
		if parent_ship == my_ship:
			continue
			
		var dist = global_position.distance_to(soldier.global_position)
		if dist < min_dist:
			min_dist = dist
			best_target = soldier
			
	return best_target

func _get_ship_of_node(node: Node) -> Node:
	var curr = node
	while curr != null:
		if curr.is_in_group("ship") or curr.is_in_group("player"):
			return curr
		curr = curr.get_parent()
	return null

func fire(target_pos: Vector3, cooldown_override: float = -1.0) -> void:
	if not fire_pot_scene: return
	
	cooldown_timer = cooldown_override if cooldown_override > 0 else base_cooldown
	
	var pot = fire_pot_scene.instantiate()
	get_tree().root.add_child.call_deferred(pot)
	
	# 발사 위치 살짝 위쪽 설정
	var spawn_pos = global_position + Vector3(0, 1.0, 0)
	pot.position = spawn_pos
	
	# 업그레이드 매니저에서 데미지와 반경 가져오기
	var um = get_node_or_null("/root/UpgradeManager")
	var level = 1
	if is_instance_valid(um) and "current_levels" in um:
		level = um.current_levels.get("fire_pot", 1)
		var s = um.UPGRADES["fire_pot"]["stats"]
		var dmg = s.get("base_damage", 15.0) + (level - 1) * s.get("damage_per_lv", 5.0)
		var rad = s.get("base_radius", 3.0) + (level - 1) * s.get("radius_per_lv", 0.5)
		
		# Deferred 호출로 씬 트리에 들어간 후 값 설정
		get_tree().create_timer(0.01).timeout.connect(func():
			if is_instance_valid(pot):
				pot.damage = dmg
				pot.explosion_radius = rad
				pot.team = team
				
				# 비행 궤적 설정 (거리에 비례해 비행 시간 결정)
				var dist = spawn_pos.distance_to(target_pos)
				var flight_time = clamp(dist / 10.0, 0.5, 1.5)
				var arc = clamp(dist * 0.3, 2.0, 5.0)
				pot.setup_flight(spawn_pos, target_pos, flight_time, arc)
		)
	
	# 발사 효과 (사운드)
	var audio_manager = get_node_or_null("/root/AudioManager")
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx("cloth_flap", global_position, randf_range(1.2, 1.5)) # 던지는 소리 임시
