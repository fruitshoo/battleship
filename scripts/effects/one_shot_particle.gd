extends GPUParticles3D

## 원샷 파티클 — 재생 즉시 emit을 시작하고, 수명이 다하면 자동으로 노드를 제거합니다.
## muzzle_smoke, hit_effect, slash_effect, rocket_explosion 등 일회성 GPUParticles3D에 공용으로 사용합니다.

var _active: bool = false
var _activate_when_ready: bool = false
var _life_left: float = 0.0

@export var sfx_name: String = ""
@export_range(0.5, 1.5, 0.01) var sfx_pitch_min: float = 0.94
@export_range(0.5, 1.5, 0.01) var sfx_pitch_max: float = 1.06
@export_range(-24.0, 12.0, 0.5, "suffix:dB") var sfx_volume_db: float = 0.0


func _enter_tree() -> void:
	if _activate_when_ready and is_node_ready():
		_activate_when_ready = false
		call_deferred("pool_activate")


func _ready() -> void:
	var should_activate_when_ready := _activate_when_ready
	pool_reset()
	if _is_prewarm_mode():
		return

	if should_activate_when_ready:
		call_deferred("pool_activate")
	elif not has_meta(ScenePool.KEY_META):
		call_deferred("pool_activate")


func pool_capacity() -> int:
	return 12


func pool_activate() -> void:
	if not is_inside_tree():
		_activate_when_ready = true
		return

	if not VfxBudget.allow_spawn(get_tree(), _budget_key(), global_position, _budget_limit(), _budget_distance()):
		ScenePool.release(self)
		return

	_active = true
	_life_left = lifetime + 0.3
	visible = true
	set_process(true)
	_play_activation_sfx()
	restart()
	emitting = true
	# 자식 파티클도 함께 emit
	var max_life = lifetime
	for child in get_children():
		if child is GPUParticles3D:
			var particles := child as GPUParticles3D
			particles.visible = true
			particles.restart()
			particles.emitting = true
			max_life = max(max_life, particles.lifetime)
	_life_left = max_life + 0.3


func pool_reset() -> void:
	_active = false
	_activate_when_ready = false
	_life_left = 0.0
	set_process(false)
	emitting = false
	visible = false
	for child in get_children():
		if child is GPUParticles3D:
			var particles := child as GPUParticles3D
			particles.emitting = false
			particles.visible = false


func _process(delta: float) -> void:
	if not _active:
		return
	_life_left -= delta
	if _life_left <= 0.0:
		ScenePool.release(self)


func _play_activation_sfx() -> void:
	if sfx_name.strip_edges().is_empty():
		return
	var audio_manager := get_node_or_null("/root/AudioManager")
	if not is_instance_valid(audio_manager) or not audio_manager.has_method("play_sfx_random_pitch"):
		return
	audio_manager.play_sfx_random_pitch(
		sfx_name,
		global_position,
		sfx_pitch_min,
		sfx_pitch_max,
		sfx_volume_db
	)

func _is_prewarm_mode() -> bool:
	var n: Node = self
	while is_instance_valid(n):
		if n.has_meta("prewarm_mode") and n.get_meta("prewarm_mode") == true:
			return true
		n = n.get_parent()
	return false

func _budget_key() -> String:
	match name:
		"WaterExplosion":
			return "water_explosion"
		"MuzzleSmoke":
			return "muzzle_smoke"
		"HitEffect":
			return "hit_effect"
		"BloodMist":
			return "blood_mist"
		"RocketExplosion":
			return "rocket_explosion"
		"FirePotExplosion":
			return "fire_pot_explosion"
	return name.to_snake_case()

func _budget_limit() -> int:
	match name:
		"WaterExplosion":
			return 4
		"MuzzleSmoke":
			return 5
		"HitEffect":
			return 8
		"BloodMist":
			return 5
		"RocketExplosion":
			return 5
		"FirePotExplosion":
			return 3
	return 6

func _budget_distance() -> float:
	match name:
		"WaterExplosion":
			return 70.0
		"MuzzleSmoke":
			return 65.0
		"HitEffect":
			return 55.0
		"BloodMist":
			return 45.0
		"RocketExplosion":
			return 90.0
		"FirePotExplosion":
			return 65.0
	return 60.0
