extends "res://scripts/entities/weapons/weapon.gd"

## 작살 (Harpoon)
## 창 계열 기본 피해/사거리/공격 템포에 높은 치명타 확률 보너스를 가집니다.

const BASE_DAMAGE: float = 8.0

func _ready() -> void:
	damage = BASE_DAMAGE
	attack_range = 2.35
	attack_cooldown = 1.35


func apply_owner_damage_bonus_pct(damage_bonus_pct: float) -> void:
	damage = BASE_DAMAGE * (1.0 + maxf(0.0, damage_bonus_pct))


func attack(target: Node3D, attacker: Node3D) -> void:
	if not is_instance_valid(target): return
	
	var audio_manager = get_node_or_null("/root/AudioManager")
	
	# 데미지 적용 (작살은 기본 치명타 +15%)
	var crit_base = attacker.get_crit_chance_value() if attacker.has_method("get_crit_chance_value") else 0.1
	var crit_chance = crit_base + 0.15
	var crit_multiplier = attacker.get_crit_multiplier_value() if attacker.has_method("get_crit_multiplier_value") else 2.5 # 치명타 데미지 상향
	var hit_pos = target.global_position
	
	var is_crit = randf() < crit_chance
	var final_damage = damage * (crit_multiplier if is_crit else 1.0)
	var crit_effect_position: Variant = snapshot_critical_hit_effect_position(target) if is_crit else null
	var crit_hit_direction: Vector3 = hit_pos - attacker.global_position
	
	if target.has_method("take_damage"):
		target.take_damage(final_damage, attacker.global_position, "harpoon")
		if is_crit and crit_effect_position is Vector3:
			spawn_critical_hit_effect_at_position(crit_effect_position as Vector3, crit_hit_direction)
		if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
			audio_manager.play_sfx("soldier_hit", hit_pos, randf_range(0.95, 1.15), 3.0 if is_crit else 0.0)
			
	# 휘두르는 사운드
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx("sword_swing", attacker.global_position, randf_range(0.9, 1.1))
