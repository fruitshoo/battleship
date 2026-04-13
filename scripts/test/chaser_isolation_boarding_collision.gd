@tool
extends "res://scripts/test/chaser_isolation_runtime_methods.gd"

var has_rammed: bool = false
var leaking_rate: float = 0.0
var _leak_tick_timer: float = 0.0


func can_board_targets() -> bool:
	return allow_boarding


func get_target_ship() -> Node3D:
	return target if is_instance_valid(target) else null


func _mark_boarding_impact(target_ship: Node3D, grace_duration: float = 1.25) -> void:
	if not is_instance_valid(target_ship):
		return
	set_meta("boarding_impact_target_id", target_ship.get_instance_id())
	set_meta("boarding_impact_grace_timer", grace_duration)


func _has_recent_boarding_impact(target_ship: Node3D) -> bool:
	if not is_instance_valid(target_ship):
		return false
	if not has_meta("boarding_impact_grace_timer"):
		return false
	if float(get_meta("boarding_impact_grace_timer", 0.0)) <= 0.0:
		return false
	return int(get_meta("boarding_impact_target_id", 0)) == target_ship.get_instance_id()


func _process_boarding(delta: float) -> void:
	ChaserShipBoardingHelper.process_boarding(self, delta)


func _apply_neighbor_ship_guards(prev_pos: Vector3, proposed_pos: Vector3, excluded_ship: Node3D = null) -> Vector3:
	return ChaserShipBoardingHelper.apply_neighbor_ship_guards(self, prev_pos, proposed_pos, excluded_ship)


func _apply_ship_collision_guard(other_ship: Node3D, prev_pos: Vector3, proposed_pos: Vector3, safe_ratio: float = 0.94, impact_speed_hint: float = 0.0, emit_collision_event: bool = true) -> Vector3:
	return ChaserShipBoardingHelper.apply_ship_collision_guard(self, other_ship, prev_pos, proposed_pos, safe_ratio, impact_speed_hint, emit_collision_event)


func _emit_guarded_collision(other_ship: Node3D, impact_speed_hint: float) -> void:
	ChaserShipBoardingHelper.emit_guarded_collision(self, other_ship, impact_speed_hint)


func _soften_collision_speed() -> void:
	ChaserShipBoardingHelper.soften_collision_speed(self)


func _find_player() -> void:
	ChaserShipAiHelper.find_player(self)


func _on_body_entered(body: Node3D) -> void:
	if not can_board_targets():
		return
	if body.is_in_group("player") or (body.get_parent() and body.get_parent().is_in_group("player")):
		var ship_node := body if body.is_in_group("player") else body.get_parent()
		if is_instance_valid(ship_node) and ship_node is Node3D:
			_mark_boarding_impact(ship_node as Node3D)
		_board_ship(body)


func _on_area_entered(area: Area3D) -> void:
	if not can_board_targets():
		return
	if area.is_in_group("ship_hitbox"):
		return

	if area.is_in_group("player"):
		_board_ship(area)
	elif area.is_in_group("ship_proximity"):
		var role_parent = area.get_parent()
		if role_parent and role_parent.is_in_group("player"):
			_board_ship(role_parent)


func remove_stuck_object(_obj: Node3D, _s_mult: float, _t_mult: float) -> void:
	tilt_offset *= 0.5
	if tilt_offset < 0.01:
		tilt_offset = 0.0


