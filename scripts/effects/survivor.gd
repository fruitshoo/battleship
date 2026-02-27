extends Area3D

## 생존자(Survivor) 시스템
## 적함 침몰 시 발생하며, 플레이어가 다가가면 자석처럼 끌려와 병사로 합류함

@export var magnet_radius: float = 7.0 # 자석 효과 범위 (12.0 -> 7.0 하향)
@export var magnet_speed: float = 5.0 # 끌려가는 기본 속도
@export var float_speed: float = 1.5 # 둥실거리는 속도
@export var float_height: float = 0.2 # 둥실거리는 진폭
@export var rotation_speed: float = 0.5 # 회전 속도

var target_player: Node3D = null
var current_magnet_speed: float = 0.0
var base_y: float = 0.0
var time_alive: float = 0.0
var is_collected: bool = false

@onready var visual = $MeshInstance3D if has_node("MeshInstance3D") else self

func _ready() -> void:
	base_y = position.y
	
	# 파란색 캡슐 이미지 설정 (병사 캐릭터와 동일하게)
	if visual and visual is MeshInstance3D:
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.4, 0.8) # Blue (Player Team Color)
		mat.emission_enabled = true
		mat.emission = Color(0.2, 0.4, 0.8)
		mat.emission_energy_multiplier = 0.5
		visual.set_surface_override_material(0, mat)
		
		# 초기 등장 페이드인 및 스케일 업
		visual.scale = Vector3.ZERO
		var tween = create_tween().set_parallel(true)
		tween.tween_property(visual, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		
	# 획득 이벤트 연결
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)


@export var lifetime: float = 90.0 # 소멸 시간 (초, 생존자는 조금 더 길게)
var is_expiring: bool = false # 소멸 진행 중 여부

func _physics_process(delta: float) -> void:
	if is_collected: return
	time_alive += delta
	
	# 수명 체크 및 소멸 연출 시작
	if not is_expiring and time_alive > lifetime - 15.0:
		_start_expire_sequence()
	
	if time_alive > lifetime:
		_expire_and_free()
		return

	if not is_instance_valid(target_player):
		_find_target_player()
	
	if is_instance_valid(target_player):
		var dist = global_position.distance_to(target_player.global_position)
		if dist <= magnet_radius:
			# 자석 효과: 거리가 가까울수록 더 빠르게 가속
			current_magnet_speed = lerp(current_magnet_speed, magnet_speed + (10.0 / max(dist, 1.0)), 3.0 * delta)
			var direction = (target_player.global_position - global_position).normalized()
			global_position += direction * current_magnet_speed * delta
			
			# 근거리 자동 획득 (충돌 미감지 보완)
			if dist < 2.0:
				_collect_by_proximity()
		else:
			current_magnet_speed = 0.0
			_apply_floating(delta)
	else:
		_apply_floating(delta)


func _start_expire_sequence() -> void:
	is_expiring = true
	# 깜빡이는 효과 (Material의 emission 강도로 경고)
	if visual and visual is MeshInstance3D:
		var mat = visual.get_surface_override_material(0)
		if mat is StandardMaterial3D:
			var tween = create_tween().set_loops(15)
			tween.tween_property(mat, "albedo_color:a", 0.4, 0.5)
			tween.tween_property(mat, "albedo_color:a", 1.0, 0.5)

func _expire_and_free() -> void:
	is_collected = true # 획득 방지
	var tween = create_tween().set_parallel(true)
	# 가라앉으며 사라짐
	tween.tween_property(self , "position:y", position.y - 1.5, 2.0)
	if visual:
		tween.tween_property(visual, "scale", Vector3.ZERO, 2.0)
	tween.chain().tween_callback(queue_free)


func _apply_floating(delta: float) -> void:
	# 물 위에서 둥실공실
	position.y = base_y + sin(time_alive * float_speed) * float_height
	if visual:
		visual.rotation.y += rotation_speed * delta
		visual.rotation.z = sin(time_alive * float_speed * 1.2) * 0.15


func _find_target_player() -> void:
	var players = get_tree().get_nodes_in_group("player")
	# 진짜 플레이어 배를 우선 탐색 (나포함 제외)
	for p in players:
		if p.get("is_player_controlled") == true and not p.get("is_sinking"):
			target_player = p
			return
	# 못 찾으면 나포함이 아닌 아무나
	for p in players:
		if not p.is_in_group("captured_minion"):
			target_player = p
			return


func _on_body_entered(body: Node3D) -> void:
	if is_collected: return
	
	# 플레이어와 충돌했는지 확인
	var is_player = false
	if body.is_in_group("player"):
		is_player = true
	elif body.owner and body.owner.is_in_group("player"):
		is_player = true
	elif body.get_parent() and body.get_parent().is_in_group("player"):
		is_player = true
		
	if is_player:
		var ship = body if body.is_in_group("player") else (body.owner if body.owner and body.owner.is_in_group("player") else body.get_parent())
		_try_collect(ship)

func _on_area_entered(area: Area3D) -> void:
	if is_collected: return
	var parent = area.get_parent()
	if parent and parent.is_in_group("player") and parent.get("is_player_controlled") == true:
		_try_collect(parent)

func _collect_by_proximity() -> void:
	if is_collected: return
	if is_instance_valid(target_player) and target_player.get("is_player_controlled") == true:
		_try_collect(target_player)


func _try_collect(player_ship: Node3D) -> void:
	if is_collected: return
	
	# 플레이어 배에 병사 추가 시도
	if player_ship and player_ship.has_method("add_survivor"):
		if player_ship.add_survivor():
			is_collected = true
			_finish_collection()
		else:
			# 정원이 가득 찬 경우: 획득하지 않고 그냥 밀려남 (튕겨나가는 연출)
			var bounce_dir = (global_position - player_ship.global_position).normalized()
			global_position += bounce_dir * 2.0
			current_magnet_speed = 0.0


func _finish_collection() -> void:
	# 획득 시 사라지는 연출
	if visual:
		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(visual, "scale", Vector3.ZERO, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tween.tween_property(visual, "position:y", position.y + 2.0, 0.3)
		tween.chain().tween_callback(queue_free)
	else:
		queue_free()
