extends RefCounted
class_name BaseShipBoardingHelper


const SoldierBoardingPrepBarHelper = preload("res://scripts/entities/soldiers/soldier_boarding_prep_bar_helper.gd")
const SoldierDeckZoneHelper = preload("res://scripts/entities/soldiers/soldier_deck_zone_helper.gd")
const SoldierShipHelper = preload("res://scripts/entities/soldiers/soldier_ship_helper.gd")
const BOARDING_LANDING_INSET := 0.58
const BOARDING_LANDING_CLAMP_INSET := 0.24
const BOARDING_CONTACT_DISTANCE_PAD := 0.85
const BOARDING_BREAK_DISTANCE_PAD := 2.2
const BOARDING_WAVE_MAX_SIZE := 3
const HOSTILE_BOARDING_WAVE_MAX_SIZE := 2
const HOSTILE_BOARDING_CONTEST_MAX := 2
const BOARDING_LAUNCH_INSET := 0.18
const BOARDING_LAUNCH_READY_MIN_RADIUS := 2.35
const BOARDING_LAUNCH_READY_MAX_RADIUS := 3.55
const BOARDING_PREP_BAR_READY_RADIUS_PAD := 2.4
const BOARDING_BLOCKED_RETRY_DELAY := 0.25
const HOSTILE_BOARDING_TRAVEL_SPEED := 12.0
const HOSTILE_BOARDING_TRAVEL_MIN := 0.48
const HOSTILE_BOARDING_TRAVEL_MAX := 0.86
const ROOF_BOARDING_TRAVEL_SPEED := 9.5
const ROOF_BOARDING_TRAVEL_MIN := 0.68
const ROOF_BOARDING_TRAVEL_MAX := 1.08
const ROOF_BOARDING_JUMP_HEIGHT_MIN := 0.65
const ROOF_BOARDING_JUMP_HEIGHT_MAX := 1.25
const ROOF_BOARDING_LANDING_SPACING := 0.72
const BOARDING_TRAVEL_SPEED := 12.0
const BOARDING_TRAVEL_MIN := 0.46
const BOARDING_TRAVEL_MAX := 0.82

static func process_boarding_common(ship, delta: float) -> void:
	if not is_instance_valid(ship.boarding_target):
		_hide_boarding_prep_bars_on_ship(ship)
		cancel_boarding(ship)
		return
	if not _can_target_be_boarded(ship.boarding_target, ship):
		_hide_boarding_prep_bars_on_ship(ship)
		cancel_boarding(ship)
		return

	var target_pos = ship.boarding_target.global_position
	var dist = ship.global_position.distance_to(target_pos)
	var effective_boarding_distance: float = _get_effective_boarding_distance(ship)
	var effective_break_distance: float = _get_effective_break_distance(ship, effective_boarding_distance)

	if dist > effective_break_distance:
		print("[Boarding] 밧줄이 끊어졌습니다. 도선 중단.")
		_hide_boarding_prep_bars_on_ship(ship)
		cancel_boarding(ship)
		return

	if dist > effective_boarding_distance and not ship._initial_rope_deployed:
		ship.boarding_contact_timer = maxf(0.0, ship.boarding_contact_timer - delta * 2.0)
		ship.boarding_hook_timer = 0.0
		ship.boarding_secondary_rope_timer = 0.0
		_update_boarding_prep_bars(ship)
		return

	ship.boarding_contact_timer += delta
	if ship.boarding_contact_timer < ship.boarding_contact_grace_duration:
		_update_boarding_prep_bars(ship)
		return

	var stable_contact = ship._is_boarding_contact_stable()
	if not stable_contact:
		var force_hook_after = ship.boarding_contact_grace_duration + 0.65
		if ship.boarding_contact_timer < force_hook_after:
			var unstable_decay_rate := 1.4
			if ship.boarding_contact_grace_duration <= 0.001:
				unstable_decay_rate = 0.35
			ship.boarding_contact_timer = maxf(ship.boarding_contact_grace_duration * 0.6, ship.boarding_contact_timer - delta * unstable_decay_rate)
			_update_boarding_prep_bars(ship)
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
		_update_boarding_prep_bars(ship)
		return

	if not ship._full_rope_deployed:
		ship.boarding_secondary_rope_timer += delta
		if ship.boarding_secondary_rope_timer >= ship.boarding_secondary_rope_delay:
			ship._spawn_ropes()
			ship._full_rope_deployed = true
			if ship.DEBUG_COMBAT_LOGS:
				print("[Boarding] 추가 밧줄이 연결되었습니다.")
		if not ship._full_rope_deployed and _requires_full_rope_before_transfer(ship):
			ship._update_ropes(delta)
			_update_boarding_prep_bars(ship)
			return
	_play_boarding_rally_cry(ship)

	if ship.boarding_prep_timer < ship.boarding_prep_duration:
		ship.boarding_prep_timer += delta
	else:
		ship.boarding_timer += delta
		var effective_interval: float = ship.get_effective_boarding_interval() if ship.has_method("get_effective_boarding_interval") else ship.boarding_interval
		if ship.boarding_timer >= effective_interval:
			var transferred_count := 0
			if not ShipBoardingMetaHelper.is_transfer_suppressed(ship):
				transferred_count = transfer_boarding_wave(ship)
			if transferred_count > 0:
				ship.boarding_timer = 0.0
			else:
				ship.boarding_timer = _get_blocked_boarding_retry_timer(effective_interval)

	_update_boarding_prep_bars(ship)
	ship._update_ropes(delta)


