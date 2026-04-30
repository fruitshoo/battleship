extends Node3D
class_name SoldierWeapon

## 병사가 사용하는 무기의 베이스 클래스

const NODE_VISUAL := "Visual"
const SOLDIER_CRIT_HIT_SCENE: PackedScene = preload("res://scenes/effects/soldier_crit_hit.tscn")
const SOLDIER_CRIT_HIT_HEIGHT: float = 1.05

@export var damage: float = 10.0
@export var attack_range: float = 1.2
@export var attack_cooldown: float = 1.0

# 병사가 공격할 때 호출하는 함수 (자식에서 오버라이드 됨)
func attack(_target: Node3D, _attacker: Node3D) -> void:
	pass


func get_weapon_visual_node() -> Node3D:
	var visual := get_node_or_null(NODE_VISUAL)
	return visual as Node3D if visual is Node3D else null


func get_weapon_visual_root() -> Node3D:
	var visual := get_weapon_visual_node()
	return visual if visual != null else self


# 씬에 있는 무기 메쉬의 가시성을 설정하는 헬퍼
func set_visual_visible(make_visible: bool) -> void:
	var visual := get_weapon_visual_node()
	if visual != null:
		visual.visible = make_visible


func spawn_critical_hit_effect(target: Node3D, attacker: Node3D = null) -> void:
	if not is_instance_valid(target) or not is_inside_tree():
		return
	var effect := ScenePool.acquire(get_tree(), SOLDIER_CRIT_HIT_SCENE) as Node3D
	if not is_instance_valid(effect):
		return
	get_tree().root.add_child(effect)
	effect.global_position = target.global_position + Vector3(0.0, SOLDIER_CRIT_HIT_HEIGHT, 0.0)
	if is_instance_valid(attacker):
		var hit_dir := target.global_position - attacker.global_position
		hit_dir.y = 0.0
		if hit_dir.length_squared() > 0.001:
			effect.global_basis = Basis.looking_at(hit_dir.normalized(), Vector3.UP)
	if effect.has_method("pool_activate"):
		effect.pool_activate()
