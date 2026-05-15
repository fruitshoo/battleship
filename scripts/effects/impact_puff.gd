extends GPUParticles3D


var _budget_key_value: String = "hit_effect"
var _budget_limit_value: int = 8
var _budget_distance_value: float = 55.0
var _life_left: float = 0.0
var _active: bool = false
var _budget_reserved: bool = false

func _ready() -> void:
	pool_reset()
	if _is_prewarm_mode():
		return

func set_intensity(scale: float) -> void:
	pass

func set_budget_reserved(reserved: bool = true) -> void:
	_budget_reserved = reserved

func pool_capacity() -> int:
	return 18

func pool_activate() -> void:
	if not _budget_reserved and not VfxBudget.allow_spawn(get_tree(), _budget_key_value, global_position, _budget_limit_value, _budget_distance_value):
		ScenePool.release(self)
		return
	_budget_reserved = false
	_active = true
	visible = true
	set_process(true)
	restart()
	emitting = true
	_life_left = lifetime + 0.3

func pool_reset() -> void:
	_active = false
	_life_left = 0.0
	_budget_reserved = false
	set_process(false)
	visible = false
	emitting = false

func _process(delta: float) -> void:
	if not _active:
		return
	_life_left -= delta
	if _life_left <= 0.0:
		ScenePool.release(self)

func _is_prewarm_mode() -> bool:
	var n: Node = self
	while is_instance_valid(n):
		if n.has_meta("prewarm_mode") and n.get_meta("prewarm_mode") == true:
			return true
		n = n.get_parent()
	return false
