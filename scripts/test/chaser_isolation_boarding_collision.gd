@tool
extends "res://scripts/test/chaser_isolation_runtime_methods.gd"

var has_rammed: bool = false
var leaking_rate: float = 0.0
var _leak_tick_timer: float = 0.0


func can_board_targets() -> bool:
	return allow_boarding


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

	if not _is_side_boarding_approach(ship_node):
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

	if my_crew > enemy_crew:
		is_boarding = true
		boarding_target = ship_node

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
			print("[Boarding] 병력 우위! 접현 후 갈고리 투척을 준비합니다. (아군 %d vs 적군 %d)" % [my_crew, enemy_crew])
	else:
		if DEBUG_COMBAT_LOGS:
			print("[Skirmish] 병력 우위 부족으로 도선하지 않고 대치합니다. (아군 %d vs 적군 %d)" % [my_crew, enemy_crew])


func add_leak(amount: float) -> void:
	leaking_rate += amount
	print("[Status] 누수 발생! 초당 데미지: %.1f" % leaking_rate)


func remove_leak(amount: float) -> void:
	leaking_rate = maxf(0.0, leaking_rate - amount)
	if leaking_rate <= 0.0:
		_leak_tick_timer = 0.0
	print("[Status] 누수 완화. 남은 누수율: %.1f" % leaking_rate)
