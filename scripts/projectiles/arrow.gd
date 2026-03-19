extends Area3D
const HitTargetResolver = preload("res://scripts/helpers/hit_target_resolver.gd")
const ScenePool = preload("res://scripts/helpers/scene_pool.gd")
const VfxBudget = preload("res://scripts/helpers/vfx_budget.gd")

## 화살 (Arrow)
## 병사가 쏘는 원거리 투사체

@export var damage: float = 15.0
@export var speed: float = 25.0 # 초당 이동 거리 (이전 20.0 -> 8.0 -> 14.0 -> 16.0 -> 25.0)
@export var arc_height: float = 2.0 # 포물선 최대 높이

var start_pos: Vector3 = Vector3.ZERO
var target_pos: Vector3 = Vector3.ZERO
var target_node: Node3D = null # 목표물 참조 (강제 명중 판정용)
var team: String = "player"
var damage_source: String = "bow"
var is_fire_arrow: bool = false
var fire_damage: float = 0.0

var progress: float = 0.0
var duration: float = 1.0

func _ready() -> void:
	# 초기화: 소환 시점에 설정된 위치 데이터로 계산
	var distance = start_pos.distance_to(target_pos)
	duration = distance / speed
	if duration < 0.2: duration = 0.2
	
	global_position = start_pos
	
	# 신호 연결
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	progress += delta / duration
	
	if progress >= 1.0:
		# 도달 시 강제 타격 판정 (트리거 충돌 무시 현상 방지)
		if is_instance_valid(target_node) and not target_node.is_queued_for_deletion():
			# 목표물이 아직 주변에 있다면 (이동 중일 수 있으므로 반경 3.0m 이내 허용)
			if global_position.distance_to(target_node.global_position) < 3.0:
				_check_hit(target_node)
				
		global_position = target_pos
		queue_free()
		return
	
	# 수평 이동 (LERP)
	var current_pos = start_pos.lerp(target_pos, progress)
	
	# 수직 곡선 (sin 이용)
	var y_offset = sin(PI * progress) * arc_height
	current_pos.y += y_offset
	
	# 회전 (진행 방향 응시)
	if (current_pos - global_position).length_squared() > 0.001:
		var dir = (current_pos - global_position).normalized()
		var up_vec = Vector3.UP
		if abs(dir.y) > 0.999:
			up_vec = Vector3.RIGHT
		look_at(current_pos, up_vec)
		
	global_position = current_pos

	# 수면(y=0.0) 타격 감지 기능 추가
	if global_position.y <= 0.0:
		_splash_and_sink()

func _splash_and_sink() -> void:
	# 화살은 스플래시만 작게 재생
	var water_explosion_scene = preload("res://scenes/effects/water_burst.tscn")
	if water_explosion_scene and VfxBudget.allow_spawn(get_tree(), "water_explosion_small", global_position, 2, 60.0):
		var pos = global_position
		var explosion = ScenePool.acquire(get_tree(), water_explosion_scene)
		if explosion.has_method("configure_as_small"):
			explosion.configure_as_small()
		explosion.position = Vector3(pos.x, 0.05, pos.z)
		get_tree().root.add_child(explosion)
		if explosion.has_method("pool_activate"):
			explosion.pool_activate()
		
	var audio_manager = get_node_or_null("/root/AudioManager")
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx("water_splash_small", global_position, randf_range(0.9, 1.2))
		
	queue_free()

func _on_area_entered(area: Area3D) -> void:
	_check_hit(area)

func _on_body_entered(body: Node3D) -> void:
	_check_hit(body)

func _check_hit(target: Node) -> void:
	# 자신과 같은 팀이면 무시
	if target.is_in_group("soldiers"):
		if target.get("team") == team:
			return
		
		# 적군 병사 피격
		if target.has_method("take_damage"):
			target.take_damage(damage, global_position, damage_source)
			# 불화살 이펙트 소환 등 가능
			queue_free()
	
	# 적 배 피격 (HitArea 등 하위 노드에서 부모 함선까지 자동 해석)
	var potential_ship = HitTargetResolver.resolve_ship_from_node(target)
	if potential_ship:
		var is_sinking = potential_ship.get("is_sinking") == true
		if is_sinking:
			queue_free()
			return
		
		# 활/연노는 선체를 공격하지 않는다.
		# 배와 스치거나 히트박스를 지나가더라도 무시하고 계속 날아가 병사만 노린다.
		return
