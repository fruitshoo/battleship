extends Area3D

## 신기전 로켓 (Singigeon Rocket)
## 빠르게 직선 비행, 적 충돌 시 범위 피해 및 화약 폭발 효과

@export var speed: float = 70.0
@export var damage: float = 5.0 # 함선 데미지
@export var personnel_damage_mult: float = 25.0 # 병사에게는 25배 데미지
@export var lifetime: float = 3.0
@export var blast_radius: float = 3.5
@export var explosion_scene: PackedScene = preload("res://scenes/effects/rocket_explosion.tscn")

var team: String = "player"

var start_pos: Vector3 = Vector3.ZERO
var target_pos: Vector3 = Vector3.ZERO
var progress: float = 0.0
var duration: float = 1.0
@export var arc_height: float = 3.0
var has_exploded: bool = false

func _ready() -> void:
	var distance = start_pos.distance_to(target_pos)
	duration = distance / speed
	if duration < 0.3: duration = 0.3
	
	global_position = start_pos
	
	# 발사 사운드 재생 (01 또는 02 무작위 선택)
	if is_instance_valid(AudioManager):
		var sfx_name = "rocket_launch_01" if randf() < 0.5 else "rocket_launch_02"
		AudioManager.play_sfx(sfx_name, global_position, randf_range(0.9, 1.1))
	
	area_entered.connect(_on_hit)
	body_entered.connect(_on_hit)

func _physics_process(delta: float) -> void:
	progress += delta / duration
	
	if progress >= 1.0:
		if not has_exploded:
			_explode()
		queue_free()
		return
	
	var current_pos = start_pos.lerp(target_pos, progress)
	var y_offset = sin(PI * progress) * arc_height
	current_pos.y += y_offset
	
	if (current_pos - global_position).length_squared() > 0.001:
		look_at(current_pos, Vector3.UP)
		
	global_position = current_pos

func _on_hit(target: Node) -> void:
	var enemy = target if target.is_in_group("enemy") else target.get_parent()
	if not (enemy and enemy.is_in_group("enemy")):
		return
	
	if not has_exploded:
		_explode()
	queue_free()

func _explode() -> void:
	has_exploded = true
	
	# 폭발 이펙트 생성
	if explosion_scene:
		var explosion = explosion_scene.instantiate()
		get_tree().root.add_child(explosion)
		explosion.global_position = global_position
	
	# 폭발 사운드
	if is_instance_valid(AudioManager):
		AudioManager.play_sfx("impact_wood", global_position, randf_range(0.7, 0.9))
	
	# 시너지 데이터
	var blast_mult = 1.0
	var fire_lv = 0
	if is_instance_valid(UpgradeManager):
		var powder_lv = UpgradeManager.current_levels.get("black_powder", 0)
		blast_mult += (0.2 * powder_lv)
		fire_lv = UpgradeManager.current_levels.get("fire_arrows", 0)

	# 데미지 처리
	var target_group = "enemy" if team == "player" else "player"
	var targets = get_tree().get_nodes_in_group(target_group)
	
	for s in get_tree().get_nodes_in_group("soldiers"):
		if is_instance_valid(s) and s.get("team") == target_group:
			targets.append(s)
	
	var final_radius = blast_radius * blast_mult
	
	for e in targets:
		if is_instance_valid(e):
			var dist = global_position.distance_to(e.global_position)
			if dist <= final_radius:
				if e.has_method("take_damage"):
					var final_damage = damage
					if e is CharacterBody3D or e.is_in_group("soldiers"):
						final_damage *= personnel_damage_mult
					
					e.take_damage(final_damage, global_position)
					
					if fire_lv > 0 and e.has_method("take_fire_damage"):
						e.take_fire_damage(fire_lv * 2.0, 5.0)
					elif fire_lv > 0 and e.is_in_group("soldiers"):
						pass
				elif e.has_method("die"):
					e.die()
