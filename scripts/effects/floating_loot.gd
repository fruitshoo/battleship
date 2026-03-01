extends Area3D

## 부유물(Floating Loot) 시스템
## 적을 물리쳤을 때 바다에 스폰되며, 플레이어가 다가가면 자석처럼 끌려와 획득됨

@export var gold_amount: int = 30
@export var xp_amount: int = 15
@export var magnet_radius: float = 8.0 # 자석 효과 범위 (15.0 -> 8.0 하향)
@export var magnet_speed: float = 5.0 # 끌려가는 기본 속도
@export var float_speed: float = 2.0 # 둥실거리는 속도
@export var float_height: float = 0.3 # 둥실거리는 진폭
@export var rotation_speed: float = 1.0 # 회전 속도

var target_player: Node3D = null
var current_magnet_speed: float = 0.0
var base_y: float = 0.0
var time_alive: float = 0.0
var is_collected: bool = false
var _cached_lm: Node = null

@onready var visual = $MeshInstance3D if has_node("MeshInstance3D") else self

func _ready() -> void:
	# 생성 직후의 높이를 base_y로 캡처 (보통 0.5 근처)
	base_y = global_position.y
	if base_y < 0.2: base_y = 0.5 # 비정상적으로 낮게 잡혔을 경우 보정
	
	# 초기에는 투명하게 시작해서 나타남 (스폰 연출)
	if visual and visual is MeshInstance3D:
		var mat = visual.get_active_material(0)
		if mat == null:
			mat = StandardMaterial3D.new()
			visual.set_surface_override_material(0, mat)
		
		# 예시 재질 (나무통/상자 느낌)
		if mat is StandardMaterial3D:
			mat.albedo_color = Color(0.6, 0.4, 0.2)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color.a = 0.0
			
			var tween = create_tween()
			tween.tween_property(mat, "albedo_color:a", 1.0, 1.0)
			
		# 컬링 방지 마진 추가
		visual.extra_cull_margin = 1.0
	
	# 레벨 매니저 캐싱
	_cached_lm = get_tree().root.find_child("LevelManager", true, false)
	if not _cached_lm:
		var lm_nodes = get_tree().get_nodes_in_group("level_manager")
		if lm_nodes.size() > 0: _cached_lm = lm_nodes[0]
	
	# 획득 이벤트 연결
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)


@export var lifetime: float = 60.0 # 소멸 시간 (초)
var is_expiring: bool = false # 소멸 진행 중 여부

func _physics_process(delta: float) -> void:
	if is_collected: return
	time_alive += delta
	
	# 수명 체크 및 소멸 연출 시작
	if not is_expiring and time_alive > lifetime - 10.0:
		_start_expire_sequence()
	
	if time_alive > lifetime:
		_expire_and_free()
		return

	# 가장 가까운 플레이어 탐색 (주기적 탐색 대신 매 프레임 탐지)
	if not is_instance_valid(target_player):
		_find_target_player()
	
	if is_instance_valid(target_player):
		var dist = global_position.distance_to(target_player.global_position)
		if dist <= magnet_radius:
			# 자석 효과 발동: 가속도가 붙으면서 끌려감
			current_magnet_speed = lerp(current_magnet_speed, magnet_speed + (15.0 / max(dist, 1.0)), 2.0 * delta)
			var direction = (target_player.global_position - global_position).normalized()
			global_position += direction * current_magnet_speed * delta
			
			# 근거리 자동 획득 (충돌 미감지 보완)
			if dist < 2.5: # 2.0 -> 2.5 (함선 크기 고려)
				_collect_by_proximity()
		else:
			# 범위를 벗어나면 가속도 초기화 및 제자리 둥실거림
			current_magnet_speed = 0.0
			_apply_floating(delta)
	else:
		_apply_floating(delta)