func _board_ship(target_ship: Node3D) -> void:
	if not can_board_targets():
		return
	if is_dying or is_boarding:
		return

	if get_alive_crew_count() <= 0:
		return

	var ship_node = target_ship
	if not ship_node.is_in_group("player"):
		ship_node = target_ship.get_parent()
		if not (ship_node and ship_node.is_in_group("player")):
			return

	if ship_node.get("team") == team:
		return

	if team == "player":
		return

	if is_derelict:
		return

	var can_side_board: bool = _is_side_boarding_approach(ship_node)
	var can_head_on_board: bool = _can_force_head_on_boarding(ship_node)
	if not can_side_board and not can_head_on_board:
		return
	if not _has_recent_boarding_impact(ship_node):
		return

	if not has_rammed:
		has_rammed = true
		if DEBUG_COMBAT_LOGS:
			print("[Impact] 충돌 발생! 도선 시작.")

	if ship_node != boarding_target:
		boarding_target = ship_node

	var my_crew = get_alive_crew_count()
	var enemy_crew = 0
	if ship_node.has_method("get_alive_crew_count"):
		enemy_crew = ship_node.get_alive_crew_count()

	var contact_defenders: int = _count_boarding_contact_defenders(ship_node)
	set_meta("boarding_local_defenders_at_contact", contact_defenders)
	var remote_defenders_engaged: bool = _has_remote_engaged_boarding_defenders(ship_node)
	set_meta("boarding_remote_defenders_engaged", remote_defenders_engaged)
	var contact_allows_boarding: bool = remote_defenders_engaged and (contact_defenders <= 0 or my_crew > contact_defenders)
	if my_crew > enemy_crew or can_head_on_board or contact_allows_boarding:
		is_boarding = true
		boarding_target = ship_node
		set_meta("boarding_contact_mode", "head_on" if can_head_on_board and not can_side_board else "side")

		if boarding_target.has_method("set_boarding_attacker_ship"):
			boarding_target.set_boarding_attacker_ship(self)

		_clear_ropes()
		boarding_timer = 0.0
		boarding_prep_timer = 0.0
		boarding_contact_timer = 0.0
		boarding_hook_timer = 0.0
		boarding_secondary_rope_timer = 0.0
		_initial_rope_deployed = false
		_full_rope_deployed = false

		if DEBUG_COMBAT_LOGS:
			print("[Boarding] 접점 확보! 접현 후 갈고리 투척을 준비합니다. (아군 %d vs 적군 %d, 접점 방어 %d)" % [my_crew, enemy_crew, contact_defenders])
	else:
		if DEBUG_COMBAT_LOGS:
			print("[Skirmish] 접점 방어를 돌파하지 못해 도선하지 않고 대치합니다. (아군 %d vs 적군 %d, 접점 방어 %d)" % [my_crew, enemy_crew, contact_defenders])


func _can_force_head_on_boarding(target_ship: Node3D) -> bool:
	if not is_instance_valid(target_ship):
		return false
	if not target_ship.is_in_group("player"):
		return false
	var enemy_crew: int = int(target_ship.call("get_alive_crew_count")) if target_ship.has_method("get_alive_crew_count") else 0
	var state: Dictionary = _get_boarding_alignment_state(target_ship)
	if state.is_empty():
		return false
	var my_contact_dot: float = float(state.get("my_contact_dot", -1.0))
	var target_contact_abs: float = absf(float(state.get("target_contact_dot", 1.0)))
	var closing_speed: float = float(state.get("closing_speed", 999.0))
	var center_distance: float = global_position.distance_to(target_ship.global_position)
	var collision_distance: float = get_collision_distance_to(target_ship)
	if center_distance > collision_distance + 1.0:
		return false
	if enemy_crew <= 0:
		return true
	var bow_to_side_contact: bool = (
		my_contact_dot >= 0.58
		and target_contact_abs <= 0.72
		and center_distance <= collision_distance + 0.85
		and closing_speed <= boarding_max_relative_speed * 2.6
	)
	if bow_to_side_contact:
		return true
	if enemy_crew == 1 and center_distance <= collision_distance + 0.45:
		return true
	return enemy_crew <= 1 and my_contact_dot >= 0.52 and target_contact_abs <= 0.92 and closing_speed <= boarding_max_relative_speed * 2.4


func _count_boarding_contact_defenders(target_ship: Node3D) -> int:
	if not is_instance_valid(target_ship):
		return 0
	var target_team: String = target_ship.get_team_tag() if target_ship.has_method("get_team_tag") else str(target_ship.get("team"))
	if target_team.is_empty():
		return 0
	var contact_local: Vector3 = _get_boarding_contact_point_on_target_local(target_ship)
	var contact_radius: float = _get_boarding_contact_defense_radius(target_ship)
	var contact_radius_sq: float = contact_radius * contact_radius
	var defenders: int = 0
	for soldier in EntityRegistry.get_soldiers_by_ship(target_ship):
		if not is_instance_valid(soldier):
			continue
		if soldier.has_method("is_dead") and soldier.is_dead():
			continue
		var soldier_team: String = soldier.get_team_tag() if soldier.has_method("get_team_tag") else str(soldier.get("team"))
		if soldier_team != target_team:
			continue
		var soldier_local: Vector3 = target_ship.to_local(soldier.global_position)
		var diff_xz := Vector2(soldier_local.x - contact_local.x, soldier_local.z - contact_local.z)
		if diff_xz.length_squared() <= contact_radius_sq:
			defenders += 1
	return defenders


