extends "res://scripts/entities/weapons/weapon.gd"

func _ready() -> void:
	damage = 10.0
	attack_range = 1.2
	attack_cooldown = 1.0

func attack(target: Node3D, attacker: Node3D) -> void:
	if not is_instance_valid(target): return
	
	# 데미지 적용
	var crit_chance = attacker.get("crit_chance") if "crit_chance" in attacker else 0.1
	var crit_multiplier = attacker.get("crit_multiplier") if "crit_multiplier" in attacker else 2.0
	var hit_pos = target.global_position
	
	var is_crit = randf() < crit_chance
	var final_damage = damage * (crit_multiplier if is_crit else 1.0)
	
	if target.has_method("take_damage"):
		target.take_damage(final_damage, attacker.global_position)
		if is_crit and is_instance_valid(AudioManager):
			AudioManager.play_sfx("critical_hit", hit_pos, randf_range(0.9, 1.1))
			
	# 검격 사운드
	if is_instance_valid(AudioManager):
		AudioManager.play_sfx("sword_swing", attacker.global_position, randf_range(0.8, 1.2))