static func _get_blocked_boarding_retry_timer(effective_interval: float) -> float:
	return maxf(0.0, effective_interval - minf(BOARDING_BLOCKED_RETRY_DELAY, effective_interval * 0.5))


static func _uses_limited_rope_visuals(ship) -> bool:
	var contact_mode: String = ShipBoardingMetaHelper.get_contact_mode(ship)
	if ShipBoardingMetaHelper.get_approach_mode(ship) == ShipBoardingMetaHelper.APPROACH_REAR:
		return false
	return contact_mode == ShipBoardingMetaHelper.CONTACT_HEAD_ON or contact_mode == ShipBoardingMetaHelper.CONTACT_CLEANUP


static func _requires_full_rope_before_transfer(ship) -> bool:
	var contact_mode: String = ShipBoardingMetaHelper.get_contact_mode(ship)
	if contact_mode == ShipBoardingMetaHelper.CONTACT_SIDE:
		return true
	return ShipBoardingMetaHelper.get_approach_mode(ship) == ShipBoardingMetaHelper.APPROACH_REAR


static func _can_target_be_boarded(target_ship: Node, attacker_ship: Node = null) -> bool:
	if not is_instance_valid(target_ship):
		return false
	if target_ship.has_method("can_be_boarded_by"):
		return target_ship.call("can_be_boarded_by", attacker_ship) == true
	var blocks_boarding: Variant = target_ship.get("blocks_boarding")
	return blocks_boarding != true if blocks_boarding != null else true


static func cancel_boarding(ship) -> void:
	_hide_boarding_prep_bars_on_ship(ship)
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


static func _update_boarding_prep_bars(ship) -> void:
	if not _should_show_boarding_prep_bars(ship):
		_hide_boarding_prep_bars_on_ship(ship)
		return
	var soldiers_node = NodeContractHelper.get_soldiers_container(ship)
	if not soldiers_node:
		return
	var team_prop := _get_ship_team_tag(ship)
	var launch_global := _get_boarding_launch_point_global(ship, ship.boarding_target)
	var ready_radius := _get_boarding_prep_bar_ready_radius(ship)
	var ready_radius_sq := ready_radius * ready_radius
	var ratio := _get_boarding_readiness_ratio(ship)
	var urgent := ratio >= 0.86
	for child in soldiers_node.get_children():
		if not (child is Node3D):
			continue
		if not SoldierStateHelper.is_alive_soldier(child):
			SoldierBoardingPrepBarHelper.hide(child)
			continue
		if not child.has_method("get_team_tag") or child.get_team_tag() != team_prop:
			SoldierBoardingPrepBarHelper.hide(child)
			continue
		if child.get("_is_jumping") == true:
			SoldierBoardingPrepBarHelper.hide(child)
			continue
		var distance_sq: float = (child as Node3D).global_position.distance_squared_to(launch_global)
		if distance_sq > ready_radius_sq:
			SoldierBoardingPrepBarHelper.hide(child)
			continue
		SoldierBoardingPrepBarHelper.update(child, ratio, urgent)


