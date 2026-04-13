extends "res://scripts/entities/weapons/weapon.gd"

const BASE_DAMAGE: float = 13.0
const OWNER_ATTACK_BONUS_SCALE: float = 0.8

func _ready() -> void:
	damage = BASE_DAMAGE
	attack_range = 2.2
	attack_cooldown = 1.0


func apply_owner_attack_damage(owner_attack_damage: float) -> void:
	var owner_bonus: float = maxf(0.0, owner_attack_damage - 12.0)
	damage = BASE_DAMAGE + (owner_bonus * OWNER_ATTACK_BONUS_SCALE)

func attack(target: Node3D, attacker: Node3D) -> void:
	if not is_instance_valid(target): return
	
	var audio_manager = get_node_or_null("/root/AudioManager")
	
	# 데미지 적용
	var crit_chance = attacker.get_crit_chance_value() if attacker.has_method("get_crit_chance_value") else 0.1
	var crit_multiplier = attacker.get_crit_multiplier_value() if attacker.has_method("get_crit_multiplier_value") else 2.0
	var hit_pos = target.global_position
	
	var is_crit = randf() < crit_chance
	var dmg_mult = attacker.get_damage_multiplier_value() if attacker.has_method("get_damage_multiplier_value") else 1.0
	var final_damage = damage * dmg_mult * (crit_multiplier if is_crit else 1.0)
	
	if target.has_method("take_damage"):
		target.take_damage(final_damage, attacker.global_position, "sword")
		if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
			audio_manager.play_sfx("soldier_hit", hit_pos, randf_range(0.9, 1.1), 3.0 if is_crit else 0.0)
			
	# 검격 사운드
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx("sword_swing", attacker.global_position, randf_range(0.8, 1.2))
