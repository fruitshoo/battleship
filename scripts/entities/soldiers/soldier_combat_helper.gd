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

	_play_attack_animation(soldier)


static func _play_attack_animation(soldier) -> void:
	var hand_pivot := soldier.get_node_or_null("HandPivot") as Node3D
	var weapon := soldier.current_weapon as Node3D
	var weapon_visual := _get_weapon_visual_node(weapon)
	_cache_attack_rest_transforms(hand_pivot, weapon_visual)
	_reset_attack_pose(hand_pivot, weapon_visual)

	var mesh_instance = soldier.get_node_or_null("MeshInstance3D")
	if mesh_instance:
		var tween = soldier.create_tween()
		tween.tween_property(mesh_instance, "position:z", -0.5, 0.1).as_relative()
		tween.tween_property(mesh_instance, "position:z", 0.5, 0.1).as_relative()

	if not is_instance_valid(hand_pivot):
		return

	var weapon_id := ""
	if is_instance_valid(weapon):
		weapon_id = str(weapon.get_meta("weapon_id", ""))

	if weapon_id == "spearman" or weapon_id == "spear" or weapon_id == "trident":
		_play_thrust_attack_animation(soldier, hand_pivot, weapon_visual)
	elif weapon_id == "sword" or weapon_id == "harpoon":
		_play_swing_attack_animation(soldier, hand_pivot, weapon_visual)
	elif soldier.current_weapon and not "max_range" in soldier.current_weapon:
		_play_swing_attack_animation(soldier, hand_pivot, weapon_visual)
	else:
		_play_ranged_attack_animation(soldier, hand_pivot)


