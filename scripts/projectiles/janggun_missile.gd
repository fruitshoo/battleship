extends Area3D
const WoodSplinter = preload("res://scripts/effects/wood_splinter.gd")
const PhysicsFrameProfiler = preload("res://scripts/debug/physics_frame_profiler.gd")

## 장군전 투사체
## 포문에서 느리게 발사되는 중형 화전형 투사체.

@export var speed: float = 18.0
@export var damage: float = 15.0 # 즉발 데미지
@export var dot_damage: float = 3.0 # 누수 데미지 (초당 3.0)
@export var speed_debuff: float = 0.7 # 속도 30% 감소
@export var turn_debuff: float = 0.6 # 선회 40% 감소
@export var stick_duration: float = 15.0 # 박혀있는 시간 (10 -> 15)

@export var arc_height: float = 4.0
@export var impact_puff_scene: PackedScene = preload("res://scenes/effects/impact_puff.tscn")
@export var wood_splinter_scene: PackedScene = preload("res://scenes/effects/wood_splinter.tscn")
var water_explosion_scene: PackedScene = preload("res://scenes/effects/water_burst.tscn")

var start_pos: Vector3 = Vector3.ZERO
var target_pos: Vector3 = Vector3.ZERO
var progress: float = 0.0
var duration: float = 1.0
var is_stuck: bool = false
var is_sinking: bool = false
var target_ship: Node3D = null
var janggun_lv: int = 0
var team: String = "player"
var _is_releasing: bool = false

func _ready() -> void:
	# 시그널은 한 번만 연결
	area_entered.connect(_on_hit)
	body_entered.connect(_on_hit)
	if start_pos.distance_squared_to(target_pos) > 0.1:
		_begin_flight()
	else:
		pool_reset()


func _enter_tree() -> void:
	if process_mode == Node.PROCESS_MODE_DISABLED:
		return
	EntityRegistry.register_projectile(self)


func _exit_tree() -> void:
	EntityRegistry.unregister_projectile(self)

func pool_capacity() -> int:
	return 15

func pool_reset() -> void:
	is_stuck = false
	is_sinking = false
	_is_releasing = false
	progress = 0.0
	target_ship = null
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	monitoring = false
	monitorable = false


func launch(
	spawn_position: Vector3,
	final_target_pos: Vector3,
	fire_team: String,
	final_damage: float,
	projectile_speed: float,
	final_janggun_lv: int
) -> void:
	start_pos = spawn_position
	target_pos = final_target_pos
	team = fire_team
	damage = final_damage
	speed = projectile_speed
	janggun_lv = final_janggun_lv
	_begin_flight()


func _begin_flight() -> void:
	is_stuck = false
	is_sinking = false
	_is_releasing = false
	progress = 0.0
	target_ship = null
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	monitoring = true
	monitorable = true
	_update_stats()
	global_position = start_pos

	var distance = start_pos.distance_to(target_pos)
	duration = distance / maxf(speed, 0.01)
	if duration < 0.55:
		duration = 0.55
	arc_height = clamp(distance * 0.07, 0.8, 4.0)

	if start_pos.distance_squared_to(target_pos) > 0.1:
		look_at(target_pos, Vector3.UP)

	_play_launch_vfx()

func _update_stats() -> void:
	# 업그레이드 수치 반영 (DoT, 디버프 강화)
	dot_damage = 3.0 + janggun_lv * 1.5
	speed_debuff = maxf(0.2, 0.7 - janggun_lv * 0.05)
	turn_debuff = maxf(0.2, 0.6 - janggun_lv * 0.05)

func _physics_process(delta: float) -> void:
	var profile_start := PhysicsFrameProfiler.begin()
	_profiled_physics_process(delta)
	PhysicsFrameProfiler.end("projectile_janggun", profile_start)


func _profiled_physics_process(delta: float) -> void:
	if is_stuck or is_sinking: return

	progress += delta / duration
	# 포문에서 밀려나가는 느낌을 위해 탄속 보간은 선형으로 유지한다.
	var t = minf(progress, 1.0)
	
	var current_pos = start_pos.lerp(target_pos, t)
	var y_offset = sin(PI * t) * arc_height
	current_pos.y += y_offset
	
	if (current_pos - global_position).length_squared() > 0.0001:
		var dir = (current_pos - global_position).normalized()
		var target_look = current_pos + dir
		var up_vec = Vector3.UP
		if abs(dir.y) > 0.999:
			up_vec = Vector3.RIGHT
		look_at(target_look, up_vec)
		
	global_position = current_pos
	
	# 수면(y=0.0) 타격 감지 기능 추가
	if current_pos.y <= 0.0:
		_splash_and_sink()
		return
	if progress >= 1.0:
		_finish_missed_flight()