static func _should_show_boarding_prep_bars(ship) -> bool:
	if not is_instance_valid(ship) or not is_instance_valid(ship.boarding_target):
		return false
	if ship.get("is_boarding") != true:
		return false
	if _get_ship_team_tag(ship) != "enemy":
		return false
	if _get_ship_team_tag(ship.boarding_target) != "player":
		return false
	return true


static func _hide_boarding_prep_bars_on_ship(ship) -> void:
	if not is_instance_valid(ship):
		return
	var soldiers_node = NodeContractHelper.get_soldiers_container(ship)
	if not soldiers_node:
		return
	for child in soldiers_node.get_children():
		SoldierBoardingPrepBarHelper.hide(child)


static func _get_boarding_readiness_ratio(ship) -> float:
	var grace: float = maxf(0.0, float(ship.boarding_contact_grace_duration))
	var hook_delay: float = maxf(0.0, float(ship.boarding_hook_throw_delay))
	var secondary_delay: float = maxf(0.0, float(ship.boarding_secondary_rope_delay))
	var prep_duration: float = maxf(0.0, float(ship.boarding_prep_duration))
	var interval: float = maxf(0.05, float(ship.get_effective_boarding_interval()) if ship.has_method("get_effective_boarding_interval") else float(ship.boarding_interval))
	var rope_delay := secondary_delay if _requires_full_rope_before_transfer(ship) else 0.0
	var total := maxf(0.05, grace + hook_delay + rope_delay + prep_duration + interval)
	var elapsed := 0.0
	if not bool(ship._initial_rope_deployed):
		elapsed = minf(float(ship.boarding_contact_timer), grace)
		if float(ship.boarding_contact_timer) >= grace:
			elapsed += minf(float(ship.boarding_hook_timer), hook_delay)
	elif _requires_full_rope_before_transfer(ship) and not bool(ship._full_rope_deployed):
		elapsed = grace + hook_delay + minf(float(ship.boarding_secondary_rope_timer), secondary_delay)
	else:
		elapsed = grace + hook_delay + rope_delay
		if float(ship.boarding_prep_timer) < prep_duration:
			elapsed += minf(float(ship.boarding_prep_timer), prep_duration)
		else:
			elapsed += prep_duration + minf(float(ship.boarding_timer), interval)
	return clampf(elapsed / total, 0.0, 1.0)


static func _get_boarding_prep_bar_ready_radius(ship) -> float:
	return maxf(_get_boarding_launch_ready_radius(ship) + BOARDING_PREP_BAR_READY_RADIUS_PAD, 5.2)


static func _get_boarding_transfer_ready_radius(ship) -> float:
	if _uses_relaxed_boarding_ready_radius(ship):
		return maxf(_get_boarding_launch_ready_radius(ship) + BOARDING_PREP_BAR_READY_RADIUS_PAD, 5.2)
	return _get_boarding_launch_ready_radius(ship)


static func _uses_relaxed_boarding_ready_radius(ship) -> bool:
	var contact_mode: String = ShipBoardingMetaHelper.get_contact_mode(ship)
	return contact_mode == ShipBoardingMetaHelper.CONTACT_HEAD_ON or contact_mode == ShipBoardingMetaHelper.CONTACT_CLEANUP


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


static func _count_target_defenders(ship, team_prop: String, target_zone: String = SoldierDeckZoneHelper.ZONE_MAIN) -> int:
	if not is_instance_valid(ship.boarding_target):
		return 0
	var target_soldiers_node = NodeContractHelper.get_soldiers_container(ship.boarding_target)
	if not target_soldiers_node:
		target_soldiers_node = ship.boarding_target
	var defenders_alive := 0
	for child in target_soldiers_node.get_children():
		if SoldierStateHelper.is_dead_soldier(child):
			continue
		if not SoldierDeckZoneHelper.is_in_zone(child, target_zone):
			continue
		if child.has_method("get_team_tag") and child.get_team_tag() != team_prop:
			defenders_alive += 1
	return defenders_alive


