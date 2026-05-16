extends Node3D
class_name SoldierWeapon

## 병사가 사용하는 무기의 베이스 클래스

const NODE_VISUAL := "Visual"
const SOLDIER_CRIT_HIT_SCENE: PackedScene = preload("res://scenes/effects/soldier_crit_hit.tscn")
const VfxSpawnHelper = preload("res://scripts/helpers/vfx_spawn_helper.gd")
const SOLDIER_CRIT_HIT_HEIGHT: float = 1.05
const CRIT_EFFECT_DECK_MARGIN := 0.75

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
	var effect_position_variant: Variant = snapshot_critical_hit_effect_position(target)
	if not effect_position_variant is Vector3:
		return
	var effect_position := effect_position_variant as Vector3
	var hit_dir := Vector3.ZERO
	if is_instance_valid(attacker):
		hit_dir = target.global_position - attacker.global_position
	spawn_critical_hit_effect_at_position(effect_position, hit_dir)


func snapshot_critical_hit_effect_position(target: Node3D) -> Variant:
	return _get_valid_critical_effect_position(target)


func spawn_critical_hit_effect_at_position(effect_position: Vector3, hit_direction: Vector3 = Vector3.ZERO) -> void:
	if not is_inside_tree() or not effect_position.is_finite():
		return
	var effect := VfxSpawnHelper.acquire_world_node3d(get_tree(), SOLDIER_CRIT_HIT_SCENE, effect_position)
	if not is_instance_valid(effect):
		return
	VfxSpawnHelper.orient_world_node3d(effect, effect_position, hit_direction)
	VfxSpawnHelper.activate(effect)


func _get_valid_critical_effect_position(target: Node3D) -> Variant:
	if not is_instance_valid(target) or not target.is_inside_tree():
		return null
	var target_pos := target.global_position
	if not target_pos.is_finite():
		return null
	var owned_ship: Node3D = target.get_owned_ship_node() if target.has_method("get_owned_ship_node") else null
	if not is_instance_valid(owned_ship) or not owned_ship.is_inside_tree():
		return null
	if owned_ship.get("is_sinking") == true or owned_ship.get("is_dying") == true:
		return null
	if owned_ship.has_method("is_sinking_or_dying") and owned_ship.call("is_sinking_or_dying") == true:
		return null
	var local_pos := owned_ship.to_local(target_pos)
	var deck_height: float = float(owned_ship.get("deck_height")) if owned_ship.get("deck_height") != null else 0.4
	if local_pos.y < deck_height - 1.0 or local_pos.y > deck_height + 1.75:
		return null
	var half_ext := Vector2(2.0, 3.0)
	if owned_ship.has_method("get_deck_half_extents"):
		var extents: Variant = owned_ship.call("get_deck_half_extents")
		if extents is Vector2:
			half_ext = extents
	var half_width := half_ext.x
	if owned_ship.has_method("get_deck_half_width_at_z"):
		half_width = maxf(0.08, float(owned_ship.call("get_deck_half_width_at_z", clampf(local_pos.z, -half_ext.y, half_ext.y))))
	if absf(local_pos.z) > half_ext.y + CRIT_EFFECT_DECK_MARGIN or absf(local_pos.x) > half_width + CRIT_EFFECT_DECK_MARGIN:
		return null
	return target_pos + Vector3(0.0, SOLDIER_CRIT_HIT_HEIGHT, 0.0)
