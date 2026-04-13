extends RefCounted


static func state_idle(soldier, delta: float, run_heavy_logic: bool) -> void:
	if soldier.has_method("_is_far_lod_sleep_candidate") and soldier._is_far_lod_sleep_candidate():
		soldier.velocity = Vector3.ZERO
		if soldier.wander_timer > 0.0:
			soldier.wander_timer -= delta
		else:
			soldier.wander_timer = randf_range(1.5, 3.0)
		return

	if run_heavy_logic:
		var enemy = soldier.find_nearest_enemy()
		if enemy:
			if soldier.is_stationary:
				soldier.current_target = enemy
				return

			soldier.current_target = enemy
			soldier._change_state(soldier.State.MOVE)
			return

		if soldier.has_method("_find_cross_ship_muster_target"):
			var muster_target: Vector3 = soldier._find_cross_ship_muster_target()
			if muster_target != Vector3.INF:
				_move_toward_point(soldier, muster_target, 0.9)
				return

		if soldier.has_method("_find_ship_duty_target"):
			var duty_target: Vector3 = soldier._find_ship_duty_target()
			if duty_target != Vector3.INF:
				_move_toward_point(soldier, duty_target, 0.75)
				return

	if soldier.wander_timer > 0:
		soldier.wander_timer -= delta
	else:
		start_wander(soldier)


static func state_wander(soldier, run_heavy_logic: bool) -> void:
	if soldier.has_method("_is_far_lod_sleep_candidate") and soldier._is_far_lod_sleep_candidate():
		soldier.velocity = Vector3.ZERO
		soldier.wander_timer = randf_range(1.5, 3.0)
		soldier._change_state(soldier.State.IDLE)
		return

	if run_heavy_logic:
		var enemy = soldier.find_nearest_enemy()
		if enemy:
			if soldier.is_stationary:
				soldier.current_target = enemy
				soldier._change_state(soldier.State.IDLE)
				return

			var dist = soldier.global_position.distance_to(enemy.global_position)
			if dist < 8.0:
				soldier.current_target = enemy
				soldier._change_state(soldier.State.MOVE)
				return

		if soldier.has_method("_find_cross_ship_muster_target"):
			var muster_target: Vector3 = soldier._find_cross_ship_muster_target()
			if muster_target != Vector3.INF:
				_move_toward_point(soldier, muster_target, 0.85)
				return

		if soldier.has_method("_find_ship_duty_target"):
			var duty_target: Vector3 = soldier._find_ship_duty_target()
			if duty_target != Vector3.INF:
				_move_toward_point(soldier, duty_target, 0.7)
				return

	if not is_instance_valid(soldier.owned_ship):
		soldier._change_state(soldier.State.IDLE)
		return

	var current_global_target = soldier.owned_ship.to_global(soldier.wander_target_local)
	var diff = current_global_target - soldier.global_position
	var wander_dist = diff.length()

	if wander_dist < 0.2:
		soldier.wander_timer = randf_range(1.0, 3.0)
		soldier._change_state(soldier.State.IDLE)
		return

	var direction = diff.normalized()
	soldier.velocity = direction * soldier.move_speed * 0.5
	soldier.move_and_slide()

	if direction.length_squared() > 0.01:
		var target_look = soldier.global_position + direction
		target_look.y = soldier.global_position.y
		if not soldier.global_position.is_equal_approx(target_look):
			soldier.look_at(target_look, Vector3.UP)


static func start_wander(soldier) -> void:
	if not is_instance_valid(soldier.owned_ship):
		return

	var half_ext = soldier._get_ship_deck_half_extents(soldier.owned_ship)
	var random_x = randf_range(-half_ext.x, half_ext.x)
	var random_z = randf_range(-half_ext.y, half_ext.y)

	soldier.wander_target_local = Vector3(random_x, 0.0, random_z)
	soldier._change_state(soldier.State.WANDER)


