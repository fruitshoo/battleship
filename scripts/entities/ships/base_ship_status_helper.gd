extends RefCounted
class_name BaseShipStatusHelper

const EntityRegistry = preload("res://scripts/helpers/entity_registry.gd")
const FIRE_CRACKLE_STREAM: AudioStream = preload("res://assets/audio/sfx/sfx_fire_crackling.ogg")
const SUPPORT_RESCUE_BOARDING_PURPOSE := "support_rescue_boarding"

static func update_fire_effect(ship) -> void:
	if (ship.is_burning or ship.is_derelict) and not ship.is_sinking and not ship.is_dying:
		if not is_instance_valid(ship._fire_instance):
			ship._fire_instance = ship.fire_effect_scene.instantiate() as Node3D
			ship.add_child(ship._fire_instance)
			ship._fire_instance.position = ship.fire_effect_offset
			set_fire_emitting(ship, true)
		else:
			set_fire_emitting(ship, true)
	else:
		if is_instance_valid(ship._fire_instance):
			set_fire_emitting(ship, false)


static func set_fire_emitting(ship, active: bool) -> void:
	if not is_instance_valid(ship._fire_instance):
		return
	var flame = ship._fire_instance.get_node_or_null("FlameParticles") as GPUParticles3D
	var smoke = ship._fire_instance.get_node_or_null("SmokeParticles") as GPUParticles3D
	var crackle = ship._fire_instance.get_node_or_null("CracklePlayer") as AudioStreamPlayer3D
	if flame:
		flame.emitting = active
	if smoke:
		smoke.emitting = active
	if crackle:
		if crackle.stream == null:
			crackle.stream = FIRE_CRACKLE_STREAM
		var should_play_crackle: bool = active and ship.is_burning
		if should_play_crackle:
			if not crackle.playing:
				crackle.play()
		elif crackle.playing:
			crackle.stop()


static func check_derelict_status(ship) -> void:
	if ship.is_derelict or ship.is_dying or ship.is_sinking:
		return

	var ship_team: String = ship.get_team_tag() if ship.has_method("get_team_tag") else str(ship.get("team"))
	var all_crew_dead = true
	var soldiers_node = ship.get_node_or_null("Soldiers")
	if soldiers_node:
		for child in EntityRegistry.get_soldiers_by_ship(ship):
			var child_team: String = child.get_team_tag() if child.has_method("get_team_tag") else str(child.get("team"))
			if child_team != ship_team:
				continue
			if not child.has_method("is_dead") or not child.is_dead():
				all_crew_dead = false
				break

	if all_crew_dead:
		var all_soldiers = EntityRegistry.get_soldiers()
		for s in all_soldiers:
			var soldier_team: String = s.get_team_tag() if s.has_method("get_team_tag") else str(s.get("team"))
			if soldier_team != ship_team:
				continue
			if s.get("home_ship") == ship and (not s.has_method("is_dead") or not s.is_dead()):
				all_crew_dead = false
				break

	if all_crew_dead and ship.has_method("_become_derelict"):
		if ship.get_meta("support_fleet_ship", false) == true:
			return
		ship.call("_become_derelict")


static func update_boarding_state(ship, delta: float) -> void:
	if ship.is_sinking or ship.is_dying:
		ship.deck_is_contested = false
		ship.deck_is_overrun = false
		ship.deck_friendly_crew_count = 0
		ship.deck_hostile_boarder_count = 0
		ship.boarding_capture_progress = 0.0
		ship._deck_overrun_announced = false
		return

	var ship_team: String = ship.get_team_tag() if ship.has_method("get_team_tag") else "enemy"
	var friendly_count: int = 0
	var hostile_count: int = 0
	for child in EntityRegistry.get_soldiers_by_ship(ship):
		if child.has_method("is_dead") and child.is_dead():
			continue
		if child.has_method("get_team_tag") and child.get_team_tag() == ship_team:
			friendly_count += 1
		else:
			hostile_count += 1

	var contested: bool = hostile_count > 0
	var overrun: bool = hostile_count > 0 and friendly_count <= 0
	var was_contested: bool = ship.get_meta("boarding_feedback_contested", false) == true
	var was_overrun: bool = ship.get_meta("boarding_feedback_overrun", false) == true
	ship.deck_friendly_crew_count = friendly_count
	ship.deck_hostile_boarder_count = hostile_count
	ship.deck_is_contested = contested
	ship.deck_is_overrun = overrun
	ship.set_meta("boarding_feedback_contested", contested)
	ship.set_meta("boarding_feedback_overrun", overrun)

	if overrun:
		var attacker_ship: Node = ship.get_boarding_attacker_ship() if ship.has_method("get_boarding_attacker_ship") else null
		if not is_instance_valid(attacker_ship):
			attacker_ship = _find_attacker_ship_from_boarders(ship, ship_team)
			if is_instance_valid(attacker_ship) and ship.has_method("set_boarding_attacker_ship"):
				ship.call("set_boarding_attacker_ship", attacker_ship)
		var effective_capture_duration: float = ship.boarding_capture_duration
		if ship.has_method("get_effective_boarding_capture_duration"):
			effective_capture_duration = float(ship.call("get_effective_boarding_capture_duration", attacker_ship))
		var support_rescue_active: bool = ship_team == "player" and _is_support_rescue_boarding_active(ship)
		if not support_rescue_active:
			ship.boarding_capture_progress = minf(effective_capture_duration, ship.boarding_capture_progress + delta)
		if ship_team == "player" and not ship._deck_overrun_announced:
			ship._deck_overrun_announced = true
			if is_instance_valid(ship._cached_hud) and ship._cached_hud.has_method("show_message"):
				ship._cached_hud.show_message("적이 갑판을 장악했습니다!", 1.75)
		elif ship_team != "player" and not was_overrun and is_instance_valid(attacker_ship):
			var attacker_team: String = attacker_ship.get_team_tag() if attacker_ship.has_method("get_team_tag") else str(attacker_ship.get("team"))
			if attacker_team == "player" and is_instance_valid(ship._cached_hud) and ship._cached_hud.has_method("show_message"):
				ship._cached_hud.show_message("월선 성공! 적 갑판 장악 중", 1.65)
		if not support_rescue_active and ship.boarding_capture_progress >= effective_capture_duration:
			_resolve_boarding_capture_tick(ship, ship_team, attacker_ship)
	elif contested:
		ship.boarding_capture_progress = move_toward(ship.boarding_capture_progress, 0.0, delta * 0.7)
		if ship_team != "player" and not was_contested:
			var attacker_ship: Node = ship.get_boarding_attacker_ship() if ship.has_method("get_boarding_attacker_ship") else null
			if is_instance_valid(attacker_ship):
				var attacker_team: String = attacker_ship.get_team_tag() if attacker_ship.has_method("get_team_tag") else str(attacker_ship.get("team"))
				if attacker_team == "player" and is_instance_valid(ship._cached_hud) and ship._cached_hud.has_method("show_message"):
					ship._cached_hud.show_message("월선 성공! 갑판 전투 시작", 1.5)
		if ship._deck_overrun_announced and ship_team == "player":
			ship._deck_overrun_announced = false
			if is_instance_valid(ship._cached_hud) and ship._cached_hud.has_method("show_message"):
				ship._cached_hud.show_message("갑판 방어를 회복했습니다.", 1.5)
	else:
		ship.boarding_capture_progress = 0.0
		ship._deck_overrun_announced = false