static func _count_target_attackers(ship, team_prop: String, target_zone: String = SoldierDeckZoneHelper.ZONE_MAIN) -> int:
	if not is_instance_valid(ship.boarding_target):
		return 0
	var target_soldiers_node = NodeContractHelper.get_soldiers_container(ship.boarding_target)
	if not target_soldiers_node:
		target_soldiers_node = ship.boarding_target
	var attackers_alive := 0
	for child in target_soldiers_node.get_children():
		if SoldierStateHelper.is_dead_soldier(child):
			continue
		if not SoldierDeckZoneHelper.is_in_zone(child, target_zone):
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
	var target_zone := _get_target_boarding_zone(ship, team_prop)
	var defenders_alive = 0
	var attackers_on_target_deck = 0
	if target_soldiers_node:
		for child in target_soldiers_node.get_children():
			if SoldierStateHelper.is_dead_soldier(child):
				continue
			if not SoldierDeckZoneHelper.is_in_zone(child, target_zone):
				continue
			if child.has_method("get_team_tag") and child.get_team_tag() != team_prop:
				defenders_alive += 1
			else:
				attackers_on_target_deck += 1
		var max_attackers_during_contest: int = _get_boarding_contest_limit(ship.boarding_target, team_prop, defenders_alive, target_zone)
		if defenders_alive > 0 and attackers_on_target_deck >= max_attackers_during_contest:
			return false

	var s = null
	var has_any_boarder := false
	var soldiers_node = NodeContractHelper.get_soldiers_container(ship)
	if soldiers_node:
		var soldiers = soldiers_node.get_children()
		var enemy_count_on_deck = 0
		var friendly_count_on_deck = 0
		for child in soldiers:
			if SoldierStateHelper.is_alive_soldier(child):
				if child.has_method("get_team_tag") and child.get_team_tag() != team_prop:
					enemy_count_on_deck += 1
				else:
					friendly_count_on_deck += 1

			if enemy_count_on_deck > 0 and friendly_count_on_deck <= enemy_count_on_deck:
				return false

		var nearest_boarder_distance_sq: float = INF
		var launch_global := _get_boarding_launch_point_global(ship, ship.boarding_target)
		var ready_radius := _get_boarding_transfer_ready_radius(ship)
		var ready_radius_sq := ready_radius * ready_radius
		for child in soldiers:
			if SoldierStateHelper.is_alive_soldier(child) and child.has_method("get_team_tag") and child.get_team_tag() == team_prop:
				if not (child is Node3D):
					continue
				has_any_boarder = true
				if child.get("_is_jumping") == true:
					continue
				var distance_sq: float = (child as Node3D).global_position.distance_squared_to(launch_global)
				if distance_sq > ready_radius_sq:
					continue
				if distance_sq < nearest_boarder_distance_sq:
					nearest_boarder_distance_sq = distance_sq
					s = child

	if s:
		SoldierBoardingPrepBarHelper.hide(s)
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
		if target_zone == SoldierDeckZoneHelper.ZONE_ROOF and ship.boarding_target.has_method("get_roof_boarding_landing_local"):
			jump_offset = ship.boarding_target.call("get_roof_boarding_landing_local", start_global)
			jump_offset = _get_spread_roof_boarding_landing_local(ship.boarding_target, jump_offset, wave_index, wave_size)
		var start_local_pos: Vector3 = s.position
		var horiz_dist: float = Vector2(start_local_pos.x - jump_offset.x, start_local_pos.z - jump_offset.z).length()
		var jump_height: float = clampf(maxf(1.35, horiz_dist * 0.22), 1.35, 2.35)
		var travel_time: float = _get_boarding_transfer_travel_time(horiz_dist, team_prop, ship.boarding_target)
		var jump_peak_y: float = start_local_pos.y + jump_height
		if target_zone == SoldierDeckZoneHelper.ZONE_ROOF:
			jump_height = clampf(maxf(ROOF_BOARDING_JUMP_HEIGHT_MIN, horiz_dist * 0.12), ROOF_BOARDING_JUMP_HEIGHT_MIN, ROOF_BOARDING_JUMP_HEIGHT_MAX)
			travel_time = clampf(horiz_dist / ROOF_BOARDING_TRAVEL_SPEED, ROOF_BOARDING_TRAVEL_MIN, ROOF_BOARDING_TRAVEL_MAX)
			jump_peak_y = maxf(start_local_pos.y, jump_offset.y) + jump_height
			SoldierDeckZoneHelper.set_roof_boarder(s, true)
		SoldierBoardingHelper.face_boarding_jump_direction(s, ship.boarding_target.to_global(jump_offset))

		var soldier_id: int = s.get_instance_id()
		var target_ship_id: int = ship.boarding_target.get_instance_id()
		var transfer_team: String = str(team_prop)
		var tween = s.create_tween()
		if target_zone == SoldierDeckZoneHelper.ZONE_ROOF:
			var arc_callable := func(progress: float) -> void:
				BaseShipBoardingHelper._apply_boarding_jump_arc(soldier_id, start_local_pos, jump_offset, jump_height, progress)
			tween.tween_method(arc_callable, 0.0, 1.0, travel_time)
		else:
			tween.set_parallel(true)
			tween.tween_property(s, "position:x", jump_offset.x, travel_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			tween.tween_property(s, "position:z", jump_offset.z, travel_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			var y_tween = s.create_tween()
			y_tween.tween_property(s, "position:y", jump_peak_y, travel_time * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			y_tween.tween_property(s, "position:y", jump_offset.y, travel_time * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		if s.has_method("set_team"):
			s.set_team(team_prop)

		s.owned_ship = ship.boarding_target
		EntityRegistry.move_soldier_ship(s, ship, ship.boarding_target)
		var immediate_target: Node3D = _find_nearest_hostile_soldier(s, ship.boarding_target, team_prop)
		var landing_target_id: int = immediate_target.get_instance_id() if is_instance_valid(immediate_target) else 0
		tween.finished.connect(func():
			BaseShipBoardingHelper._finish_transfer_landing(soldier_id, target_ship_id, jump_offset, landing_target_id, transfer_team)
			BaseShipBoardingHelper._apply_boarding_transfer_damage(soldier_id, target_ship_id, transfer_team)
		)

		if s.get("is_stationary"):
			s.set("is_stationary", false)

		print("[Action] 병사 1명 월선! (팀: %s, 대상: %s)" % [team_prop, ship.boarding_target.name])
		return true
	else:
		if has_any_boarder:
			return false
		print("[Status] 도선할 병사가 더 이상 없습니다.")
		cancel_boarding(ship)
		if ship.has_method("check_derelict_status"):
			ship.call("check_derelict_status")
	return false


static func _get_boarding_transfer_travel_time(horiz_dist: float, team_prop: String, target_ship: Node3D) -> float:
	if team_prop == "enemy" and _get_ship_team_tag(target_ship) == "player":
		return clampf(horiz_dist / HOSTILE_BOARDING_TRAVEL_SPEED, HOSTILE_BOARDING_TRAVEL_MIN, HOSTILE_BOARDING_TRAVEL_MAX)
	return clampf(horiz_dist / BOARDING_TRAVEL_SPEED, BOARDING_TRAVEL_MIN, BOARDING_TRAVEL_MAX)


static func _apply_boarding_jump_arc(soldier_id: int, start_local: Vector3, landing_local: Vector3, arc_height: float, progress: float) -> void:
	var soldier := NodeContractHelper.get_instance_node(soldier_id)
	if not is_instance_valid(soldier):
		return
	var t := clampf(progress, 0.0, 1.0)
	var next_pos := start_local.lerp(landing_local, t)
	next_pos.y = lerpf(start_local.y, landing_local.y, t) + sin(t * PI) * arc_height
	soldier.position = next_pos


static func _get_spread_roof_boarding_landing_local(target_ship: Node3D, landing_local: Vector3, wave_index: int, wave_size: int) -> Vector3:
	if wave_size <= 1:
		return landing_local
	var radial := Vector2(landing_local.x, landing_local.z)
	if radial.length_squared() <= 0.0001:
		radial = Vector2.RIGHT
	var tangent := Vector2(-radial.y, radial.x).normalized()
	var centered_index := float(wave_index) - (float(wave_size) - 1.0) * 0.5
	var offset := tangent * centered_index * ROOF_BOARDING_LANDING_SPACING
	var spread_landing := landing_local + Vector3(offset.x, 0.0, offset.y)
	if is_instance_valid(target_ship) and target_ship.has_method("clamp_roof_boarding_landing_local"):
		return target_ship.call("clamp_roof_boarding_landing_local", spread_landing)
	return spread_landing


static func _get_boarding_wave_size(ship) -> int:
	var team_prop := _get_ship_team_tag(ship)
	var ready_boarders := _count_ready_boarders(ship, team_prop)
	if ready_boarders <= 0:
		return 1
	var target_zone := _get_target_boarding_zone(ship, team_prop)
	var target_defenders := _count_target_defenders(ship, team_prop, target_zone)
	var target_attackers := _count_target_attackers(ship, team_prop, target_zone)
	var open_contest_slots := ready_boarders
	var wave_limit := _get_boarding_wave_limit(ship, team_prop, target_zone)
	if target_defenders > 0:
		var contest_limit := _get_boarding_contest_limit(ship.boarding_target, team_prop, target_defenders, target_zone)
		open_contest_slots = maxi(0, contest_limit - target_attackers)
	var allowed_boarders := mini(ready_boarders, open_contest_slots)
	if allowed_boarders <= 0:
		return 0
	return clampi(allowed_boarders, 1, wave_limit)


static func _get_boarding_wave_limit(ship, team_prop: String, _target_zone: String = SoldierDeckZoneHelper.ZONE_MAIN) -> int:
	var slot_penalty := _get_defender_boarding_slot_penalty(ship.boarding_target if is_instance_valid(ship) else null, team_prop)
	var base_limit := HOSTILE_BOARDING_WAVE_MAX_SIZE if _is_hostile_boarding_player(ship.boarding_target if is_instance_valid(ship) else null, team_prop) else BOARDING_WAVE_MAX_SIZE
	return maxi(1, base_limit - slot_penalty)


static func _get_boarding_contest_limit(target_ship: Node, attacker_team: String, defender_count: int, _target_zone: String = SoldierDeckZoneHelper.ZONE_MAIN) -> int:
	var contest_max := HOSTILE_BOARDING_CONTEST_MAX if _is_hostile_boarding_player(target_ship, attacker_team) else 4
	var base_limit := maxi(2, mini(contest_max, defender_count))
	var slot_penalty := _get_defender_boarding_slot_penalty(target_ship, attacker_team)
	return maxi(1, base_limit - slot_penalty)


static func _is_hostile_boarding_player(target_ship: Node, attacker_team: String) -> bool:
	return attacker_team == "enemy" and is_instance_valid(target_ship) and _get_ship_team_tag(target_ship) == "player"


static func _is_hostile_roof_boarding_target(target_ship: Node, attacker_team: String) -> bool:
	return _is_hostile_boarding_player(target_ship, attacker_team) \
		and target_ship.has_method("is_roof_boarding_enabled") \
		and target_ship.call("is_roof_boarding_enabled") == true


static func _get_target_boarding_zone(ship, team_prop: String) -> String:
	if is_instance_valid(ship) and _is_hostile_roof_boarding_target(ship.boarding_target, team_prop):
		return SoldierDeckZoneHelper.ZONE_ROOF
	return SoldierDeckZoneHelper.ZONE_MAIN


static func _get_defender_boarding_slot_penalty(target_ship: Node, attacker_team: String) -> int:
	if attacker_team != "enemy" or not is_instance_valid(target_ship):
		return 0
	if _get_ship_team_tag(target_ship) != "player":
		return 0
	return maxi(0, int(target_ship.get_meta("enemy_boarding_slot_penalty", 0)))


static func _get_random_deck_landing_local(target_ship: Node3D) -> Vector3:
	var target_half_ext := _get_target_deck_half_extents(target_ship)
	var target_deck_h := _get_target_deck_height(target_ship)
	var safe_half_z: float = maxf(0.08, target_half_ext.y - minf(BOARDING_LANDING_CLAMP_INSET, maxf(0.0, target_half_ext.y - 0.08)))
	var random_z := randf_range(-safe_half_z, safe_half_z)
	var half_width := SoldierShipHelper.get_ship_deck_half_width_at_z(target_ship, random_z, target_half_ext.x)
	var safe_half_x: float = maxf(0.08, half_width - minf(BOARDING_LANDING_CLAMP_INSET, maxf(0.0, half_width - 0.08)))
	return Vector3(
		randf_range(-safe_half_x, safe_half_x),
		target_deck_h,
		random_z
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

	return SoldierShipHelper.get_clamped_main_deck_local(
		target_ship,
		Vector3(landing_x, target_deck_h, landing_z),
		BOARDING_LANDING_INSET,
		target_half_ext
	)


static func _get_boarding_launch_point_global(ship: Node3D, target_ship: Node3D) -> Vector3:
	if not is_instance_valid(ship):
		return Vector3.ZERO
	if not is_instance_valid(target_ship):
		return ship.global_position
	var half_ext := _get_target_deck_half_extents(ship)
	var deck_h := _get_target_deck_height(ship)
	var target_local: Vector3 = ship.to_local(target_ship.global_position)
	if _uses_relaxed_boarding_ready_radius(ship) and ShipBoardingMetaHelper.has_contact_anchor(ship):
		target_local = ship.to_local(target_ship.to_global(ShipBoardingMetaHelper.get_contact_anchor_local(ship)))
	var span_ratio: float = 0.72
	if half_ext.x >= 3.2 or half_ext.y >= 5.6:
		span_ratio = 0.84
	var use_side_edge: bool = absf(target_local.x / maxf(half_ext.x, 0.01)) > absf(target_local.z / maxf(half_ext.y, 0.01))
	var launch_local := Vector3.ZERO
	if use_side_edge:
		var x_sign: float = 1.0 if target_local.x >= 0.0 else -1.0
		launch_local.x = x_sign * maxf(0.0, half_ext.x - BOARDING_LAUNCH_INSET)
		launch_local.z = clampf(target_local.z, -half_ext.y * span_ratio, half_ext.y * span_ratio)
	else:
		var z_sign: float = 1.0 if target_local.z >= 0.0 else -1.0
		launch_local.x = clampf(target_local.x, -half_ext.x * span_ratio, half_ext.x * span_ratio)
		launch_local.z = z_sign * maxf(0.0, half_ext.y - BOARDING_LAUNCH_INSET)
	launch_local = SoldierShipHelper.get_clamped_main_deck_local(ship, launch_local, BOARDING_LAUNCH_INSET, half_ext)
	launch_local.y = deck_h
	return ship.to_global(launch_local)


static func _get_boarding_launch_ready_radius(ship: Node3D) -> float:
	var half_ext := _get_target_deck_half_extents(ship)
	var deck_pressure: float = maxf(half_ext.x, half_ext.y)
	return clampf(deck_pressure * 0.62, BOARDING_LAUNCH_READY_MIN_RADIUS, BOARDING_LAUNCH_READY_MAX_RADIUS)


static func _finish_transfer_landing(soldier_id: int, target_ship_id: int, landing_local: Vector3, landing_target_id: int = 0, attacker_team: String = "") -> void:
	var soldier := NodeContractHelper.get_instance_node(soldier_id)
	if not is_instance_valid(soldier):
		return
	var target_ship := NodeContractHelper.get_instance_node3d(target_ship_id)
	if is_instance_valid(target_ship):
		if SoldierDeckZoneHelper.is_roof(soldier) and target_ship.has_method("clamp_roof_boarding_landing_local"):
			soldier.position = landing_local
		else:
			soldier.position = _clamp_deck_landing_local(target_ship, landing_local)
	_finish_soldier_boarding_jump_pose(soldier, "on_deck")
	var landing_target := NodeContractHelper.get_instance_node3d(landing_target_id)
	if is_instance_valid(landing_target) and not SoldierStateHelper.is_dead_soldier(landing_target) and soldier.has_method("move_to_target"):
		soldier.call("move_to_target", landing_target)
		if attacker_team == "enemy" and is_instance_valid(target_ship) and target_ship.has_method("get_team_tag") and target_ship.call("get_team_tag") == "player":
			if "chaos_duration_timer" in soldier:
				soldier.set("chaos_duration_timer", 0.0)
			if "chaos_tick_timer" in soldier:
				soldier.set("chaos_tick_timer", 1.0)


static func _apply_boarding_transfer_damage(soldier_id: int, target_ship_id: int, attacker_team: String) -> void:
	if attacker_team != "enemy":
		return
	var soldier := NodeContractHelper.get_instance_node(soldier_id)
	if not is_instance_valid(soldier):
		return
	var target_ship := NodeContractHelper.get_instance_node3d(target_ship_id)
	if not is_instance_valid(target_ship) or _get_ship_team_tag(target_ship) != "player":
		return
	var damage: float = maxf(0.0, float(target_ship.get_meta("enemy_boarding_transfer_damage", 0.0)))
	if damage <= 0.0:
		return
	if soldier.has_method("take_damage"):
		soldier.call("take_damage", damage, soldier.global_position, "boarding_resist")


static func _clamp_deck_landing_local(target_ship: Node3D, landing_local: Vector3) -> Vector3:
	var target_half_ext := _get_target_deck_half_extents(target_ship)
	return SoldierShipHelper.get_clamped_main_deck_local(
		target_ship,
		landing_local,
		BOARDING_LANDING_CLAMP_INSET,
		target_half_ext
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
		if not SoldierDeckZoneHelper.can_share_combat_zone(boarder, other):
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
