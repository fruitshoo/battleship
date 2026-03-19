extends RefCounted

const ScenePool = preload("res://scripts/helpers/scene_pool.gd")
const SceneGroupCache = preload("res://scripts/helpers/scene_group_cache.gd")
const IMPACT_PUFF_SCENE = preload("res://scenes/effects/impact_puff.tscn")


static func perform_special_attack(soldier, target: Node3D) -> void:
	if not is_instance_valid(target):
		return

	if is_instance_valid(soldier.owned_ship) and target == soldier.owned_ship.get("boarding_attacker"):
		if soldier.team == "player":
			if soldier.owned_ship.has_method("take_rope_damage"):
				soldier.owned_ship.take_rope_damage(soldier.attack_damage * 1.5)
				play_rope_hit_effects(soldier)
				return

	perform_attack(soldier)


static func play_rope_hit_effects(soldier) -> void:
	var audio_manager = soldier.get_node_or_null("/root/AudioManager")
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx("impact_wood", soldier.global_position, randf_range(1.1, 1.3))

	var effect = ScenePool.acquire(soldier.get_tree(), IMPACT_PUFF_SCENE)
	if effect.has_method("configure_as_hit"):
		effect.configure_as_hit()
	soldier.get_tree().root.add_child(effect)
	effect.global_position = soldier.global_position + (soldier.global_transform.basis.z * -1.0)
	if effect.has_method("pool_activate"):
		effect.pool_activate()


static func perform_attack(soldier) -> void:
	if not is_instance_valid(soldier.current_target):
		return

	if soldier.current_weapon and soldier.current_weapon.has_method("attack"):
		soldier.current_weapon.attack(soldier.current_target, soldier)

	var mesh_instance = soldier.get_node_or_null("MeshInstance3D")
	if mesh_instance:
		var tween = soldier.create_tween()
		tween.tween_property(mesh_instance, "position:z", -0.5, 0.1).as_relative()
		tween.tween_property(mesh_instance, "position:z", 0.5, 0.1).as_relative()

	var hand_pivot = soldier.get_node_or_null("HandPivot")
	if hand_pivot:
		var w_tween = soldier.create_tween()
		w_tween.set_parallel(true)
		if soldier.current_weapon and not "max_range" in soldier.current_weapon:
			w_tween.tween_property(hand_pivot, "rotation:x", -deg_to_rad(60), 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			w_tween.tween_property(hand_pivot, "scale", Vector3(1.2, 1.2, 1.2), 0.1)
			w_tween.chain().set_parallel(true)
			w_tween.tween_property(hand_pivot, "rotation:x", 0.0, 0.2)
			w_tween.tween_property(hand_pivot, "scale", Vector3.ONE, 0.2)
		else:
			w_tween.tween_property(hand_pivot, "position:z", 0.2, 0.1).as_relative()
			w_tween.chain().tween_property(hand_pivot, "position:z", -0.2, 0.2).as_relative()


static func check_ranged_combat(soldier) -> void:
	if not soldier.current_weapon or not "max_range" in soldier.current_weapon:
		return

	var attack_cooldown = soldier.current_weapon.attack_cooldown if "attack_cooldown" in soldier.current_weapon else 2.0
	if soldier.attack_timer > 0:
		return

	var target = find_ranged_target(soldier)
	if target:
		soldier.current_target = target
		perform_attack(soldier)
		soldier.attack_timer = attack_cooldown


static func find_ranged_target(soldier) -> Node3D:
	var max_range = soldier.current_weapon.attack_range if soldier.current_weapon and "attack_range" in soldier.current_weapon else 20.0

	var nearest = soldier.find_nearest_enemy()
	if is_instance_valid(nearest):
		var dist_xz = Vector2(soldier.global_position.x - nearest.global_position.x, soldier.global_position.z - nearest.global_position.z).length()
		if dist_xz <= max_range:
			return nearest

	return null