func _has_remote_engaged_boarding_defenders(target_ship: Node3D) -> bool:
	if not is_instance_valid(target_ship):
		return false
	var hostile_boarders: int = int(target_ship.get("deck_hostile_boarder_count")) if target_ship.get("deck_hostile_boarder_count") != null else 0
	if target_ship.get("deck_is_contested") == true or hostile_boarders > 0:
		return true
	var target_team: String = target_ship.get_team_tag() if target_ship.has_method("get_team_tag") else str(target_ship.get("team"))
	if target_team.is_empty():
		return false
	var contact_local: Vector3 = _get_boarding_contact_point_on_target_local(target_ship)
	var remote_radius: float = _get_boarding_contact_defense_radius(target_ship) * 1.15
	var remote_radius_sq: float = remote_radius * remote_radius
	for soldier in EntityRegistry.get_soldiers_by_ship(target_ship):
		if not is_instance_valid(soldier):
			continue
		if soldier.has_method("is_dead") and soldier.is_dead():
			continue
		var soldier_team: String = soldier.get_team_tag() if soldier.has_method("get_team_tag") else str(soldier.get("team"))
		if soldier_team != target_team:
			continue
		var current_target: Variant = soldier.get("current_target") if "current_target" in soldier else null
		if not is_instance_valid(current_target):
			continue
		var target_of_soldier_team: String = current_target.get_team_tag() if current_target.has_method("get_team_tag") else str(current_target.get("team"))
		if target_of_soldier_team == target_team:
			continue
		var soldier_local: Vector3 = target_ship.to_local(soldier.global_position)
		var diff_xz := Vector2(soldier_local.x - contact_local.x, soldier_local.z - contact_local.z)
		if diff_xz.length_squared() > remote_radius_sq:
			return true
	return false


func _get_boarding_contact_point_on_target_local(target_ship: Node3D) -> Vector3:
	var half_ext: Vector2 = target_ship.get_deck_half_extents() if target_ship.has_method("get_deck_half_extents") else Vector2(2.0, 3.0)
	var attacker_local: Vector3 = target_ship.to_local(global_position)
	var width_ratio: float = absf(attacker_local.x / maxf(half_ext.x, 0.01))
	var length_ratio: float = absf(attacker_local.z / maxf(half_ext.y, 0.01))
	var contact_span_ratio: float = 0.84 if maxf(half_ext.x, half_ext.y) >= 5.6 else 0.72
	var contact_local := Vector3.ZERO
	if width_ratio > length_ratio:
		contact_local.x = (1.0 if attacker_local.x >= 0.0 else -1.0) * half_ext.x
		contact_local.z = clampf(attacker_local.z, -half_ext.y * contact_span_ratio, half_ext.y * contact_span_ratio)
	else:
		contact_local.x = clampf(attacker_local.x, -half_ext.x * contact_span_ratio, half_ext.x * contact_span_ratio)
		contact_local.z = (1.0 if attacker_local.z >= 0.0 else -1.0) * half_ext.y
	return contact_local


func _get_boarding_contact_defense_radius(target_ship: Node3D) -> float:
	var half_ext: Vector2 = target_ship.get_deck_half_extents() if target_ship.has_method("get_deck_half_extents") else Vector2(2.0, 3.0)
	return clampf(maxf(half_ext.x, half_ext.y) * 0.28 + 1.0, 2.4, 5.5)


func add_leak(amount: float) -> void:
	leaking_rate += amount
	print("[Status] 누수 발생! 초당 데미지: %.1f" % leaking_rate)


func remove_leak(amount: float) -> void:
	leaking_rate = maxf(0.0, leaking_rate - amount)
	if leaking_rate <= 0.0:
		_leak_tick_timer = 0.0
	print("[Status] 누수 완화. 남은 누수율: %.1f" % leaking_rate)
