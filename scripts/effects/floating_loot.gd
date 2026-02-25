extends Area3D

## 부유물(Floating Loot) 시스템
## 적을 물리쳤을 때 바다에 스폰되며, 플레이어가 다가가면 자석처럼 끌려와 획득됨

@export var gold_amount: int = 30
@export var xp_amount: int = 15
@export var magnet_radius: float = 15.0 # 자석 효과 범위
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
	base_y = position.y
	
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
	
	# 레벨 매니저 캐싱
	_cached_lm = get_tree().root.find_child("LevelManager", true, false)
	if not _cached_lm:
		var lm_nodes = get_tree().get_nodes_in_group("level_manager")
		if lm_nodes.size() > 0: _cached_lm = lm_nodes[0]
	
	# 획득 이벤트 연결
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	if is_collected: return
	time_alive += delta
	
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
		else:
			# 범위를 벗어나면 가속도 초기화 및 제자리 둥실거림
			current_magnet_speed = 0.0
			_apply_floating(delta)
	else:
		_apply_floating(delta)


func _apply_floating(delta: float) -> void:
	# 물 위에서 둥실거리고 회전함
	position.y = base_y + sin(time_alive * float_speed) * float_height
	if visual:
		visual.rotation.y += rotation_speed * delta
		visual.rotation.z = sin(time_alive * float_speed * 1.5) * 0.1 # 살짝 갸우뚱


func _find_target_player() -> void:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		target_player = players[0]


func _on_body_entered(body: Node3D) -> void:
	if is_collected: return
	
	# body 자체가 player거나, 부모/주인이 player 그룹인지 확인 (CharacterBody3D 등 자식 노드 감지 대응)
	var is_player = false
	if body.is_in_group("player"):
		is_player = true
	elif body.owner and body.owner.is_in_group("player"):
		is_player = true
	elif body.get_parent() and body.get_parent().is_in_group("player"):
		is_player = true
		
	if is_player:
		is_collected = true
		_collect_loot()


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
			
	# 파티클이나 시각적인 먹는 효과 (크기가 줄어들면서 사라짐)
	if visual:
		var tween = create_tween()
		tween.tween_property(visual, "scale", Vector3.ZERO, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tween.tween_callback(queue_free)
	else:
		queue_free()
