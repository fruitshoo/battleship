class_name BaseShip
extends Node3D

## 함선의 공통 기반 클래스 (물리, 시각 효과, 내구도 관리)

# === 이동 관련 ===
@export var max_speed: float = 10.0
@export var acceleration: float = 1.5
@export var deceleration: float = 1.2
@export var turn_rate: float = 50.0

# === 돛 관련 ===
@export var sail_angle: float = 0.0 # 돛 각도 (-90 ~ 90도)

# === 러더(키) 관련 ===
@export var rudder_angle: float = 0.0 # 러더 각도 (-45 ~ 45도)

# === 둥실둥실 효과 ===
@export var bobbing_amplitude: float = 0.3
@export var bobbing_speed: float = 1.0
@export var rocking_amplitude: float = 0.05
var _centrifugal_tilt: float = 0.0 # 원심력에 의한 기울기

# === 내부 상태 ===
var current_speed: float = 0.0
var base_y: float = 0.0

# === 디버프 및 모디파이어 ===
var speed_mult: float = 1.0
var turn_mult: float = 1.0
var tilt_offset: float = 0.0
var stuck_objects: Array[Node3D] = []

# === 선체 내구도 ===
@export var max_hull_hp: float = 200.0 # 스케일 상향 (100 -> 200)
var hull_hp: float = 200.0
@export var hull_regen_rate: float = 0.0
var hull_defense: float = 0.0

var is_sinking: bool = false
var is_dying: bool = false # 터지기 직전 (보스/적선용)
var is_burning: bool = false
var is_derelict: bool = false # 선원 전멸 시 무력화(폐선)
var boarding_attacker: Node3D = null

# === 도선(Boarding) 상태 및 변수 ===
var is_boarding: bool = false
var boarding_timer: float = 0.0
var boarding_interval: float = 1.5
var boarding_prep_timer: float = 0.0
var boarding_prep_duration: float = 2.5
var boarding_target: Node3D = null
var max_boarding_distance: float = 9.0
var boarding_break_distance: float = 12.0
var rope_instances: Array[MeshInstance3D] = []

var fire_build_up: float = 0.0
var fire_threshold: float = 100.0
var burn_timer: float = 0.0

var _last_splinter_time: float = 0.0 # 파편 생성 쿨다운 (최적화)


@export var wood_splinter_scene: PackedScene = preload("res://scenes/effects/wood_splinter.tscn")
@export var fire_effect_scene: PackedScene = preload("res://scenes/effects/fire_effect.tscn")
@export var loot_scene: PackedScene = preload("res://scenes/effects/floating_loot.tscn")
@export var survivor_scene: PackedScene = preload("res://scenes/effects/survivor.tscn")
var _fire_instance: Node3D = null

@export var fire_effect_offset: Vector3 = Vector3(0, 1.5, 0.0)

# === 노드 참조 ===
var masts: Array[Node] = []
@onready var rudder_visual: Node3D = $RudderVisual if has_node("RudderVisual") else null
@onready var wake_trail: GPUParticles3D = $WakeTrail if has_node("WakeTrail") else null

# Oar (노) 레퍼런스
@onready var oar_pivot_left: Node3D = $OarBaseLeft/OarPivot if has_node("OarBaseLeft/OarPivot") else null
@onready var oar_pivot_right: Node3D = $OarBaseRight/OarPivot if has_node("OarBaseRight/OarPivot") else null

var _cached_level_manager: Node = null
var _cached_hud: Node = null
var _cached_ocean: Node3D = null
var _cached_audio_manager: Node = null

func _ready() -> void:
	base_y = position.y
	add_to_group("ships")
	
	for child in get_children():
		if child.name.begins_with("Mast"):
			masts.append(child)
	
	hull_hp = max_hull_hp
	_cache_common_references()

func _cache_common_references() -> void:
	_cached_level_manager = get_tree().root.find_child("LevelManager", true, false)
	if not _cached_level_manager:
		var lms = get_tree().get_nodes_in_group("level_manager")
		if lms.size() > 0: _cached_level_manager = lms[0]
		
	if _cached_level_manager and "hud" in _cached_level_manager:
		_cached_hud = _cached_level_manager.hud
	
	_cached_audio_manager = get_node_or_null("/root/AudioManager")

