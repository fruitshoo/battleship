extends Area3D

## 생존자(Survivor) 시스템
## 적함 침몰 시 발생하며, 플레이어가 다가가면 자석처럼 끌려와 병사로 합류함

@export var base_magnet_radius: float = 8.0 # 기본 자석 효과 범위
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
	base_y = global_position.y
	if base_y < 0.2: base_y = 0.5
	
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
		
		# 컬링 방지 마진 추가
		visual.extra_cull_margin = 1.0
		
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
		var current_radius = _get_current_magnet_radius()
		if dist <= current_radius:
			# 자석 효과: 거리가 가까울수록 더 빠르게 가속
			current_magnet_speed = lerp(current_magnet_speed, magnet_speed + (10.0 / max(dist, 1.0)), 3.0 * delta)
			var direction = (target_player.global_position - global_position).normalized()
			global_position += direction * current_magnet_speed * delta
			
			# 근거리 자동 획득 (충돌 미감지 보완)
			if dist < 2.5: # 2.0 -> 2.5
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
	var closest_dist = INF
	var closest_p = null
	
	for p in players:
		if p.get("is_sinking"): continue
		
		var d = global_position.distance_to(p.global_position)
		if d < closest_dist:
			closest_dist = d
			closest_p = p
			
	if closest_dist <= _get_current_magnet_radius() * 1.5:
		target_player = closest_p
	else:
		target_player = null


func _get_current_magnet_radius() -> float:
	var um = get_node_or_null("/root/UpgradeManager")
	if is_instance_valid(um) and "current_levels" in um:
		var supply_lv = um.current_levels.get("supply_bonus", 0)
		return base_magnet_radius + (supply_lv * 2.0)
	return base_magnet_radius


func _on_body_entered(body: Node3D) -> void:
	if is_collected: return
	var ship = _get_ship_from_node(body)
	if ship and ship.is_in_group("player"):
		_try_collect(ship)

func _on_area_entered(area: Area3D) -> void:
	if is_collected: return
	var ship = _get_ship_from_node(area)
	if ship and ship.is_in_group("player"):
		_try_collect(ship)

func _collect_by_proximity() -> void:
	if is_collected: return
	if is_instance_valid(target_player):
		_try_collect(target_player)

func _get_ship_from_node(node: Node) -> Node3D:
	if not node: return null
	if node.is_in_group("player"): return node
	
	# 부모나 주인(owner)이 함선인지 확인
	var p = node.get_parent()
	if p and p.is_in_group("player"): return p
	
	if node is CollisionShape3D or node is Area3D:
		var pp = node.get_parent()
		if pp and pp.is_in_group("player"): return pp
		
	if node.owner and node.owner.is_in_group("player"):
		return node.owner
		
	return null


func _try_collect(player_ship: Node3D) -> void:
	if is_collected: return
	
	# 플레이어 배에 병사 추가 시도
	if player_ship and player_ship.has_method("add_survivor"):
		if player_ship.add_survivor():
			is_collected = true
			
			# 생존자 구조 시에도 체력 소폭 회복 로직 추가
			if "hull_hp" in player_ship and "max_hull_hp" in player_ship:
				var um = get_node_or_null("/root/UpgradeManager")
				var supply_lv = 0
				if is_instance_valid(um) and "current_levels" in um:
					supply_lv = um.current_levels.get("supply_bonus", 0)
				
				var heal_amount = 5.0 + (supply_lv * 5.0) # 기본 5, 레벨당 +5
				player_ship.hull_hp = minf(player_ship.hull_hp + heal_amount, player_ship.max_hull_hp)
				
				if player_ship.has_method("_find_hud"):
					var hud = player_ship._find_hud()
					if hud and hud.has_method("update_hull_hp"):
						hud.update_hull_hp(player_ship.hull_hp, player_ship.max_hull_hp)
			
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
