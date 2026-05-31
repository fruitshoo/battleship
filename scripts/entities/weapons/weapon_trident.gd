extends "res://scripts/entities/weapons/weapon.gd"

## 삼지창 (Trident)
## 창과 같은 스펙을 쓰고, 외형과 사운드만 다르게 표현합니다.

const BASE_DAMAGE: float = 10.0

func _ready() -> void:
	damage = BASE_DAMAGE
	attack_range = 2.35
	attack_cooldown = 1.2


func apply_owner_damage_bonus_pct(damage_bonus_pct: float) -> void:
	damage = BASE_DAMAGE * (1.0 + maxf(0.0, damage_bonus_pct))


func apply_owner_damage_modifiers(damage_bonus_pct: float, damage_add: float = 0.0) -> void:
	damage = (BASE_DAMAGE + maxf(0.0, damage_add)) * (1.0 + maxf(0.0, damage_bonus_pct))


func attack(target: Node3D, attacker: Node3D) -> void:
	if not is_instance_valid(target): return
	
	var audio_manager = get_node_or_null("/root/AudioManager")
	
	# 데미지 적용
	var crit_chance = attacker.get_crit_chance_value() if attacker.has_method("get_crit_chance_value") else 0.1
	var crit_multiplier = attacker.get_crit_multiplier_value() if attacker.has_method("get_crit_multiplier_value") else 2.0
	var hit_pos = target.global_position
	
	var is_crit = randf() < crit_chance
	var final_damage = damage * (crit_multiplier if is_crit else 1.0)
	var crit_effect_position: Variant = snapshot_critical_hit_effect_position(target) if is_crit else null
	var crit_hit_direction: Vector3 = hit_pos - attacker.global_position
	
	if target.has_method("take_damage"):
		target.take_damage(final_damage, attacker.global_position, "trident")
		if is_crit and crit_effect_position is Vector3:
			spawn_critical_hit_effect_at_position(crit_effect_position as Vector3, crit_hit_direction)
		if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
			audio_manager.play_sfx("soldier_hit", hit_pos, randf_range(0.75, 0.95), 3.0 if is_crit else 0.0)
			
	# 묵직한 공격 사운드
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx("sword_swing", attacker.global_position, randf_range(0.6, 0.8)) # 낮은 피치로 묵직함 표현
