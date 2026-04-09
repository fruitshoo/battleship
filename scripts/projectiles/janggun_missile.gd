extends Area3D
const HitTargetResolver = preload("res://scripts/helpers/hit_target_resolver.gd")
const EntityRegistry = preload("res://scripts/helpers/entity_registry.gd")
const NodeContractHelper = preload("res://scripts/helpers/node_contract_helper.gd")
const ScenePool = preload("res://scripts/helpers/scene_pool.gd")
const VfxBudget = preload("res://scripts/helpers/vfx_budget.gd")

## 장군전 미사일 (Janggun Missile)
## 느리지만 고데미지 통나무 미사일. 범위 피해.

@export var speed: float = 18.0
@export var damage: float = 15.0 # 즉발 데미지 (최강 무기)
@export var dot_damage: float = 3.0 # 누수 데미지 (초당 3.0)
@export var speed_debuff: float = 0.7 # 속도 30% 감소
@export var turn_debuff: float = 0.6 # 선회 40% 감소
@export var stick_duration: float = 15.0 # 박혀있는 시간 (10 -> 15)

@export var arc_height: float = 8.0
@export var muzzle_smoke_scene: PackedScene = preload("res://scenes/effects/impact_puff.tscn")
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

func _ready() -> void:
	# 시그널은 한 번만 연결
	area_entered.connect(_on_hit)
	body_entered.connect(_on_hit)
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
	progress = 0.0
	target_ship = null
	
	# 초기화 시 모니터링 다시 켜기
	monitoring = true
	monitorable = true
	
	# 수치 반영
	_update_stats()
	
	global_position = start_pos
	
	var distance = start_pos.distance_to(target_pos)
	duration = distance / speed
	if duration < 0.7: duration = 0.7
	arc_height = clamp(distance * 0.12, 1.5, 8.0)
	
	if start_pos.distance_squared_to(target_pos) > 0.1:
		look_at(target_pos, Vector3.UP)
	
	_play_launch_vfx()

func _update_stats() -> void:
	# 업그레이드 수치 반영 (DoT, 디버프 강화)
	dot_damage = 3.0 + janggun_lv * 1.5
	speed_debuff = maxf(0.2, 0.7 - janggun_lv * 0.05)
	turn_debuff = maxf(0.2, 0.6 - janggun_lv * 0.05)

func _physics_process(delta: float) -> void:
	if is_stuck or is_sinking: return
	
	progress += delta / duration
	# SLBM 같은 느낌을 주는 비선형 가속(Ease-In) 제거 -> 강력한 초기 추진력 표현을 위해 선형(Linear)으로 변경
	var t = progress
	
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

func _on_hit(target: Node) -> void:
	if is_stuck: return
	
	var ship = HitTargetResolver.resolve_ship_from_node(target)
	
	if ship:
		var target_is_sinking = NodeContractHelper.is_sinking_or_dying(ship)
		if target_is_sinking:
			return # 침몰 중인 배엔 데미지도 스플래시도 넣지 않고 통과 (또는 다른 처리)
			
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
	
	ScenePool.release(self)


func _splash_and_sink() -> void:
	if is_sinking: return
	is_sinking = true
	
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
	tween.tween_callback(func(): ScenePool.release(self))

func _play_impact_vfx() -> void:
	# 나무 파편 이펙트
	if wood_splinter_scene and VfxBudget.allow_spawn(get_tree(), "wood_splinter", global_position, 3, 60.0):
		var splinter = ScenePool.acquire(get_tree(), wood_splinter_scene)
		splinter.position = global_position
		get_tree().root.add_child(splinter)
		if splinter.has_method("set_amount_by_damage"):
			splinter.set_amount_by_damage(damage)
		if splinter.has_method("pool_activate"):
			splinter.pool_activate()
			
	# 타격 시 검은 연기 (발사 연기 재사용)
	if muzzle_smoke_scene and VfxBudget.allow_spawn(get_tree(), "muzzle_smoke", global_position, 5, 65.0):
		var smoke = ScenePool.acquire(get_tree(), muzzle_smoke_scene)
		if smoke.has_method("configure_as_hit"):
			smoke.configure_as_hit()
		smoke.position = global_position
		# Basis.looking_at은 타겟 벡터가 0이면 오류가 나므로 가드 추가
		var smoke_dir = Vector3.UP
		smoke.basis = Basis.looking_at(smoke_dir, Vector3.FORWARD)
		get_tree().root.add_child(smoke)
		if smoke.has_method("pool_activate"):
			smoke.pool_activate()
	
	# 피격 사운드 (장군전 전용 중타격음)
	var audio_manager = get_node_or_null("/root/AudioManager")
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx("heavy_missle_impact", global_position, randf_range(0.8, 1.0))

func _play_launch_vfx() -> void:
	# 화면 흔들림
	var cam = get_viewport().get_camera_3d()
	if cam and cam.has_method("shake"):
		cam.shake(0.6, 0.3)
	
	var launch_dir = (target_pos - start_pos).normalized()
	
	# 머즐 연기
	if muzzle_smoke_scene and VfxBudget.allow_spawn(get_tree(), "muzzle_smoke", global_position, 5, 65.0):
		var smoke = ScenePool.acquire(get_tree(), muzzle_smoke_scene)
		if smoke.has_method("configure_as_muzzle"):
			smoke.configure_as_muzzle()
		smoke.position = global_position
		# Basis.looking_at은 타겟 벡터가 0이면 오류가 발생하므로 체크
		var smoke_look_dir = launch_dir if not launch_dir.is_zero_approx() else Vector3.FORWARD
		smoke.basis = Basis.looking_at(smoke_look_dir, Vector3.UP)
		get_tree().root.add_child(smoke)
		if smoke.has_method("pool_activate"):
			smoke.pool_activate()
