extends Area3D
const HitTargetResolver = preload("res://scripts/helpers/hit_target_resolver.gd")

## 팔우노 화살 (Ballista Bolt)
## 고속으로 비행하며 다수의 대상을 관통하고 강력한 넉백을 줍니다.

@export var speed: float = 70.0
@export var lifetime: float = 3.0
var damage: float = 45.0
var max_pierce: int = 3
var team: String = "player"
var direction: Vector3 = Vector3.FORWARD

var pierce_count: int = 0
var hit_list: Array[Node] = []

func _ready() -> void:
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(lifetime).timeout.connect(queue_free)

func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta

func _on_area_entered(area: Area3D) -> void:
	_check_hit(area)

func _on_body_entered(body: Node3D) -> void:
	_check_hit(body)

func _check_hit(target: Node) -> void:
	if pierce_count >= max_pierce: return
	if target in hit_list: return
	
	# 피아식별
	var is_enemy = false
	var enemy_node = null
	
	if target.is_in_group("soldiers"):
		if target.get("team") != team:
			is_enemy = true
			enemy_node = target
	else:
		var ship = HitTargetResolver.resolve_ship_from_node(target)
		if ship and HitTargetResolver.resolve_team_tag(ship) != team:
			is_enemy = true
			enemy_node = ship
			
	if is_enemy:
		hit_list.append(target)
		pierce_count += 1
		
		# 데미지 적용
		if enemy_node.has_method("take_damage"):
			var source_id = "ballista" if team == "player" else ""
			enemy_node.take_damage(damage, global_position, source_id)
			
		# 넉백 (병사일 경우)
		if enemy_node.is_in_group("soldiers"):
			_apply_knockback(enemy_node)
			
		# 사운드 및 이펙트 (관통 시 가벼운 타격음)
		var audio_manager = get_node_or_null("/root/AudioManager")
		if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
			audio_manager.play_sfx("impact_wood", global_position, 1.2)
			
		# 일정 횟수 이상 관통하면 소멸
		if pierce_count >= max_pierce:
			queue_free()

func _apply_knockback(soldier: Node3D) -> void:
	if not is_instance_valid(soldier): return
	
	# 병사의 velocity에 직접 힘을 가하거나 state를 잠시 변경
	var knockback_dir = direction.normalized()
	knockback_dir.y = 0.5 # 살짝 위로 띄움
	
	if "velocity" in soldier:
		soldier.velocity += knockback_dir * 10.0
	
	# 병사가 AI 상태라면 잠시 비틀거리게 할 수 있음 (State.IDLE 등으로 강제 전환 등)
	if soldier.has_method("set"):
		# 만약 병사 스크립트에 비틀거림 상태가 있다면 적용 (없으면 패스)
		pass
