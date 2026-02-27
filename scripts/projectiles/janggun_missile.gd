extends Area3D

## 장군전 미사일 (Janggun Missile)
## 느리지만 고데미지 통나무 미사일. 범위 피해.

@export var speed: float = 25.0
@export var damage: float = 15.0 # 즉발 데미지 (최강 무기)
@export var dot_damage: float = 3.0 # 누수 데미지 (초당 3.0)
@export var speed_debuff: float = 0.7 # 속도 30% 감소
@export var turn_debuff: float = 0.6 # 선회 40% 감소
@export var stick_duration: float = 15.0 # 박혀있는 시간 (10 -> 15)

@export var arc_height: float = 8.0
@export var muzzle_flash_scene: PackedScene = preload("res://scenes/effects/muzzle_flash.tscn")
@export var muzzle_smoke_scene: PackedScene = preload("res://scenes/effects/muzzle_smoke.tscn")

var start_pos: Vector3 = Vector3.ZERO
var target_pos: Vector3 = Vector3.ZERO
var progress: float = 0.0
var duration: float = 1.0
var is_stuck: bool = false
var is_sinking: bool = false
var target_ship: Node3D = null

func _ready() -> void:
	var distance = start_pos.distance_to(target_pos)
	duration = distance / speed
	if duration < 0.5: duration = 0.5
	
	global_position = start_pos
	
	# 발사 연출 (Screen Shake + Muzzle Effects)
	_play_launch_vfx()
	
	area_entered.connect(_on_hit)
	body_entered.connect(_on_hit)

func _physics_process(_delta: float) -> void:
	if is_stuck or is_sinking: return
	
	progress += _delta / duration
	# 비선형 가속 연출 (Ease-In: 초반엔 육중하게 출발)
	# progress 0.0 -> 1.0 을 곡선형으로 변환
	var t = progress * progress # Quadratic Ease-In
	
	var current_pos = start_pos.lerp(target_pos, t)
	var y_offset = sin(PI * t) * arc_height
	current_pos.y += y_offset
	
	# 육중함 표현을 위한 미세한 진동 (Wobble)
	var wobble = Vector3(
		sin(progress * 40.0) * 0.05,
		cos(progress * 35.0) * 0.05,
		0
	)
	current_pos += global_transform.basis * wobble
	
	if (current_pos - global_position).length_squared() > 0.001:
		look_at(current_pos, Vector3.UP)
		
	global_position = current_pos

func _on_hit(target: Node) -> void:
	if is_stuck: return
	
	var ship = target if target.is_in_group("enemy") or target.is_in_group("player") else null
	if not ship:
		var p = target.get_parent()
		if p and (p.is_in_group("enemy") or p.is_in_group("player")):
			ship = p
	
	if ship:
		_play_impact_vfx() # 임팩트 이펙트 재생
		_stick_to_ship(ship)
		
		# 충돌 화면 흔들림 (강력)
		var cam = get_viewport().get_camera_3d()
		if cam and cam.has_method("shake"):
			cam.shake(0.5, 0.25)

func _stick_to_ship(ship: Node3D) -> void:
	is_stuck = true
	target_ship = ship
	
	# 데미지 주기
	if ship.has_method("take_damage"):
		ship.take_damage(damage, global_position)
	
	# 물리/충돌 끄기
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	
	# 함선에 고정 (Reparent) - 물리 콜백 중 리페어런팅 에러 방지를 위해 지연 호출
	call_deferred("reparent", ship)
	
	# 디버프 적용
	if ship.has_method("add_stuck_object"):
		ship.add_stuck_object(self , speed_debuff, turn_debuff)
	
	if ship.has_method("add_leak"):
		ship.add_leak(dot_damage)
	
	print("🪵 장군전이 함선에 박혔습니다! (즉발:%.0f, 누수:%.1f/s)" % [damage, dot_damage])
	
	# 일정 시간 후 제거
	get_tree().create_timer(stick_duration).timeout.connect(_unstick)

func _unstick() -> void:
	if is_instance_valid(target_ship) and target_ship.has_method("remove_stuck_object"):
		target_ship.remove_stuck_object(self , speed_debuff, turn_debuff)
	
	if is_instance_valid(target_ship) and target_ship.has_method("remove_leak"):
		target_ship.remove_leak(dot_damage)
	
	queue_free()

@export var wood_splinter_scene: PackedScene = preload("res://scenes/effects/wood_splinter.tscn")
@export var shockwave_scene: PackedScene = preload("res://scenes/effects/shockwave.tscn")

func _splash_and_sink() -> void:
	if is_sinking: return
	is_sinking = true
	
	var tween = create_tween()
	tween.tween_property(self , "position:y", position.y - 2.0, 1.0)
	tween.tween_callback(queue_free)

func _play_impact_vfx() -> void:
	# 나무 파편 이펙트
	if wood_splinter_scene:
		var splinter = wood_splinter_scene.instantiate()
		get_tree().root.add_child(splinter)
		splinter.global_position = global_position
		if splinter.has_method("set_amount_by_damage"):
			splinter.set_amount_by_damage(damage)
	
	# 피격 사운드 (장군전 전용 중타격음)
	if is_instance_valid(AudioManager):
		AudioManager.play_sfx("heavy_missle_impact", global_position, randf_range(0.8, 1.0))

func _play_launch_vfx() -> void:
	# 화면 흔들림
	var cam = get_viewport().get_camera_3d()
	if cam and cam.has_method("shake"):
		cam.shake(0.6, 0.3)
	
	var launch_dir = (target_pos - start_pos).normalized()
	
	# 머즐 플래시
	if muzzle_flash_scene:
		var flash = muzzle_flash_scene.instantiate()
		get_tree().root.add_child(flash)
		flash.global_position = global_position
		if flash.has_method("set_fire_direction"):
			flash.set_fire_direction(launch_dir)
			
	# 머즐 연기
	if muzzle_smoke_scene:
		var smoke = muzzle_smoke_scene.instantiate()
		get_tree().root.add_child(smoke)
		smoke.global_position = global_position
		smoke.look_at(global_position + launch_dir, Vector3.UP)
		if smoke is GPUParticles3D:
			smoke.emitting = true
