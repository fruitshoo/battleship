extends "res://scripts/entities/weapons/weapon.gd"

@export var arrow_scene: PackedScene = preload("res://scenes/projectiles/arrow.tscn")
@export var shoot_cooldown: float = 2.0
@export var max_range: float = 20.0

func _ready() -> void:
	damage = 8.0
	attack_range = max_range
	attack_cooldown = shoot_cooldown

func attack(target: Node3D, attacker: Node3D) -> void:
	if not is_instance_valid(target) or not arrow_scene: return
	
	var arrow = arrow_scene.instantiate() as Node3D
	# 발사 위치는 활(또는 병사 가슴 위치) 부근으로 약간 보정
	var spawn_pos = attacker.global_position
	spawn_pos.y += 0.8
	
	var current_target_pos = target.global_position
	current_target_pos.y += 0.5
	current_target_pos.x += randf_range(-0.5, 0.5)
	current_target_pos.z += randf_range(-0.5, 0.5)
	
	# 데이터 설정 (SceneTree에 추가하기 전에 설정하여 _ready에서 사용 가능하게 함)
	if "start_pos" in arrow: arrow.start_pos = spawn_pos
	if "target_pos" in arrow: arrow.target_pos = current_target_pos
	if "damage" in arrow: arrow.damage = damage
	
	# 병사 팀 정보 전달
	if "team" in arrow:
		if "team" in attacker:
			arrow.team = attacker.get("team")
			
	# 거리에 따른 곡선 조절
	if "arc_height" in arrow:
		var dist = spawn_pos.distance_to(current_target_pos)
		arrow.arc_height = clamp(dist * 0.3, 1.0, 5.0)
		
	# 시너지 (화염살)
	var active_um = attacker.get_tree().root.get_node_or_null("UpgradeManager")
	if not active_um:
		active_um = attacker.get_tree().root.find_child("UpgradeManager", true, false)
		
	if "team" in arrow and arrow.team == "player" and is_instance_valid(active_um):
		var plv = active_um.current_levels.get("fire_arrows", 0) if "current_levels" in active_um else 0
		if plv > 0 and "is_fire_arrow" in arrow:
			arrow.is_fire_arrow = true
			if "fire_damage" in arrow: arrow.fire_damage = plv * 1.5
	
	# 레벨 매니저 또는 부모 트리에 추가 (이 시점에 _ready 실행됨)
	var lm = attacker.get_tree().root.find_child("LevelManager", true, false)
	if lm:
		lm.add_child(arrow)
	else:
		attacker.get_tree().root.add_child(arrow)
		
	# 위치 및 방향 최종 보정
	arrow.global_position = spawn_pos
	arrow.look_at(current_target_pos, Vector3.UP)
	
	# 활 쏘는 소리
	if is_instance_valid(AudioManager):
		AudioManager.play_sfx("arrow_shoot", attacker.global_position, randf_range(0.9, 1.1))
