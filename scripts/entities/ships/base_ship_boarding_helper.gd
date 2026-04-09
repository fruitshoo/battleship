extends RefCounted
class_name BaseShipBoardingHelper

static func process_boarding_common(ship, delta: float) -> void:
	if not is_instance_valid(ship.boarding_target):
		cancel_boarding(ship)
		return

	if ship.boarding_rope_hp <= 0:
		cancel_boarding(ship)
		return

	var target_pos = ship.boarding_target.global_position
	var dist = ship.global_position.distance_to(target_pos)

	if dist > ship.boarding_break_distance:
		print("[Boarding] 밧줄이 끊어졌습니다. 도선 중단.")
		cancel_boarding(ship)
		return

	if dist > ship.max_boarding_distance:
		ship.boarding_contact_timer = maxf(0.0, ship.boarding_contact_timer - delta * 2.0)
		ship.boarding_hook_timer = 0.0
		ship.boarding_secondary_rope_timer = 0.0
		if ship._initial_rope_deployed and dist > (ship.max_boarding_distance + 0.8):
			ship._clear_ropes()
			ship._initial_rope_deployed = false
			ship._full_rope_deployed = false
		return

	ship.boarding_contact_timer += delta
	if ship.boarding_contact_timer < ship.boarding_contact_grace_duration:
		return

	var stable_contact = ship._is_boarding_contact_stable()
	if not stable_contact:
		var force_hook_after = ship.boarding_contact_grace_duration + 1.2
		if ship.boarding_contact_timer < force_hook_after:
			ship.boarding_contact_timer = maxf(ship.boarding_contact_grace_duration * 0.6, ship.boarding_contact_timer - delta * 1.4)
			return

	ship.boarding_hook_timer += delta
	if not ship._initial_rope_deployed:
		if ship.boarding_hook_timer >= ship.boarding_hook_throw_delay:
			ship._spawn_ropes(ship.boarding_initial_rope_count)
			ship._initial_rope_deployed = true
			ship._full_rope_deployed = ship.boarding_initial_rope_count >= 2
			ship.boarding_secondary_rope_timer = 0.0
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

	if ship.boarding_prep_timer < ship.boarding_prep_duration:
		ship.boarding_prep_timer += delta
	else:
		ship.boarding_timer += delta
		var effective_interval: float = ship.get_effective_boarding_interval() if ship.has_method("get_effective_boarding_interval") else ship.boarding_interval
		if ship.boarding_timer >= effective_interval:
			ship.boarding_timer = 0.0
			transfer_one_soldier(ship)

	ship._update_ropes(delta)


static func cancel_boarding(ship) -> void:
	if is_instance_valid(ship.boarding_target) and ship.boarding_target.get("boarding_attacker") == ship:
		ship.boarding_target.set("boarding_attacker", null)
	ship._clear_ropes()
	ship.is_boarding = false
	ship.boarding_timer = 0.0
	ship.boarding_prep_timer = 0.0
	ship.boarding_contact_timer = 0.0
	ship.boarding_hook_timer = 0.0
	ship.boarding_secondary_rope_timer = 0.0
	ship._initial_rope_deployed = false
	ship._full_rope_deployed = false
	ship.boarding_rope_hp = ship.max_boarding_rope_hp


static func transfer_one_soldier(ship) -> void:
	if not is_instance_valid(ship.boarding_target):
		return

	var target_soldiers_node = ship.boarding_target.get_node_or_null("Soldiers")
	if not target_soldiers_node:
		target_soldiers_node = ship.boarding_target

	var team_prop = ship.get_team_tag() if ship.has_method("get_team_tag") else ("player" if "team" in ship and str(ship.get("team")) == "player" else "enemy")
	var defenders_alive = 0
	var attackers_on_target_deck = 0
	if target_soldiers_node:
		for child in target_soldiers_node.get_children():
			if child.has_method("is_dead") and child.is_dead():
				continue
			if child.has_method("get_team_tag") and child.get_team_tag() != team_prop:
				defenders_alive += 1
			else:
				attackers_on_target_deck += 1
	var max_attackers_during_contest: int = maxi(1, mini(2, defenders_alive))
	if defenders_alive > 0 and attackers_on_target_deck >= max_attackers_during_contest:
		return

	var s = null
	var soldiers_node = ship.get_node_or_null("Soldiers")
	if soldiers_node:
		var soldiers = soldiers_node.get_children()
		var enemy_count_on_deck = 0
		var ally_count_on_deck = 0
		for child in soldiers:
			if not (child.has_method("is_dead") and child.is_dead()):
				if child.has_method("get_team_tag") and child.get_team_tag() != team_prop:
					enemy_count_on_deck += 1
				else:
					ally_count_on_deck += 1

		if enemy_count_on_deck > 0 and ally_count_on_deck <= enemy_count_on_deck:
			return

		# 적 함선인 경우 최소한 한 명은 배를 지키기 위해 남겨둠
		if team_prop == "enemy" and ally_count_on_deck <= 1:
			return

		for child in soldiers:
			if not (child.has_method("is_dead") and child.is_dead()) and child.has_method("get_team_tag") and child.get_team_tag() == team_prop:
				s = child
				break

	if s:
		var start_global = s.global_position
		s.call_deferred("reparent", target_soldiers_node)

		var target_half_ext = Vector2(1.0, 1.5)
		if ship.boarding_target.has_method("get_deck_half_extents"):
			var ext = ship.boarding_target.call("get_deck_half_extents")
			if ext is Vector2 and ext.x > 0.01 and ext.y > 0.01:
				target_half_ext = ext
		var target_deck_h = ship.boarding_target.get("deck_height") if "deck_height" in ship.boarding_target else 0.5
		var jump_offset = Vector3(
			randf_range(-target_half_ext.x, target_half_ext.x),
			target_deck_h,
			randf_range(-target_half_ext.y, target_half_ext.y)
		)
		var end_global = ship.boarding_target.global_transform * jump_offset

		var tween = ship.create_tween()
		tween.set_parallel(true)
		tween.tween_property(s, "global_position:x", end_global.x, 0.5).set_trans(Tween.TRANS_LINEAR)
		tween.tween_property(s, "global_position:z", end_global.z, 0.5).set_trans(Tween.TRANS_LINEAR)

		var mid_y = max(start_global.y, end_global.y) + 2.0
		var y_tween = ship.create_tween()
		y_tween.tween_property(s, "global_position:y", mid_y, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		y_tween.tween_property(s, "global_position:y", end_global.y, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

		if s.has_method("set_team"):
			s.set_team(team_prop)

		s.set("owned_ship", ship.boarding_target)
		if team_prop == "enemy" and ship.boarding_target.has_method("get_team_tag") and ship.boarding_target.get_team_tag() == "player":
			s.set("boarder_explosion_timer", 8.0)

		if s.get("is_stationary"):
			s.set("is_stationary", false)

		print("[Action] 병사 1명 월선! (팀: %s, 대상: %s)" % [team_prop, ship.boarding_target.name])
	else:
		if ship.has_method("_become_derelict") and not ship.is_in_group("player"):
			print("[Status] 모든 병사 도선 완료. 무인선 상태로 표류합니다.")
			ship.call("_become_derelict")
		else:
			print("[Status] 도선할 병사가 더 이상 없습니다.")
			cancel_boarding(ship)