## 둥실둥실 시각 효과
func _apply_bobbing_effect() -> void:
	var time = Time.get_ticks_msec() * 0.001
	
	if not is_instance_valid(_cached_ocean):
		var oceans = get_tree().get_nodes_in_group("ocean")
		if oceans.size() > 0:
			_cached_ocean = oceans[0]
			
	var wave_h = 0.0
	if is_instance_valid(_cached_ocean) and _cached_ocean.has_method("get_wave_height"):
		# 매 프레임 해당 좌표의 파도 높이를 계산 (안전하고 최적화됨)
		wave_h = _cached_ocean.get_wave_height(global_position)
		
	# 기존 단순 둥실거림은 진폭을 살짝만 남겨 파도 위의 미세한 진동으로 사용
	var bob_offset = sin(time * bobbing_speed) * bobbing_amplitude * 0.2
	
	# 무거운 배의 관성(Inertia)을 모방하기 위해 부드럽게 보간(Lerp)합니다.
	var target_y = base_y + wave_h + bob_offset
	position.y = lerp(position.y, target_y, 3.0 * get_physics_process_delta_time())
	
	var turn_factor = rudder_angle / 45.0
	var speed_ratio = clamp(current_speed / max_speed, 0.0, 1.0)
	var target_centrifugal = deg_to_rad(-turn_factor * speed_ratio * 12.0)
	
	var dt = get_physics_process_delta_time()
	_centrifugal_tilt = lerp(_centrifugal_tilt, target_centrifugal, 2.5 * dt)
	
	rotation.z = (sin(time * bobbing_speed * 0.8) * rocking_amplitude) + tilt_offset + _centrifugal_tilt

## 돛 시각화 업데이트
func _update_sail_visual() -> void:
	for mast in masts:
		if mast.has_method("set_sail_angle"):
			mast.set_sail_angle(sail_angle)

## 러더 시각화 업데이트
func _update_rudder_visual() -> void:
	if rudder_visual:
		rudder_visual.rotation.y = deg_to_rad(rudder_angle)

## 화재 효과 업데이트
func _update_fire_effect() -> void:
	if (is_burning or is_derelict) and not is_sinking and not is_dying:
		if not is_instance_valid(_fire_instance):
			_fire_instance = fire_effect_scene.instantiate() as Node3D
			add_child(_fire_instance)
			_fire_instance.position = fire_effect_offset
			_set_fire_emitting(true)
		else:
			_set_fire_emitting(true)
	else:
		if is_instance_valid(_fire_instance):
			_set_fire_emitting(false)

func _set_fire_emitting(active: bool) -> void:
	if not is_instance_valid(_fire_instance): return
	var flame = _fire_instance.get_node_or_null("FlameParticles") as GPUParticles3D
	var smoke = _fire_instance.get_node_or_null("SmokeParticles") as GPUParticles3D
	if flame: flame.emitting = active
	if smoke: smoke.emitting = active

## 함선 충각(Ramming) 시 갑판 위 병사들에게 광역 데미지 및 넉백 부여
func apply_ramming_aoe(damage: float, impact_pos: Vector3) -> void:
	var soldiers_node = get_node_or_null("Soldiers")
	if not soldiers_node: return
	
	for child in soldiers_node.get_children():
		if child.has_method("take_damage") and child.get("current_state") != 4: # 4 = DEAD
			# 병사들에게 충격파 데미지 전달
			child.take_damage(damage, impact_pos)
			
			# 물리적 비틀거림/스턴 연출을 위해 일시적으로 공격 타이머 초기화 (딜레이 보장)
			if "attack_timer" in child:
				child.attack_timer = max(child.attack_timer, 1.5)
			
			# 약간 띄우는 넉백 효과 추가
			if "velocity" in child:
				child.velocity.y += 2.0
				
	print("[%s] 함선 충돌로 인해 갑판 위 병사들이 %d의 충격 피해를 입었습니다." % [name, int(damage)])
