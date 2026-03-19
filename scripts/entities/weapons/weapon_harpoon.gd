extends "res://scripts/entities/weapons/weapon.gd"

## 작살 (Harpoon)
## 평균적인 능력치에 높은 치명타 확률 보너스를 가집니다.

func _ready() -> void:
	damage = 14.0
	attack_range = 2.8
	attack_cooldown = 1.1

func attack(target: Node3D, attacker: Node3D) -> void:
	if not is_instance_valid(target): return
	
	var audio_manager = get_node_or_null("/root/AudioManager")
	
	# 데미지 적용 (작살은 기본 치명타 +15%)
	var crit_base = attacker.get("crit_chance") if "crit_chance" in attacker else 0.1
	var crit_chance = crit_base + 0.15
	var crit_multiplier = attacker.get("crit_multiplier") if "crit_multiplier" in attacker else 2.5 # 치명타 데미지 상향
	var hit_pos = target.global_position
	
	var is_crit = randf() < crit_chance
	var final_damage = damage * (crit_multiplier if is_crit else 1.0)
	
	if target.has_method("take_damage"):
		target.take_damage(final_damage, attacker.global_position, "harpoon")
		if is_crit and is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
			audio_manager.play_sfx("critical_hit", hit_pos, randf_range(1.1, 1.3))
			
	# 휘두르는 사운드
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx("sword_swing", attacker.global_position, randf_range(0.9, 1.1))
