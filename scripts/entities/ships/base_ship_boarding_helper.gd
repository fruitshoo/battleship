extends RefCounted
class_name BaseShipBoardingHelper


const BOARDING_LANDING_INSET := 0.45
const BOARDING_CONTACT_DISTANCE_PAD := 0.85
const BOARDING_BREAK_DISTANCE_PAD := 2.2
const BOARDING_WAVE_MAX_SIZE := 3

static func process_boarding_common(ship, delta: float) -> void:
	if not is_instance_valid(ship.boarding_target):
		cancel_boarding(ship)
		return
	if not _can_target_be_boarded(ship.boarding_target, ship):
		cancel_boarding(ship)
		return

	var target_pos = ship.boarding_target.global_position
	var dist = ship.global_position.distance_to(target_pos)
	var effective_boarding_distance: float = _get_effective_boarding_distance(ship)
	var effective_break_distance: float = _get_effective_break_distance(ship, effective_boarding_distance)

	if dist > effective_break_distance:
		print("[Boarding] 밧줄이 끊어졌습니다. 도선 중단.")
		cancel_boarding(ship)
		return

	if dist > effective_boarding_distance:
		ship.boarding_contact_timer = maxf(0.0, ship.boarding_contact_timer - delta * 2.0)
		ship.boarding_hook_timer = 0.0
		ship.boarding_secondary_rope_timer = 0.0
		if ship._initial_rope_deployed and dist > (effective_boarding_distance + 0.8):
			ship._clear_ropes()
			ship._initial_rope_deployed = false
			ship._full_rope_deployed = false
		return

	ship.boarding_contact_timer += delta
	if ship.boarding_contact_timer < ship.boarding_contact_grace_duration:
		return

	var stable_contact = ship._is_boarding_contact_stable()
	if not stable_contact:
		var force_hook_after = ship.boarding_contact_grace_duration + 0.65
		if ship.boarding_contact_timer < force_hook_after:
			ship.boarding_contact_timer = maxf(ship.boarding_contact_grace_duration * 0.6, ship.boarding_contact_timer - delta * 1.4)
			return

	ship.boarding_hook_timer += delta
	if not ship._initial_rope_deployed:
		if ship.boarding_hook_timer >= ship.boarding_hook_throw_delay:
			var initial_rope_count: int = 1 if _uses_limited_rope_visuals(ship) else ship.boarding_initial_rope_count
			ship._spawn_ropes(initial_rope_count)
			ship._initial_rope_deployed = true
			ship._full_rope_deployed = _uses_limited_rope_visuals(ship) or initial_rope_count >= 2
			ship.boarding_secondary_rope_timer = 0.0
			if ship.has_method("_show_boarding_start_feedback"):
				ship.call("_show_boarding_start_feedback", ship.boarding_target)
			if ship.DEBUG_COMBAT_LOGS:
				print("[Boarding] 갈고리 투척 성공, 밧줄 연결 시작.")
		return

	if not ship._full_rope_deployed:
		ship.boarding_secondary_rope_timer += delta
		if ship.boarding_secondary_rope_timer >= ship.boarding_secondary_rope_delay:
			ship._spawn_ropes()
			ship._full_rope_deployed = true
			if ship.DEBUG_COMBAT_LOGS:
				print("[Boarding] 추가 밧줄이 연결되었습니다.")
	_play_boarding_rally_cry(ship)

	if ship.boarding_prep_timer < ship.boarding_prep_duration:
		ship.boarding_prep_timer += delta
	else:
		ship.boarding_timer += delta
		var effective_interval: float = ship.get_effective_boarding_interval() if ship.has_method("get_effective_boarding_interval") else ship.boarding_interval
		if ship.boarding_timer >= effective_interval:
			ship.boarding_timer = 0.0
			if not ShipBoardingMetaHelper.is_transfer_suppressed(ship):
				transfer_boarding_wave(ship)

	ship._update_ropes(delta)