## 데미지 처리 (공통)
func take_damage(amount: float, hit_position: Vector3 = Vector3.ZERO) -> void:
	if is_sinking or is_dying:
		return
		
	var final_damage = maxf(amount - hull_defense, 1.0)
	hull_hp -= final_damage
	
	# 피격 이펙트 (파편) - 스로틀링 적용
	var current_time = Time.get_ticks_msec() / 1000.0
	if wood_splinter_scene and (current_time - _last_splinter_time > 0.2):
		_last_splinter_time = current_time
		var splinter = wood_splinter_scene.instantiate()
		get_tree().root.add_child(splinter)
		if hit_position != Vector3.ZERO:
			splinter.global_position = hit_position + Vector3(0, 0.5, 0)
		else:
			splinter.global_position = global_position + Vector3(randf_range(-1, 1), 1.5, randf_range(-1, 1))
		splinter.rotation.y = randf() * TAU
		if splinter.has_method("set_amount_by_damage"):
			splinter.set_amount_by_damage(final_damage)
			
	_flash_damage(final_damage)
	
	if hull_hp <= 0:
		die()

func _flash_damage(amount: float = 10.0) -> void:
	var shake_mult = clamp(amount / 10.0, 0.15, 2.0)
	var shake_tween = create_tween()
	shake_tween.tween_property(self , "rotation:z", rocking_amplitude * 3.0 * shake_mult, 0.1)
	shake_tween.tween_property(self , "rotation:z", -rocking_amplitude * 2.0 * shake_mult, 0.1)
	shake_tween.tween_property(self , "rotation:z", 0.0, 0.2)

## 화염 데미지
func take_fire_damage(_dps: float, duration: float) -> void:
	if is_burning:
		burn_timer = max(burn_timer, duration)
		return
		
	fire_build_up += duration * 6.0
	if fire_build_up >= fire_threshold:
		is_burning = true
		fire_build_up = fire_threshold
		burn_timer = duration
		print("[Status] 배에 불이 붙었습니다!")

func _update_burning_status(delta: float) -> void:
	if is_burning:
		hull_hp = move_toward(hull_hp, 0, 2.0 * delta)
		if hull_hp <= 0:
			die()
			
		burn_timer -= delta
		if burn_timer <= 0:
			is_burning = false
			fire_build_up = 0.0
	else:
		if fire_build_up > 0:
			fire_build_up = move_toward(fire_build_up, 0, 15.0 * delta)

func _update_hull_regeneration(delta: float) -> void:
	if is_sinking or is_dying or hull_regen_rate <= 0: return
	
	if hull_hp < max_hull_hp:
		hull_hp = move_toward(hull_hp, max_hull_hp, hull_regen_rate * delta)

func get_hull_ratio() -> float:
	if max_hull_hp <= 0.0: return 1.0
	return hull_hp / max_hull_hp

## 가상 함수 분리용 (자식 클래스에서 오버라이드)
func die() -> void:
	pass

# ==========================================
# === 공통 도선(Boarding) 밧줄 처리 로직 ===
# ==========================================

func _spawn_ropes() -> void:
	_clear_ropes()
	var count = randi_range(2, 3)
	for i in range(count):
		var mesh_instance = MeshInstance3D.new()
		var cylinder = CylinderMesh.new()
		cylinder.top_radius = 0.04
		cylinder.bottom_radius = 0.04
		cylinder.height = 1.0 # 기본 길이는 1로 설정 (scale로 조절)
		mesh_instance.mesh = cylinder
		
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.4, 0.3, 0.2)
		mat.roughness = 0.9
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh_instance.material_override = mat
		
		add_child(mesh_instance)
		
		var offset = Vector3(1.0, 0.8, lerp(-2.0, 2.0, float(i) / (count - 1)))
		if is_instance_valid(boarding_target):
			var to_target = (boarding_target.global_position - global_position).normalized()
			var local_to_target = global_transform.basis.inverse() * to_target
			if local_to_target.x < 0: offset.x = -1.0
			
		mesh_instance.position = offset
		mesh_instance.set_meta("anchor_offset", offset)
		rope_instances.append(mesh_instance)