static func state_move(soldier) -> void:
	if soldier.is_stationary:
		soldier._change_state(soldier.State.IDLE)
		return

	if not is_instance_valid(soldier.current_target):
		if _try_muster_to_cross_ship_contact(soldier, 1.0):
			return
		soldier._change_state(soldier.State.IDLE)
		return

	if soldier.current_target.has_method("get_current_state_value") and soldier.current_target.get_current_state_value() == soldier.State.DEAD:
		soldier.current_target = null
		if _try_muster_to_cross_ship_contact(soldier, 1.0):
			return
		soldier._change_state(soldier.State.IDLE)
		return

	var target_ship = soldier.current_target.get_owned_ship_node() if soldier.current_target.has_method("get_owned_ship_node") else null
	if is_instance_valid(target_ship) and target_ship != soldier.owned_ship:
		if target_ship.has_method("is_sinking_or_dying") and target_ship.is_sinking_or_dying():
			soldier.current_target = null
			if _try_muster_to_cross_ship_contact(soldier, 1.0):
				return
			soldier._change_state(soldier.State.IDLE)
			return

	var pos_self_2d = Vector2(soldier.global_position.x, soldier.global_position.z)
	var pos_target_2d = Vector2(soldier.current_target.global_position.x, soldier.current_target.global_position.z)
	var distance_xz = pos_self_2d.distance_to(pos_target_2d)

	if is_instance_valid(soldier.owned_ship) and target_ship != soldier.owned_ship:
		if not soldier._is_ship_pair_in_melee_range(target_ship):
			soldier._change_state(soldier.State.IDLE)
			return
		if soldier.has_method("_is_in_cross_ship_contact_zone") and soldier._is_in_cross_ship_contact_zone(target_ship) == false:
			if soldier.has_method("_get_cross_ship_contact_point_global"):
				var muster_target: Vector3 = soldier._get_cross_ship_contact_point_global(target_ship)
				if muster_target != Vector3.INF:
					_move_toward_point(soldier, muster_target, 1.0)
					return
		var engage_distance: float = soldier._get_cross_ship_engage_max_distance(target_ship)
		if distance_xz > engage_distance:
			soldier._change_state(soldier.State.IDLE)
			return

	if distance_xz > soldier.detection_range:
		soldier.current_target = null
		soldier._change_state(soldier.State.IDLE)
		return

	var attack_range = soldier.current_weapon.attack_range if soldier.current_weapon and "attack_range" in soldier.current_weapon else 1.2
	if distance_xz <= attack_range:
		soldier._change_state(soldier.State.ATTACK)
		return

	var target_pos = soldier.current_target.global_position
	var direction = (target_pos - soldier.global_position).normalized()
	soldier.velocity = direction * soldier.move_speed
	soldier.move_and_slide()

	if direction.length_squared() > 0.01:
		var target_look = soldier.global_position + direction
		target_look.y = soldier.global_position.y
		if not soldier.global_position.is_equal_approx(target_look):
			soldier.look_at(target_look, Vector3.UP)


static func state_attack(soldier) -> void:
	if not is_instance_valid(soldier.current_target):
		soldier._change_state(soldier.State.IDLE)
		return

	if (soldier.current_target.has_method("get_current_state_value") and soldier.current_target.get_current_state_value() == soldier.State.DEAD) or soldier.current_target.get_team_tag() == soldier.team:
		soldier.current_target = null
		if _try_muster_to_cross_ship_contact(soldier, 0.95):
			return
		soldier._change_state(soldier.State.IDLE)
		return

	var target_ship = soldier.current_target.get_owned_ship_node() if soldier.current_target.has_method("get_owned_ship_node") else null
	if is_instance_valid(target_ship) and target_ship != soldier.owned_ship:
		if target_ship.has_method("is_sinking_or_dying") and target_ship.is_sinking_or_dying():
			soldier.current_target = null
			if _try_muster_to_cross_ship_contact(soldier, 0.95):
				return
			soldier._change_state(soldier.State.IDLE)
			return

	var pos_self_2d = Vector2(soldier.global_position.x, soldier.global_position.z)
	var pos_target_2d = Vector2(soldier.current_target.global_position.x, soldier.current_target.global_position.z)
	var distance_xz = pos_self_2d.distance_to(pos_target_2d)

	if is_instance_valid(soldier.owned_ship) and target_ship != soldier.owned_ship:
		if not soldier._is_ship_pair_in_melee_range(target_ship):
			soldier._change_state(soldier.State.IDLE)
			return
		if soldier.has_method("_is_in_cross_ship_contact_zone") and soldier._is_in_cross_ship_contact_zone(target_ship) == false:
			soldier._change_state(soldier.State.MOVE)
			return

	var attack_range = soldier.current_weapon.attack_range if soldier.current_weapon and "attack_range" in soldier.current_weapon else 1.2
	if distance_xz > attack_range * 1.2:
		soldier._change_state(soldier.State.MOVE)
		return

	soldier.look_at(
		Vector3(soldier.current_target.global_position.x, soldier.global_position.y, soldier.current_target.global_position.z),
		Vector3.UP
	)

	if soldier.attack_timer <= 0:
		if soldier.current_target.has_method("get_hull_ratio"):
			soldier._perform_special_attack(soldier.current_target)
		else:
			soldier._perform_attack()
		soldier.attack_timer = soldier.current_weapon.attack_cooldown if soldier.current_weapon and "attack_cooldown" in soldier.current_weapon else 1.0


static func _move_toward_point(soldier, target_pos: Vector3, speed_scale: float = 1.0) -> void:
	var flat_target := Vector3(target_pos.x, soldier.global_position.y, target_pos.z)
	var diff: Vector3 = flat_target - soldier.global_position
	diff.y = 0.0
	if diff.length_squared() <= 0.04:
		soldier.velocity = Vector3.ZERO
		soldier.move_and_slide()
		return

	var direction: Vector3 = diff.normalized()
	soldier.velocity = direction * soldier.move_speed * speed_scale
	soldier.move_and_slide()

	if direction.length_squared() > 0.01:
		var target_look: Vector3 = soldier.global_position + direction
		target_look.y = soldier.global_position.y
		if not soldier.global_position.is_equal_approx(target_look):
			soldier.look_at(target_look, Vector3.UP)


static func _try_muster_to_cross_ship_contact(soldier, speed_scale: float = 1.0) -> bool:
	if not soldier.has_method("_find_cross_ship_muster_target"):
		return false
	var muster_target: Vector3 = soldier._find_cross_ship_muster_target()
	if muster_target == Vector3.INF:
		return false
	_move_toward_point(soldier, muster_target, speed_scale)
	return true