func _on_hit(target: Node) -> void:
	if is_stuck or is_sinking: return
	
	var ship = HitTargetResolver.resolve_ship_from_node(target)
	
	if ship:
		var target_is_sinking = NodeContractHelper.is_sinking_or_dying(ship)
		if target_is_sinking:
			return # 침몰 중인 배엔 데미지도 스플래시도 넣지 않고 통과 (또는 다른 처리)
			
		_play_impact_vfx() # 임팩트 이펙트 재생
		_stick_to_ship(ship)
		
		# 장군전은 중형 투사체라 흔들림을 대장군전급으로 키우지 않는다.
		var cam = get_viewport().get_camera_3d()
		if cam and cam.has_method("shake"):
			cam.shake(0.32, 0.16)

func _stick_to_ship(ship: Node3D) -> void:
	is_stuck = true
	target_ship = ship
	
	# 데미지 주기
	if ship.has_method("take_damage"):
		var source_id = "janggun" if team == "player" else ""
		ship.take_damage(damage, global_position, source_id)
	
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
	
	# 잦은 장군전 적중 로그는 기본 비활성화
	
	# 일정 시간 후 제거
	get_tree().create_timer(stick_duration).timeout.connect(_unstick)

func _unstick() -> void:
	if is_instance_valid(target_ship) and target_ship.has_method("remove_stuck_object"):
		target_ship.remove_stuck_object(self , speed_debuff, turn_debuff)
	
	if is_instance_valid(target_ship) and target_ship.has_method("remove_leak"):
		target_ship.remove_leak(dot_damage)
	
	_release_self()


func _finish_missed_flight() -> void:
	var splash_pos := global_position
	splash_pos.y = minf(splash_pos.y, 0.2)
	global_position = splash_pos
	_splash_and_sink()


func _splash_and_sink() -> void:
	if is_sinking: return
	is_sinking = true
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	
	# 바다에 떨어질 때 물 폭발 이펙트 생성
	if water_explosion_scene and VfxBudget.allow_spawn(get_tree(), "water_explosion", global_position, 4, 70.0):
		var pos = global_position
		var explosion = ScenePool.acquire(get_tree(), water_explosion_scene)
		if explosion.has_method("configure_as_splash"):
			explosion.configure_as_splash()
		explosion.position = Vector3(pos.x, 0.2, pos.z)
		get_tree().root.add_child(explosion)
		if explosion.has_method("pool_activate"):
			explosion.pool_activate()
	
	# 물보라 사운드
	var audio_manager = get_node_or_null("/root/AudioManager")
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx("water_splash_large", global_position, randf_range(0.8, 1.2))
	
	var tween = create_tween()
	tween.tween_property(self , "position:y", position.y - 2.0, 1.0)
	var self_id: int = get_instance_id()
	tween.tween_callback(func(): ScenePool.release_by_instance_id(self_id))


func _release_self() -> void:
	if _is_releasing:
		return
	_is_releasing = true
	if is_inside_tree():
		set_deferred("monitoring", false)
		set_deferred("monitorable", false)
		set_deferred("process_mode", Node.PROCESS_MODE_DISABLED)
		call_deferred("_finalize_release")
	else:
		monitoring = false
		monitorable = false
		process_mode = Node.PROCESS_MODE_DISABLED
		ScenePool.release(self)


func _finalize_release() -> void:
	if not is_instance_valid(self):
		return
	ScenePool.release(self)

func _play_impact_vfx() -> void:
	var impact_dir := target_pos - start_pos
	if impact_dir.length_squared() <= 0.001:
		impact_dir = -global_basis.z

	# 나무 파편 이펙트
	if wood_splinter_scene:
		var splinter_damage := damage + 8.0
		WoodSplinter.spawn_burst(
			get_tree(),
			wood_splinter_scene,
			global_position + Vector3(0.0, 0.35, 0.0),
			splinter_damage,
			impact_dir,
			"cannon_hit_splinter",
			6,
			140.0
		)
			
	# 타격 이펙트
	if impact_puff_scene and VfxBudget.allow_spawn(get_tree(), "hit_effect", global_position, 8, 180.0):
		var smoke = ScenePool.acquire(get_tree(), impact_puff_scene)
		if smoke.has_method("set_intensity"):
			smoke.set_intensity(1.18)
		get_tree().root.add_child(smoke)
		smoke.global_position = global_position
		# Basis.looking_at은 타겟 벡터가 0이면 오류가 나므로 가드 추가
		var smoke_dir = Vector3.UP
		smoke.global_basis = Basis.looking_at(smoke_dir, Vector3.FORWARD)
		if smoke.has_method("pool_activate"):
			smoke.pool_activate()
	
	# 피격 사운드: 묵직한 장군전 충격음 위에 목재 파열음을 겹친다.
	var audio_manager = get_node_or_null("/root/AudioManager")
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx("heavy_missle_impact", global_position, randf_range(0.94, 1.05), -1.0)
		audio_manager.play_sfx("impact_wood", global_position, randf_range(0.82, 0.96), 1.5)

func _play_launch_vfx() -> void:
	# 화면 흔들림
	var cam = get_viewport().get_camera_3d()
	if cam and cam.has_method("shake"):
		cam.shake(0.22, 0.12)