static func _play_swing_attack_animation(soldier, hand_pivot: Node3D, weapon_visual: Node3D = null) -> void:
	var rest_rotation: Vector3 = hand_pivot.get_meta("_attack_rest_rotation", hand_pivot.rotation)
	var rest_scale: Vector3 = hand_pivot.get_meta("_attack_rest_scale", hand_pivot.scale)
	var swing_tween = soldier.create_tween()
	swing_tween.set_parallel(true)
	swing_tween.tween_property(hand_pivot, "rotation", rest_rotation + Vector3(deg_to_rad(-28.0), 0.0, deg_to_rad(58.0)), 0.09).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	swing_tween.tween_property(hand_pivot, "scale", rest_scale * 1.08, 0.09)
	if is_instance_valid(weapon_visual):
		var visual_rest_rot: Vector3 = weapon_visual.get_meta("_attack_rest_rotation", weapon_visual.rotation)
		swing_tween.tween_property(weapon_visual, "rotation", visual_rest_rot + Vector3(0.0, 0.0, deg_to_rad(22.0)), 0.09).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	swing_tween.chain().set_parallel(true)
	swing_tween.tween_property(hand_pivot, "rotation", rest_rotation + Vector3(deg_to_rad(8.0), 0.0, deg_to_rad(-34.0)), 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	swing_tween.tween_property(hand_pivot, "scale", rest_scale, 0.12)
	if is_instance_valid(weapon_visual):
		var visual_rest_rot_2: Vector3 = weapon_visual.get_meta("_attack_rest_rotation", weapon_visual.rotation)
		swing_tween.tween_property(weapon_visual, "rotation", visual_rest_rot_2 + Vector3(0.0, 0.0, deg_to_rad(-16.0)), 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	swing_tween.chain().set_parallel(true)
	swing_tween.tween_property(hand_pivot, "rotation", rest_rotation, 0.10).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if is_instance_valid(weapon_visual):
		swing_tween.tween_property(weapon_visual, "rotation", weapon_visual.get_meta("_attack_rest_rotation", weapon_visual.rotation), 0.10).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


static func _play_thrust_attack_animation(soldier, hand_pivot: Node3D, weapon_visual: Node3D = null) -> void:
	var rest_position: Vector3 = hand_pivot.get_meta("_attack_rest_position", hand_pivot.position)
	var rest_rotation: Vector3 = hand_pivot.get_meta("_attack_rest_rotation", hand_pivot.rotation)
	var thrust_tween = soldier.create_tween()
	thrust_tween.set_parallel(true)
	thrust_tween.tween_property(hand_pivot, "position", rest_position + Vector3(0.0, 0.03, -0.38), 0.07).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	thrust_tween.tween_property(hand_pivot, "rotation", rest_rotation + Vector3(deg_to_rad(-18.0), 0.0, deg_to_rad(6.0)), 0.07).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if is_instance_valid(weapon_visual):
		var visual_rest_pos: Vector3 = weapon_visual.get_meta("_attack_rest_position", weapon_visual.position)
		thrust_tween.tween_property(weapon_visual, "position", visual_rest_pos + Vector3(0.0, 0.18, -0.05), 0.07).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	thrust_tween.chain().set_parallel(true)
	thrust_tween.tween_property(hand_pivot, "position", rest_position, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	thrust_tween.tween_property(hand_pivot, "rotation", rest_rotation, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if is_instance_valid(weapon_visual):
		thrust_tween.tween_property(weapon_visual, "position", weapon_visual.get_meta("_attack_rest_position", weapon_visual.position), 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


static func _play_ranged_attack_animation(soldier, hand_pivot: Node3D) -> void:
	var rest_position: Vector3 = hand_pivot.get_meta("_attack_rest_position", hand_pivot.position)
	var rest_rotation: Vector3 = hand_pivot.get_meta("_attack_rest_rotation", hand_pivot.rotation)
	var ranged_tween = soldier.create_tween()
	ranged_tween.set_parallel(true)
	ranged_tween.tween_property(hand_pivot, "position", rest_position + Vector3(0.0, 0.0, 0.18), 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	ranged_tween.tween_property(hand_pivot, "rotation", rest_rotation + Vector3(deg_to_rad(-10.0), 0.0, 0.0), 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	ranged_tween.chain().set_parallel(true)
	ranged_tween.tween_property(hand_pivot, "position", rest_position, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	ranged_tween.tween_property(hand_pivot, "rotation", rest_rotation, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


static func _get_weapon_visual_node(weapon: Node3D) -> Node3D:
	if not is_instance_valid(weapon):
		return null
	if weapon.has_node("Visual"):
		return weapon.get_node("Visual") as Node3D
	return weapon


static func _cache_attack_rest_transforms(hand_pivot: Node3D, weapon_visual: Node3D) -> void:
	if is_instance_valid(hand_pivot) and not hand_pivot.has_meta("_attack_rest_position"):
		hand_pivot.set_meta("_attack_rest_position", hand_pivot.position)
		hand_pivot.set_meta("_attack_rest_rotation", hand_pivot.rotation)
		hand_pivot.set_meta("_attack_rest_scale", hand_pivot.scale)
	if is_instance_valid(weapon_visual) and not weapon_visual.has_meta("_attack_rest_position"):
		weapon_visual.set_meta("_attack_rest_position", weapon_visual.position)
		weapon_visual.set_meta("_attack_rest_rotation", weapon_visual.rotation)
		weapon_visual.set_meta("_attack_rest_scale", weapon_visual.scale)


static func _reset_attack_pose(hand_pivot: Node3D, weapon_visual: Node3D) -> void:
	if is_instance_valid(hand_pivot) and hand_pivot.has_meta("_attack_rest_position"):
		hand_pivot.position = hand_pivot.get_meta("_attack_rest_position", hand_pivot.position)
		hand_pivot.rotation = hand_pivot.get_meta("_attack_rest_rotation", hand_pivot.rotation)
		hand_pivot.scale = hand_pivot.get_meta("_attack_rest_scale", hand_pivot.scale)
	if is_instance_valid(weapon_visual) and weapon_visual.has_meta("_attack_rest_position"):
		weapon_visual.position = weapon_visual.get_meta("_attack_rest_position", weapon_visual.position)
		weapon_visual.rotation = weapon_visual.get_meta("_attack_rest_rotation", weapon_visual.rotation)
		weapon_visual.scale = weapon_visual.get_meta("_attack_rest_scale", weapon_visual.scale)


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