func _update_ropes() -> void:
	if not is_instance_valid(boarding_target):
		_clear_ropes()
		return
		
	var target_center = boarding_target.global_position + Vector3(0, 0.5, 0)
	
	for rope in rope_instances:
		if not is_instance_valid(rope): continue
		
		var offset = rope.get_meta("anchor_offset")
		var start_pos = global_transform * offset
		var dist = start_pos.distance_to(target_center)
		
		var mid_pos = start_pos + (target_center - start_pos) * 0.5
		rope.global_transform = Transform3D().looking_at(target_center - mid_pos, Vector3.UP)
		rope.global_position = mid_pos
		
		rope.rotate_object_local(Vector3.RIGHT, deg_to_rad(-90))
		rope.scale = Vector3(1.0, dist, 1.0)

func _clear_ropes() -> void:
	for rope in rope_instances:
		if is_instance_valid(rope):
			rope.queue_free()
	rope_instances.clear()

func _process_boarding_common(delta: float) -> void:
	if not is_instance_valid(boarding_target):
		_cancel_boarding()
		return
		
	var target_pos = boarding_target.global_position
	var dist = global_position.distance_to(target_pos)
	
	if dist <= max_boarding_distance:
		if boarding_prep_timer < boarding_prep_duration:
			boarding_prep_timer += delta
		else:
			boarding_timer += delta
			if boarding_timer >= boarding_interval:
				boarding_timer = 0.0
				_transfer_one_soldier()
				
	if dist > boarding_break_distance:
		print("[Boarding] 밧줄이 끊어졌습니다. 도선 중단.")
		_cancel_boarding()
		return
		
	_update_ropes()

func _cancel_boarding() -> void:
	if is_instance_valid(boarding_target) and boarding_target.get("boarding_attacker") == self:
		boarding_target.set("boarding_attacker", null)
	_clear_ropes()
	is_boarding = false
	boarding_timer = 0.0
	boarding_prep_timer = 0.0

func _transfer_one_soldier() -> void:
	if not is_instance_valid(boarding_target): return
	
	var target_soldiers_node = boarding_target.get_node_or_null("Soldiers")
	if not target_soldiers_node: target_soldiers_node = boarding_target
	
	var team_prop = get("team") if "team" in self else "enemy"
	
	var s = null
	var enemy_on_deck = false
	
	if has_node("Soldiers"):
		var soldiers = $Soldiers.get_children()
		
		# 1. 방어 판단: 내 배에 침입한 적군이 있는지
		for child in soldiers:
			if child.get("current_state") != 4: # NOT DEAD
				if child.get("team") != team_prop:
					enemy_on_deck = true
					break
					
		if enemy_on_deck:
			return
			
		# 2. 아군 병사 선택
		for child in soldiers:
			if child.get("current_state") != 4 and child.get("team") == team_prop:
				s = child
				break
				
	if s:
		var start_global = s.global_position
		s.call_deferred("reparent", target_soldiers_node)
		
		# 점프 애니메이션 세팅
		var jump_offset = Vector3(randf_range(-1.0, 1.0), 0.5, randf_range(-1.5, 1.5))
		var end_global = boarding_target.global_transform * jump_offset
		
		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(s, "global_position:x", end_global.x, 0.5).set_trans(Tween.TRANS_LINEAR)
		tween.tween_property(s, "global_position:z", end_global.z, 0.5).set_trans(Tween.TRANS_LINEAR)
		
		var mid_y = max(start_global.y, end_global.y) + 2.0
		var y_tween = create_tween()
		y_tween.tween_property(s, "global_position:y", mid_y, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		y_tween.tween_property(s, "global_position:y", end_global.y, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		
		if s.has_method("set_team"):
			s.set_team(team_prop)
			
		s.set("owned_ship", boarding_target)
		
		# 폭발병 로직 (임시)
		if team_prop == "enemy" and boarding_target.get("team") == "player":
			s.set("boarder_explosion_timer", 8.0)
			
		if s.get("is_stationary"): s.set("is_stationary", false)
		
		print("[Action] 병사 1명 월선! (팀: %s, 대상: %s)" % [team_prop, boarding_target.name])
	else:
		if has_method("_become_derelict") and not is_in_group("player"):
			print("[Status] 모든 병사 도선 완료. 무인선 상태로 표류합니다.")
			call("_become_derelict")
		else:
			print("[Status] 도선할 병사가 더 이상 없습니다.")
			_cancel_boarding()
