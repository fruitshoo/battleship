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
@export var max_hull_hp: float = 100.0
var hull_hp: float = 100.0
@export var hull_regen_rate: float = 0.0
var hull_defense: float = 0.0

var is_sinking: bool = false
var is_dying: bool = false # 터지기 직전 (보스/적선용)
var is_burning: bool = false
var is_derelict: bool = false # 선원 전멸 시 무력화(폐선)
var boarding_attacker: Node3D = null

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
var _oar_time: float = 0.0

var _cached_level_manager: Node = null
var _cached_hud: Node = null

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

## 둥실둥실 시각 효과
func _apply_bobbing_effect() -> void:
	var time = Time.get_ticks_msec() * 0.001
	var bob_offset = sin(time * bobbing_speed) * bobbing_amplitude
	
	position.y = base_y + bob_offset
	
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
