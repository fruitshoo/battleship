extends Node3D

## 보스 함선 (Boss Ship)
## 거대한 체력, 다수의 포대, 선회 포격 AI

signal boss_died

@export var max_p: float = 1000.0
@export var move_speed: float = 3.0
@export var orbit_distance: float = 35.0 # 플레이어 주변을 도는 거리
@export var cannon_scene: PackedScene = preload("res://scenes/entities/cannon.tscn")
@export var singigeon_scene: PackedScene = preload("res://scenes/entities/singigeon_launcher.tscn")

var hp: float = 1000.0
var target: Node3D = null
var is_dead: bool = false
var orbit_angle: float = 0.0

# 누수(Leaking) 시스템 변수
var leaking_rate: float = 0.0 # 초당 피해량
var current_sink_offset: float = 0.0 # 가라앉은 깊이
var current_tilt_angle: float = 0.0 # 기울어진 각도

func _ready() -> void:
	hp = max_p
	add_to_group("enemy")
	add_to_group("boss")
	_find_player()
	_setup_weapons()

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
		# 우측 대포
		var cr = cannon_scene.instantiate()
		cannons_node.add_child(cr)
		cr.position = Vector3(2.5, 0.8, z_pos)
		cr.rotation.y = deg_to_rad(-90)
		cr.team = "enemy"
		
	# 전방 신기전 배치
	var singigeon = singigeon_scene.instantiate()
	add_child(singigeon)
	singigeon.position = Vector3(0, 1.0, -5.0)
	singigeon.team = "enemy"
	if singigeon.has_method("upgrade_to_level"):
		singigeon.upgrade_to_level(3) # 최고 레벨 신기전

func _process(delta: float) -> void:
	if is_dead: return
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
		
	# 이동 및 회전
	var target_look = global_position + move_dir
	if not global_position.is_equal_approx(target_look):
		var look_target = lerp(global_position + -basis.z, target_look, delta * 2.0)
		look_at(look_target, Vector3.UP)
		
	global_position += -basis.z * move_speed * delta
	
	# === 누수(Leaking) 시각 효과 및 데미지 ===
	if leaking_rate > 0:
		take_damage(leaking_rate * delta)
		
		# HP 비율에 따라 서서히 가라앉음
		var hp_ratio = 1.0 - (hp / max_p)
		# 보스는 더 크므로 최대 0.5m만 가라앉고, 5도만 기울어짐 (무거우니까)
		var target_sink = hp_ratio * 0.5
		var target_tilt = hp_ratio * 5.0
		
		current_sink_offset = lerp(current_sink_offset, target_sink, delta)
		current_tilt_angle = lerp(current_tilt_angle, target_tilt, delta)
		
		# 시각적 반영 (자식 노드들 오프셋)
		# 대포나 신기전 발사기 노드는 오프셋에서 제외하여 기능 유지 (탐지 및 발사)
		for child in get_children():
			if child.name in ["Cannons", "SingijeonLauncher"]: continue
			if child is MeshInstance3D or (child is Node3D and not child is GPUParticles3D):
				child.position.y = - current_sink_offset
				child.rotation_degrees.z = current_tilt_angle

func _find_player() -> void:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		target = players[0]

func take_damage(amount: float, hit_position: Vector3 = Vector3.ZERO) -> void:
	if is_dead: return
	hp -= amount
	
	# HUD에 보스 체력 업데이트 (LevelManager를 통해)
	var lm = get_tree().root.find_child("LevelManager", true, false)
	if lm and lm.has_method("update_boss_hp"):
		lm.update_boss_hp(hp, max_p)
		
	if hp <= 0:
		_die()

func _die() -> void:
	is_dead = true
	boss_died.emit()
	print("🏆 보스 격침!")
	
	# 침몰 효과 (회전하며 가라앉음)
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", -5.0, 4.0)
	tween.tween_property(self, "rotation:z", deg_to_rad(25.0), 3.0)
	
	tween.chain().tween_callback(func():
		var lm = get_tree().root.find_child("LevelManager", true, false)
		if lm: lm.show_victory()
	)
	
	# 삭제 지연
	leaking_rate = 0.0 # 사망 시 누수 중단
	get_tree().create_timer(5.0).timeout.connect(queue_free)


# 누수 추가/제거
func add_leak(amount: float) -> void:
	leaking_rate += amount
	print("💧 보스 함선에 누수 발생! 초당 데미지: %.1f" % leaking_rate)

func remove_leak(amount: float) -> void:
	leaking_rate = maxf(0.0, leaking_rate - amount)
	print("🩹 보스 누수 완화. 남은 누수율: %.1f" % leaking_rate)