static func _uses_limited_rope_visuals(ship) -> bool:
	var contact_mode: String = ShipBoardingMetaHelper.get_contact_mode(ship)
	return contact_mode == ShipBoardingMetaHelper.CONTACT_HEAD_ON or contact_mode == ShipBoardingMetaHelper.CONTACT_CLEANUP


static func _can_target_be_boarded(target_ship: Node, attacker_ship: Node = null) -> bool:
	if not is_instance_valid(target_ship):
		return false
	if target_ship.has_method("can_be_boarded_by"):
		return target_ship.call("can_be_boarded_by", attacker_ship) == true
	var blocks_boarding: Variant = target_ship.get("blocks_boarding")
	return blocks_boarding != true if blocks_boarding != null else true


static func cancel_boarding(ship) -> void:
	if is_instance_valid(ship.boarding_target) and ship.boarding_target.has_method("get_boarding_attacker_ship") and ship.boarding_target.get_boarding_attacker_ship() == ship:
		ship.boarding_target.clear_boarding_attacker_ship()
	ship._clear_ropes()
	ship.is_boarding = false
	ship.boarding_timer = 0.0
	ship.boarding_prep_timer = 0.0
	ship.boarding_contact_timer = 0.0
	ship.boarding_hook_timer = 0.0
	ship.boarding_secondary_rope_timer = 0.0
	ship._initial_rope_deployed = false
	ship._full_rope_deployed = false
	if "boarding_pull_velocity" in ship:
		ship.boarding_pull_velocity = Vector3.ZERO
	ShipBoardingMetaHelper.clear_boarding_link_meta(ship)
	if ship.has_method("_clear_boarding_latch"):
		ship.call("_clear_boarding_latch")


static func _get_effective_boarding_distance(ship) -> float:
	if not is_instance_valid(ship.boarding_target):
		return ship.max_boarding_distance
	if not ship.has_method("get_collision_distance_to"):
		return ship.max_boarding_distance
	var contact_distance: float = float(ship.call("get_collision_distance_to", ship.boarding_target))
	return maxf(ship.max_boarding_distance, contact_distance + BOARDING_CONTACT_DISTANCE_PAD)


static func _get_effective_break_distance(ship, effective_boarding_distance: float) -> float:
	if not is_instance_valid(ship.boarding_target):
		return ship.boarding_break_distance
	if not ship.has_method("get_collision_distance_to"):
		return ship.boarding_break_distance
	var contact_distance: float = float(ship.call("get_collision_distance_to", ship.boarding_target))
	return maxf(ship.boarding_break_distance, maxf(effective_boarding_distance + 1.8, contact_distance + BOARDING_BREAK_DISTANCE_PAD))


static func _play_boarding_rally_cry(ship) -> void:
	SoldierBoardingHelper.play_boarding_rally_cry(ship, _get_ship_team_tag(ship))


static func _get_ship_team_tag(ship) -> String:
	if is_instance_valid(ship) and ship.has_method("get_team_tag"):
		return str(ship.call("get_team_tag"))
	if is_instance_valid(ship) and ship.get("team") != null:
		return str(ship.get("team"))
	return "unknown"


static func _count_target_defenders(ship, team_prop: String) -> int:
	if not is_instance_valid(ship.boarding_target):
		return 0
	var target_soldiers_node = NodeContractHelper.get_soldiers_container(ship.boarding_target)
	if not target_soldiers_node:
		target_soldiers_node = ship.boarding_target
	var defenders_alive := 0
	for child in target_soldiers_node.get_children():
		if SoldierStateHelper.is_dead_soldier(child):
			continue
		if child.has_method("get_team_tag") and child.get_team_tag() != team_prop:
			defenders_alive += 1
	return defenders_alive


static func _count_target_attackers(ship, team_prop: String) -> int:
	if not is_instance_valid(ship.boarding_target):
		return 0
	var target_soldiers_node = NodeContractHelper.get_soldiers_container(ship.boarding_target)
	if not target_soldiers_node:
		target_soldiers_node = ship.boarding_target
	var attackers_alive := 0
	for child in target_soldiers_node.get_children():
		if SoldierStateHelper.is_dead_soldier(child):
			continue
		if child.has_method("get_team_tag") and child.get_team_tag() == team_prop:
			attackers_alive += 1
	return attackers_alive


