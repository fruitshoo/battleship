extends Area3D

## 신기전 로켓 (Singigeon Rocket)
## 빠르게 직선 비행, 적 충돌 시 범위 피해 및 화약 폭발 효과

@export var speed: float = 45.0
@export var damage: float = 2.5 # 함선 데미지 하향 (5.0 -> 2.5)
@export var personnel_damage_mult: float = 5.0 # 병사 데미지 배수 하향 (25 -> 5)
@export var lifetime: float = 3.0
@export var blast_radius: float = 3.5
@export var explosion_scene: PackedScene = preload("res://scenes/effects/rocket_explosion.tscn")

var team: String = "player"
var shooter: Node3D = null # 이 로켓을 쏜 선박 (오사 방지용)

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
	
	# 발사 사운드 재생 (01, 02, 03 무작위 선택)
	if is_instance_valid(AudioManager):
		var rand = randf()
		var sfx_name = "rocket_launch_01"
		if rand > 0.66: sfx_name = "rocket_launch_03"
		elif rand > 0.33: sfx_name = "rocket_launch_02"
		
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
	if has_exploded: return
	
	var hit_obj = target
	# 적군인지 확인 (함선 본체거나 병사거나)
	if not (hit_obj.is_in_group("enemy") or hit_obj.is_in_group("player")):
		var parent = hit_obj.get_parent()
		if parent and (parent.is_in_group("enemy") or parent.is_in_group("player")):
			hit_obj = parent
	
	# 다른 팀인지 확인
	var target_group = "enemy" if team == "player" else "player"
	if not hit_obj.is_in_group(target_group):
		return
		
	# 자기 자신(쏜 사람)은 절대로 맞지 않음
	if shooter and (hit_obj == shooter or hit_obj.get_parent() == shooter):
		return

	# 직접 맞은 대상에게만 데미지 적용
	_apply_damage(hit_obj)
	_explode()
	queue_free()

func _apply_damage(target_node: Node) -> void:
	if not is_instance_valid(target_node): return
	
	# 데미지 보정 (블랙 파우더 업그레이드 등)
	var dmg_mult = 1.0
	var fire_lv = 0
	if is_instance_valid(UpgradeManager):
		var powder_lv = UpgradeManager.current_levels.get("black_powder", 0)
		dmg_mult += (0.2 * powder_lv)
		fire_lv = UpgradeManager.current_levels.get("fire_arrows", 0)

	if target_node.has_method("take_damage"):
		var final_damage = damage * dmg_mult
		if target_node is CharacterBody3D or target_node.is_in_group("soldiers"):
			final_damage *= personnel_damage_mult
		
		target_node.take_damage(final_damage, global_position)
		
		# 점화 효과
		if fire_lv > 0 and target_node.has_method("take_fire_damage"):
			target_node.take_fire_damage(fire_lv * 2.0, 5.0)
	elif target_node.has_method("die"):
		target_node.die()

func _explode() -> void:
	has_exploded = true
	
	# 트레일 중단
	var trail = get_node_or_null("RocketTrail")
	if trail:
		trail.emitting = false
	
	# 폭발 VFX(화염/연기) 제거 - 요청에 따라 나무 파편(take_damage 내에 있음)만 남김
	# 폭발 사운드는 타격감 유지를 위해 남겨둠
	if is_instance_valid(AudioManager):
		AudioManager.play_sfx("impact_wood", global_position, randf_range(0.7, 0.9))