func _start_expire_sequence() -> void:
	is_expiring = true
	# 깜빡이는 효과 (Material의 alpha 조절)
	if visual and visual is MeshInstance3D:
		var mat = visual.get_surface_override_material(0)
		if mat is StandardMaterial3D:
			var tween = create_tween().set_loops(10)
			tween.tween_property(mat, "albedo_color:a", 0.3, 0.5)
			tween.tween_property(mat, "albedo_color:a", 1.0, 0.5)

func _expire_and_free() -> void:
	is_collected = true # 획득 방지
	var tween = create_tween().set_parallel(true)
	# 가라앉으며 사라짐
	tween.tween_property(self , "position:y", position.y - 1.5, 1.5)
	if visual:
		tween.tween_property(visual, "scale", Vector3.ZERO, 1.5)
	tween.chain().tween_callback(queue_free)


func _apply_floating(delta: float) -> void:
	# 물 위에서 둥실거리고 회전함
	position.y = base_y + sin(time_alive * float_speed) * float_height
	if visual:
		visual.rotation.y += rotation_speed * delta
		visual.rotation.z = sin(time_alive * float_speed * 1.5) * 0.1 # 살짝 갸우뚱


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
			
	# 가장 가까운 아군 배를 타겟으로 함 (본선/나포함 구분 없음)
	if closest_dist <= magnet_radius * 1.5:
		target_player = closest_p
	else:
		target_player = null


func _on_body_entered(body: Node3D) -> void:
	if is_collected: return
	var ship = _get_ship_from_node(body)
	if ship and ship.is_in_group("player"):
		is_collected = true
		_collect_loot()

func _on_area_entered(area: Area3D) -> void:
	if is_collected: return
	var ship = _get_ship_from_node(area)
	if ship and ship.is_in_group("player"):
		is_collected = true
		_collect_loot()

func _collect_by_proximity() -> void:
	if is_collected: return
	if is_instance_valid(target_player):
		is_collected = true
		_collect_loot()

func _get_ship_from_node(node: Node) -> Node3D:
	if not node: return null
	if node.is_in_group("player"): return node
	
	var p = node.get_parent()
	if p and p.is_in_group("player"): return p
	
	if node is CollisionShape3D or node is Area3D:
		var pp = node.get_parent()
		if pp and pp.is_in_group("player"): return pp
		
	if node.owner and node.owner.is_in_group("player"):
		return node.owner
		
	return null


func _collect_loot() -> void:
	# 획득 효과음 재생 (카메라 거리에 상관없이 잘 들리도록 2D 사운드(null)로 재생)
	var audio_manager = get_node_or_null("/root/AudioManager")
	if is_instance_valid(audio_manager):
		audio_manager.play_sfx("treasure_collect", null, randf_range(1.1, 1.3))
	
	# 보상 지급
	if is_instance_valid(_cached_lm):
		if _cached_lm.has_method("add_score"):
			_cached_lm.add_score(gold_amount)
		if _cached_lm.has_method("add_xp"):
			_cached_lm.add_xp(xp_amount)
			
	# 선체 수리 (supply_bonus 업그레이드 수치 반영)
	if is_instance_valid(target_player) and "hull_hp" in target_player and "max_hull_hp" in target_player:
		var um = get_node_or_null("/root/UpgradeManager")
		var supply_lv = 0
		if is_instance_valid(um) and "current_levels" in um:
			supply_lv = um.current_levels.get("supply_bonus", 0)
			
		var heal_amount = 5.0 + (supply_lv * 10.0) # 기본 5, 레벨당 +10
		target_player.hull_hp = minf(target_player.hull_hp + heal_amount, target_player.max_hull_hp)
		
		# HUD 연동
		if target_player.has_method("_find_hud"):
			var hud = target_player._find_hud()
			if hud and hud.has_method("update_hull_hp"):
				hud.update_hull_hp(target_player.hull_hp, target_player.max_hull_hp)
				
	# 파티클이나 시각적인 먹는 효과 (크기가 줄어들면서 사라짐)
	if visual:
		var tween = create_tween()
		tween.tween_property(visual, "scale", Vector3.ZERO, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tween.tween_callback(queue_free)
	else:
		queue_free()