static func _count_ready_boarders(ship, team_prop: String) -> int:
	var soldiers_node = NodeContractHelper.get_soldiers_container(ship)
	if not soldiers_node:
		return 0
	var ready_count := 0
	for child in soldiers_node.get_children():
		if not SoldierStateHelper.is_alive_soldier(child):
			continue
		if not child.has_method("get_team_tag") or child.get_team_tag() != team_prop:
			continue
		if child.get("_is_jumping") == true:
			continue
		ready_count += 1
	return ready_count


static func transfer_boarding_wave(ship) -> int:
	var transferred_count := 0
	var wave_size := _get_boarding_wave_size(ship)
	for wave_index in range(wave_size):
		if not transfer_one_soldier(ship, wave_index, wave_size):
			break
		transferred_count += 1
	return transferred_count


static func transfer_one_soldier(ship, wave_index: int = 0, wave_size: int = 1) -> bool:
	if not is_instance_valid(ship.boarding_target):
		return false

	var target_soldiers_node = NodeContractHelper.get_soldiers_container(ship.boarding_target)
	if not target_soldiers_node:
		target_soldiers_node = ship.boarding_target

	var team_prop = ship.get_team_tag() if ship.has_method("get_team_tag") else ("player" if "team" in ship and str(ship.get("team")) == "player" else "enemy")
	var defenders_alive = 0
	var attackers_on_target_deck = 0
	if target_soldiers_node:
		for child in target_soldiers_node.get_children():
			if SoldierStateHelper.is_dead_soldier(child):
				continue
			if child.has_method("get_team_tag") and child.get_team_tag() != team_prop:
				defenders_alive += 1
			else:
				attackers_on_target_deck += 1
		var max_attackers_during_contest: int = maxi(2, mini(4, defenders_alive))
		if defenders_alive > 0 and attackers_on_target_deck >= max_attackers_during_contest:
			return false

	var s = null
	var soldiers_node = NodeContractHelper.get_soldiers_container(ship)
	if soldiers_node:
		var soldiers = soldiers_node.get_children()
		var enemy_count_on_deck = 0
		var ally_count_on_deck = 0
		for child in soldiers:
			if SoldierStateHelper.is_alive_soldier(child):
				if child.has_method("get_team_tag") and child.get_team_tag() != team_prop:
					enemy_count_on_deck += 1
				else:
					ally_count_on_deck += 1

			if enemy_count_on_deck > 0 and ally_count_on_deck <= enemy_count_on_deck:
				return false

		var nearest_boarder_distance_sq: float = INF
		for child in soldiers:
			if SoldierStateHelper.is_alive_soldier(child) and child.has_method("get_team_tag") and child.get_team_tag() == team_prop:
				if not (child is Node3D):
					continue
				var distance_sq: float = (child as Node3D).global_position.distance_squared_to(ship.boarding_target.global_position)
				if distance_sq < nearest_boarder_distance_sq:
					nearest_boarder_distance_sq = distance_sq
					s = child

	if s:
		var start_global = s.global_position
		_begin_soldier_boarding_jump_pose(s, "boarding")
		SoldierBoardingHelper.play_boarding_war_cry(
			s,
			"boarding",
			wave_size > 1,
			float(wave_index) * SoldierBoardingHelper.BOARDING_WAR_CRY_STAGGER_SECONDS,
			SoldierBoardingHelper.BOARDING_WAR_CRY_VOLUME_DB - 0.5
		)
		s.reparent(target_soldiers_node, true)
		s.global_position = start_global

		var jump_offset := _get_nearest_deck_landing_local(ship.boarding_target, start_global)
		var start_local_pos: Vector3 = s.position
		var horiz_dist: float = Vector2(start_local_pos.x - jump_offset.x, start_local_pos.z - jump_offset.z).length()
		var jump_height: float = maxf(2.0, horiz_dist * 0.32)
		var travel_time: float = clampf(horiz_dist / 14.0, 0.45, 0.75)

		var tween = s.create_tween()
		tween.set_parallel(true)
		tween.tween_property(s, "position:x", jump_offset.x, travel_time).set_trans(Tween.TRANS_LINEAR)
		tween.tween_property(s, "position:z", jump_offset.z, travel_time).set_trans(Tween.TRANS_LINEAR)

		var y_tween = s.create_tween()
		y_tween.tween_property(s, "position:y", start_local_pos.y + jump_height, travel_time * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		y_tween.tween_property(s, "position:y", jump_offset.y, travel_time * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		var soldier_id: int = s.get_instance_id()
		var target_ship_id: int = ship.boarding_target.get_instance_id()
		y_tween.finished.connect(func():
			BaseShipBoardingHelper._finish_transfer_landing(soldier_id, target_ship_id, jump_offset)
		)

		if s.has_method("set_team"):
			s.set_team(team_prop)

		s.owned_ship = ship.boarding_target
		EntityRegistry.move_soldier_ship(s, ship, ship.boarding_target)
		var immediate_target: Node3D = _find_nearest_hostile_soldier(s, ship.boarding_target, team_prop)
		if is_instance_valid(immediate_target) and s.has_method("move_to_target"):
			s.move_to_target(immediate_target)
			if team_prop == "enemy" and ship.boarding_target.has_method("get_team_tag") and ship.boarding_target.get_team_tag() == "player":
				if "chaos_duration_timer" in s:
					s.set("chaos_duration_timer", 0.0)
				if "chaos_tick_timer" in s:
					s.set("chaos_tick_timer", 1.0)

		if s.get("is_stationary"):
			s.set("is_stationary", false)

		print("[Action] 병사 1명 월선! (팀: %s, 대상: %s)" % [team_prop, ship.boarding_target.name])
		return true
	else:
		print("[Status] 도선할 병사가 더 이상 없습니다.")
		cancel_boarding(ship)
		if ship.has_method("check_derelict_status"):
			ship.call("check_derelict_status")
	return false


static func _get_boarding_wave_size(ship) -> int:
	var team_prop := _get_ship_team_tag(ship)
	var ready_boarders := _count_ready_boarders(ship, team_prop)
	if ready_boarders <= 0:
		return 1
	var target_defenders := _count_target_defenders(ship, team_prop)
	var target_attackers := _count_target_attackers(ship, team_prop)
	var open_contest_slots := ready_boarders
	if target_defenders > 0:
		open_contest_slots = maxi(0, maxi(2, mini(4, target_defenders)) - target_attackers)
	return clampi(mini(ready_boarders, open_contest_slots), 1, BOARDING_WAVE_MAX_SIZE)


static func _get_random_deck_landing_local(target_ship: Node3D) -> Vector3:
	var target_half_ext := _get_target_deck_half_extents(target_ship)
	var target_deck_h := _get_target_deck_height(target_ship)
	return Vector3(
		randf_range(-target_half_ext.x, target_half_ext.x),
		target_deck_h,
		randf_range(-target_half_ext.y, target_half_ext.y)
	)


static func _get_nearest_deck_landing_local(target_ship: Node3D, approach_global: Vector3) -> Vector3:
	var target_half_ext := _get_target_deck_half_extents(target_ship)
	var target_deck_h := _get_target_deck_height(target_ship)
	var approach_local: Vector3 = target_ship.to_local(approach_global)
	var inset_x := minf(BOARDING_LANDING_INSET, maxf(0.0, target_half_ext.x - 0.05))
	var inset_z := minf(BOARDING_LANDING_INSET, maxf(0.0, target_half_ext.y - 0.05))
	var outside_x := absf(approach_local.x) > target_half_ext.x
	var outside_z := absf(approach_local.z) > target_half_ext.y

	var landing_x := clampf(approach_local.x, -target_half_ext.x + inset_x, target_half_ext.x - inset_x)
	var landing_z := clampf(approach_local.z, -target_half_ext.y + inset_z, target_half_ext.y - inset_z)
	if outside_x:
		landing_x = (target_half_ext.x - inset_x) * (1.0 if approach_local.x >= 0.0 else -1.0)
	if outside_z:
		landing_z = (target_half_ext.y - inset_z) * (1.0 if approach_local.z >= 0.0 else -1.0)

	return Vector3(landing_x, target_deck_h, landing_z)


static func _finish_transfer_landing(soldier_id: int, target_ship_id: int, landing_local: Vector3) -> void:
	var soldier = instance_from_id(soldier_id)
	if not is_instance_valid(soldier):
		return
	var target_ship = instance_from_id(target_ship_id)
	if is_instance_valid(target_ship):
		soldier.position = _clamp_deck_landing_local(target_ship as Node3D, landing_local)
	_finish_soldier_boarding_jump_pose(soldier, "on_deck")


static func _clamp_deck_landing_local(target_ship: Node3D, landing_local: Vector3) -> Vector3:
	var target_half_ext := _get_target_deck_half_extents(target_ship)
	var target_deck_h := _get_target_deck_height(target_ship)
	return Vector3(
		clampf(landing_local.x, -target_half_ext.x, target_half_ext.x),
		target_deck_h,
		clampf(landing_local.z, -target_half_ext.y, target_half_ext.y)
	)


static func _get_target_deck_half_extents(target_ship: Node3D) -> Vector2:
	var target_half_ext = Vector2(1.0, 1.5)
	if target_ship.has_method("get_deck_half_extents"):
		var ext = target_ship.call("get_deck_half_extents")
		if ext is Vector2 and ext.x > 0.01 and ext.y > 0.01:
			target_half_ext = ext
	return target_half_ext


static func _get_target_deck_height(target_ship: Node3D) -> float:
	return float(target_ship.get("deck_height")) if target_ship.get("deck_height") != null else 0.5


static func _find_nearest_hostile_soldier(boarder: Node3D, target_ship: Node3D, boarder_team: String) -> Node3D:
	if not is_instance_valid(boarder) or not is_instance_valid(target_ship):
		return null
	var nearest: Node3D = null
	var nearest_distance_sq: float = INF
	var candidates: Array = []
	var soldiers_node: Node = NodeContractHelper.get_soldiers_container(target_ship)
	if is_instance_valid(soldiers_node):
		candidates = soldiers_node.get_children()
	for registered_soldier in EntityRegistry.get_soldiers_by_ship(target_ship):
		if not candidates.has(registered_soldier):
			candidates.append(registered_soldier)
	for other in candidates:
		if other == boarder or not is_instance_valid(other):
			continue
		if not (other is Node3D):
			continue
		if SoldierStateHelper.is_dead_soldier(other):
			continue
		var other_team: String = other.get_team_tag() if other.has_method("get_team_tag") else str(other.get("team"))
		if other_team == boarder_team:
			continue
		var other_node := other as Node3D
		var distance_sq: float = boarder.global_position.distance_squared_to(other_node.global_position)
		if distance_sq < nearest_distance_sq:
			nearest_distance_sq = distance_sq
			nearest = other_node
	return nearest


static func _set_soldier_boarding_status(soldier, status: String) -> void:
	if not is_instance_valid(soldier):
		return
	if soldier.has_method("set_boarding_status"):
		soldier.call("set_boarding_status", status)
	elif soldier.has_method("set_meta"):
		soldier.set_meta("boarding_status", status)


static func _begin_soldier_boarding_jump_pose(soldier, status: String) -> void:
	if not is_instance_valid(soldier):
		return
	if soldier.has_method("begin_boarding_jump_pose"):
		soldier.call("begin_boarding_jump_pose", status)
		return
	if "_is_jumping" in soldier:
		soldier.set("_is_jumping", true)
	_set_soldier_boarding_status(soldier, status)


static func _finish_soldier_boarding_jump_pose(soldier, status: String) -> void:
	if not is_instance_valid(soldier):
		return
	if soldier.has_method("finish_boarding_jump_pose"):
		soldier.call("finish_boarding_jump_pose", status)
		return
	if "_is_jumping" in soldier:
		soldier.set("_is_jumping", false)
	_set_soldier_boarding_status(soldier, status)
