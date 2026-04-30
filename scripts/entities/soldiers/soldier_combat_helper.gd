extends RefCounted

const SoldierVisualHelper = preload("res://scripts/entities/soldiers/soldier_visual_helper.gd")

const ATTACK_COOLDOWN_TEMPO_MULT := 1.12


static func perform_special_attack(soldier, target: Node3D) -> void:
	if not is_instance_valid(target):
		return

	perform_attack(soldier)


static func perform_attack(soldier) -> void:
	if not is_instance_valid(soldier.current_target):
		return
	if SoldierStateHelper.is_dead_soldier(soldier.current_target):
		soldier.current_target = null
		return

	if soldier.current_weapon and soldier.current_weapon.has_method("attack"):
		soldier.current_weapon.attack(soldier.current_target, soldier)

	_play_attack_animation(soldier)


static func get_effective_attack_cooldown(soldier, fallback_cooldown: float = 1.0) -> float:
	var base_cooldown := fallback_cooldown
	if is_instance_valid(soldier) and is_instance_valid(soldier.current_weapon) and "attack_cooldown" in soldier.current_weapon:
		base_cooldown = float(soldier.current_weapon.attack_cooldown)
	return base_cooldown * ATTACK_COOLDOWN_TEMPO_MULT


static func _play_attack_animation(soldier) -> void:
	var hand_pivot := _get_hand_pivot(soldier)
	var weapon := soldier.current_weapon as Node3D
	var weapon_visual := _get_weapon_visual_node(weapon)
	_cache_attack_rest_transforms(hand_pivot, weapon_visual)

	var pose_node := SoldierVisualHelper.get_pose_node(soldier)
	if pose_node:
		_stop_tracked_tween(soldier, "_attack_body_tween")
		if not pose_node.has_meta("_attack_rest_position"):
			pose_node.set_meta("_attack_rest_position", pose_node.position)
		var mesh_rest_position: Vector3 = pose_node.get_meta("_attack_rest_position", pose_node.position)
		var body_tween: Tween = soldier.create_tween()
		soldier.set_meta("_attack_body_tween", body_tween)
		body_tween.tween_property(pose_node, "position", mesh_rest_position + Vector3(0.0, 0.0, -0.28), 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		body_tween.tween_property(pose_node, "position", mesh_rest_position, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	if not is_instance_valid(hand_pivot):
		return

	_stop_tracked_tween(soldier, "_attack_pose_tween")

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
	var swing_tween: Tween = soldier.create_tween()
	soldier.set_meta("_attack_pose_tween", swing_tween)
	swing_tween.set_parallel(true)
	swing_tween.tween_property(hand_pivot, "rotation", rest_rotation + Vector3(deg_to_rad(-18.0), 0.0, deg_to_rad(24.0)), 0.07).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	swing_tween.tween_property(hand_pivot, "scale", rest_scale * 1.04, 0.07).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if is_instance_valid(weapon_visual):
		var visual_rest_rot: Vector3 = weapon_visual.get_meta("_attack_rest_rotation", weapon_visual.rotation)
		swing_tween.tween_property(weapon_visual, "rotation", visual_rest_rot + Vector3(0.0, 0.0, deg_to_rad(12.0)), 0.07).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	swing_tween.chain().set_parallel(true)
	swing_tween.tween_property(hand_pivot, "rotation", rest_rotation + Vector3(deg_to_rad(6.0), 0.0, deg_to_rad(-26.0)), 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	swing_tween.tween_property(hand_pivot, "scale", rest_scale, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if is_instance_valid(weapon_visual):
		var visual_rest_rot_2: Vector3 = weapon_visual.get_meta("_attack_rest_rotation", weapon_visual.rotation)
		swing_tween.tween_property(weapon_visual, "rotation", visual_rest_rot_2 + Vector3(0.0, 0.0, deg_to_rad(-12.0)), 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	swing_tween.chain().set_parallel(true)
	swing_tween.tween_property(hand_pivot, "rotation", rest_rotation, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if is_instance_valid(weapon_visual):
		swing_tween.tween_property(weapon_visual, "rotation", weapon_visual.get_meta("_attack_rest_rotation", weapon_visual.rotation), 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


static func _play_thrust_attack_animation(soldier, hand_pivot: Node3D, weapon_visual: Node3D = null) -> void:
	var rest_position: Vector3 = hand_pivot.get_meta("_attack_rest_position", hand_pivot.position)
	var rest_rotation: Vector3 = hand_pivot.get_meta("_attack_rest_rotation", hand_pivot.rotation)
	var thrust_tween: Tween = soldier.create_tween()
	soldier.set_meta("_attack_pose_tween", thrust_tween)
	var visual_rest_pos: Vector3 = weapon_visual.get_meta("_attack_rest_position", weapon_visual.position) if is_instance_valid(weapon_visual) else Vector3.ZERO
	thrust_tween.set_parallel(true)
	thrust_tween.tween_property(hand_pivot, "position", rest_position + Vector3(0.0, 0.02, -0.18), 0.06).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	thrust_tween.tween_property(hand_pivot, "rotation", rest_rotation + Vector3(deg_to_rad(-8.0), 0.0, deg_to_rad(2.0)), 0.06).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if is_instance_valid(weapon_visual):
		thrust_tween.tween_property(weapon_visual, "position", visual_rest_pos + Vector3(0.0, 0.06, -0.18), 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	thrust_tween.chain().set_parallel(true)
	thrust_tween.tween_property(hand_pivot, "position", rest_position + Vector3(0.0, 0.01, -0.36), 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	thrust_tween.tween_property(hand_pivot, "rotation", rest_rotation + Vector3(deg_to_rad(-14.0), 0.0, deg_to_rad(4.0)), 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if is_instance_valid(weapon_visual):
		thrust_tween.tween_property(weapon_visual, "position", visual_rest_pos + Vector3(0.0, 0.12, -0.32), 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	thrust_tween.chain().set_parallel(true)
	thrust_tween.tween_property(hand_pivot, "position", rest_position, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	thrust_tween.tween_property(hand_pivot, "rotation", rest_rotation, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if is_instance_valid(weapon_visual):
		thrust_tween.tween_property(weapon_visual, "position", weapon_visual.get_meta("_attack_rest_position", weapon_visual.position), 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


static func _play_ranged_attack_animation(soldier, hand_pivot: Node3D) -> void:
	var rest_position: Vector3 = hand_pivot.get_meta("_attack_rest_position", hand_pivot.position)
	var rest_rotation: Vector3 = hand_pivot.get_meta("_attack_rest_rotation", hand_pivot.rotation)
	var ranged_tween: Tween = soldier.create_tween()
	soldier.set_meta("_attack_pose_tween", ranged_tween)
	ranged_tween.set_parallel(true)
	ranged_tween.tween_property(hand_pivot, "position", rest_position + Vector3(0.0, 0.0, 0.12), 0.10).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	ranged_tween.tween_property(hand_pivot, "rotation", rest_rotation + Vector3(deg_to_rad(-6.0), 0.0, 0.0), 0.10).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	ranged_tween.chain().set_parallel(true)
	ranged_tween.tween_property(hand_pivot, "position", rest_position, 0.20).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	ranged_tween.tween_property(hand_pivot, "rotation", rest_rotation, 0.20).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


static func _get_weapon_visual_node(weapon: Node3D) -> Node3D:
	if not is_instance_valid(weapon):
		return null
	if weapon.has_method("get_weapon_visual_root"):
		var visual_root: Variant = weapon.call("get_weapon_visual_root")
		return visual_root as Node3D if visual_root is Node3D else weapon
	return weapon


static func _get_hand_pivot(soldier) -> Node3D:
	if soldier.has_method("get_hand_pivot"):
		var pivot: Variant = soldier.call("get_hand_pivot")
		return pivot as Node3D if pivot is Node3D else null
	return null


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


static func _stop_tracked_tween(soldier, meta_key: String) -> void:
	if not soldier.has_meta(meta_key):
		return
	var tracked_tween = soldier.get_meta(meta_key)
	if tracked_tween is Tween and is_instance_valid(tracked_tween):
		tracked_tween.kill()
	soldier.remove_meta(meta_key)


static func check_ranged_combat(soldier) -> void:
	if not soldier.current_weapon or not "max_range" in soldier.current_weapon:
		return

	var attack_cooldown := get_effective_attack_cooldown(soldier, 2.0)
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