static func _find_attacker_ship_from_boarders(ship, ship_team: String) -> Node:
	for child in EntityRegistry.get_soldiers_by_ship(ship):
		if not is_instance_valid(child):
			continue
		if child.has_method("is_dead") and child.is_dead():
			continue
		var child_team: String = child.get_team_tag() if child.has_method("get_team_tag") else str(child.get("team"))
		if child_team == ship_team:
			continue
		var home_ship: Variant = child.get("home_ship") if child.get("home_ship") != null else null
		if is_instance_valid(home_ship) and home_ship is Node:
			return home_ship as Node
	return null


static func _is_support_rescue_boarding_active(player_ship: Node) -> bool:
	if not is_instance_valid(player_ship):
		return false
	for support_ship in EntityRegistry.get_ships_by_team("player"):
		if not is_instance_valid(support_ship) or support_ship == player_ship:
			continue
		if support_ship.get_meta("support_fleet_ship", false) != true:
			continue
		if support_ship.get("is_boarding") != true:
			continue
		if support_ship.get("boarding_target") != player_ship:
			continue
		if str(support_ship.get_meta("boarding_purpose", "")) != SUPPORT_RESCUE_BOARDING_PURPOSE:
			continue
		return true
	return false


static func _resolve_boarding_capture_tick(ship, ship_team: String, attacker_ship: Node) -> void:
	ship.boarding_capture_progress = 0.0
	var capture_tick_damage: float = maxf(float(ship.boarding_capture_damage_tick), float(ship.max_hull_hp) * 0.12)
	if ship_team == "player":
		ship.take_damage(capture_tick_damage, ship.global_position, "boarding_capture")
		return
	if not is_instance_valid(attacker_ship):
		return
	var attacker_team: String = attacker_ship.get_team_tag() if attacker_ship.has_method("get_team_tag") else str(attacker_ship.get("team"))
	if attacker_team != "player":
		return
	if ship.has_method("capture_ship"):
		ship.call_deferred("capture_ship")
		return
	if ship.has_method("take_damage"):
		ship.take_damage(capture_tick_damage, ship.global_position, "boarding_capture")
	if is_instance_valid(ship._cached_hud) and ship._cached_hud.has_method("show_message"):
		ship._cached_hud.show_message("갑판 장악! 적선 선체를 파괴 중", 1.5)


static func take_fire_damage(ship, duration: float) -> void:
	if ship.is_burning:
		ship.burn_timer = max(ship.burn_timer, duration)
		return

	ship.fire_build_up += duration * 6.0
	if ship.fire_build_up >= ship.fire_threshold:
		ship.is_burning = true
		ship.fire_build_up = ship.fire_threshold
		ship.burn_timer = duration
		print("[Status] 배에 불이 붙었습니다!")


static func update_burning_status(ship, delta: float) -> void:
	if ship.is_burning:
		ship.hull_hp = move_toward(ship.hull_hp, 0, 2.0 * delta)
		# Let burning sails visibly deteriorate over time without jumping straight to holes.
		for mast in ship.masts:
			if is_instance_valid(mast) and mast.has_method("add_sail_damage"):
				mast.add_sail_damage(delta * 0.04)
		if ship.hull_hp <= 0:
			ship.die()

		ship.burn_timer -= delta
		if ship.burn_timer <= 0:
			ship.is_burning = false
			ship.fire_build_up = 0.0
	else:
		if ship.fire_build_up > 0:
			ship.fire_build_up = move_toward(ship.fire_build_up, 0, 15.0 * delta)


static func update_hull_regeneration(ship, delta: float) -> void:
	if ship.is_sinking or ship.is_dying or ship.hull_regen_rate <= 0:
		return
	if ship.deck_is_contested or ship.deck_is_overrun or ship.deck_hostile_boarder_count > 0:
		return

	if ship.hull_hp < ship.max_hull_hp:
		ship.hull_hp = move_toward(ship.hull_hp, ship.max_hull_hp, ship.hull_regen_rate * delta)
