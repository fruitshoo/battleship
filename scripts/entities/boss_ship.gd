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
		# 우측 대포
		var cr = cannon_scene.instantiate()
		cannons_node.add_child(cr)
		cr.position = Vector3(2.5, 0.8, z_pos)
		cr.rotation.y = deg_to_rad(-90)
		
	# 전방 신기전 배치
	var singigeon = singigeon_scene.instantiate()
	add_child(singigeon)
	singigeon.position = Vector3(0, 1.0, -5.0)
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
	tween.chain().get_tree().root.find_child("LevelManager", true, false).show_victory()
	
	# 삭제 지연
	get_tree().create_timer(5.0).timeout.connect(queue_free)
