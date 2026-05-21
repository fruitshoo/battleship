extends RefCounted
class_name BaseShipStatusHelper

const PlayerFleetRoleHelper = preload("res://scripts/entities/ships/player_fleet_role_helper.gd")

const FIRE_CRACKLE_STREAM: AudioStream = preload("res://assets/audio/sfx/sfx_fire_crackling.ogg")
const FIRE_EFFECT_RANDOM_OFFSET_META := "fire_effect_random_offset"
const FIRE_EFFECT_RANDOM_SCALE_META := "fire_effect_random_scale"
const BURNING_CREW_DAMAGE_TIMER_META := "burning_crew_damage_timer"

static func update_fire_effect(ship) -> void:
	if ship.is_burning and not ship.is_dying:
		if not is_instance_valid(ship._fire_instance):
			ship._fire_instance = ship.fire_effect_scene.instantiate() as Node3D
			ship.add_child(ship._fire_instance)
			_apply_fire_effect_transform(ship)
			set_fire_emitting(ship, true)
		else:
			_apply_fire_effect_transform(ship)
			set_fire_emitting(ship, true)
	else:
		if is_instance_valid(ship._fire_instance):
			set_fire_emitting(ship, false)
		_clear_fire_effect_random_transform(ship)


static func clear_fire_effect(ship) -> void:
	if "is_burning" in ship:
		ship.is_burning = false
	if "burn_timer" in ship:
		ship.burn_timer = 0.0
	if "fire_build_up" in ship:
		ship.fire_build_up = 0.0
	_clear_burning_crew_damage_timer(ship)
	if is_instance_valid(ship._fire_instance):
		set_fire_emitting(ship, false)
	_clear_fire_effect_random_transform(ship)


static func _apply_fire_effect_transform(ship) -> void:
	if not is_instance_valid(ship._fire_instance):
		return
	ship._fire_instance.position = ship.fire_effect_offset + _get_fire_effect_random_offset(ship)
	var effect_scale := 1.0
	if "fire_effect_scale" in ship:
		effect_scale = maxf(0.05, float(ship.fire_effect_scale))
	ship._fire_instance.scale = Vector3.ONE * effect_scale * _get_fire_effect_random_scale(ship)


static func _get_fire_effect_random_offset(ship) -> Vector3:
	if ship.has_meta(FIRE_EFFECT_RANDOM_OFFSET_META):
		return ship.get_meta(FIRE_EFFECT_RANDOM_OFFSET_META) as Vector3
	var extents := Vector3.ZERO
	if "fire_effect_offset_randomness" in ship:
		extents = ship.fire_effect_offset_randomness
	var offset := Vector3(
		randf_range(-absf(extents.x), absf(extents.x)),
		randf_range(-absf(extents.y), absf(extents.y)),
		randf_range(-absf(extents.z), absf(extents.z))
	)
	ship.set_meta(FIRE_EFFECT_RANDOM_OFFSET_META, offset)
	return offset


static func _get_fire_effect_random_scale(ship) -> float:
	if ship.has_meta(FIRE_EFFECT_RANDOM_SCALE_META):
		return float(ship.get_meta(FIRE_EFFECT_RANDOM_SCALE_META))
	var randomness := 0.0
	if "fire_effect_scale_randomness" in ship:
		randomness = clampf(float(ship.fire_effect_scale_randomness), 0.0, 0.95)
	var scale := randf_range(1.0 - randomness, 1.0 + randomness)
	ship.set_meta(FIRE_EFFECT_RANDOM_SCALE_META, scale)
	return scale


static func _clear_fire_effect_random_transform(ship) -> void:
	if ship.has_meta(FIRE_EFFECT_RANDOM_OFFSET_META):
		ship.remove_meta(FIRE_EFFECT_RANDOM_OFFSET_META)
	if ship.has_meta(FIRE_EFFECT_RANDOM_SCALE_META):
		ship.remove_meta(FIRE_EFFECT_RANDOM_SCALE_META)


static func set_fire_emitting(ship, active: bool) -> void:
	if not is_instance_valid(ship._fire_instance):
		return
	if ship._fire_instance.has_method("set_fire_active"):
		ship._fire_instance.call("set_fire_active", active, ship.is_burning)
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
	for child in EntityRegistry.get_soldiers_by_ship(ship):
		var child_team: String = child.get_team_tag() if child.has_method("get_team_tag") else str(child.get("team"))
		if child_team != ship_team:
			continue
		if SoldierStateHelper.is_alive_soldier(child):
			all_crew_dead = false
			break

	if all_crew_dead:
		# 폐선은 빈 갑판이 아니라 원소속 승조원 전체 전멸로 판단한다.
		var all_soldiers = EntityRegistry.get_soldiers()
		for s in all_soldiers:
			var soldier_team: String = s.get_team_tag() if s.has_method("get_team_tag") else str(s.get("team"))
			if soldier_team != ship_team:
				continue
			if s.get("home_ship") == ship and SoldierStateHelper.is_alive_soldier(s):
				all_crew_dead = false
				break

	if all_crew_dead and ship.has_method("_become_derelict"):
		if PlayerFleetRoleHelper.is_support_ship(ship):
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
		if SoldierStateHelper.is_dead_soldier(child):
			continue
		if child.has_method("get_team_tag") and child.get_team_tag() == ship_team:
			friendly_count += 1
		else:
			hostile_count += 1

	var contested: bool = hostile_count > 0
	var overrun: bool = hostile_count > 0 and friendly_count <= 0
	var was_contested: bool = ship.get_meta("boarding_feedback_contested", false) == true
	var was_overrun: bool = ship.get_meta("boarding_feedback_overrun", false) == true
	var had_boarding_feedback: bool = ship.has_meta("boarding_feedback_hostile_count")
	var previous_hostile_count: int = int(ship.get_meta("boarding_feedback_hostile_count", hostile_count))
	ship.deck_friendly_crew_count = friendly_count
	ship.deck_hostile_boarder_count = hostile_count
	ship.deck_is_contested = contested
	ship.deck_is_overrun = overrun
	ship.set_meta("boarding_feedback_contested", contested)
	ship.set_meta("boarding_feedback_overrun", overrun)
	ship.set_meta("boarding_feedback_hostile_count", hostile_count)
	if had_boarding_feedback and (was_contested != contested or was_overrun != overrun or previous_hostile_count != hostile_count):
		for soldier in EntityRegistry.get_soldiers_by_ship(ship):
			if not is_instance_valid(soldier):
				continue
			if soldier.has_method("notify_ai_event"):
				soldier.call("notify_ai_event", "boarding_state_changed")

	if overrun:
		var attacker_ship: Node = ship.get_boarding_attacker_ship() if ship.has_method("get_boarding_attacker_ship") else null
		if not is_instance_valid(attacker_ship):
			attacker_ship = _find_attacker_ship_from_boarders(ship, ship_team)
			if is_instance_valid(attacker_ship) and ship.has_method("set_boarding_attacker_ship"):
				ship.call("set_boarding_attacker_ship", attacker_ship)
		var effective_capture_duration: float = ship.boarding_capture_duration
		if ship.has_method("get_effective_boarding_capture_duration"):
			effective_capture_duration = float(ship.call("get_effective_boarding_capture_duration", attacker_ship))
		var support_rescue_active: bool = ship_team == "player" and SupportBoardingHelper.is_support_rescue_boarding_active(ship)
		if ship_team != "player" and SupportBoardingHelper.finish_support_attack_boarding_if_safe(ship, ship_team):
			return
		if ship_team == "player" and ship.has_method("trigger_boarding_overrun_game_over"):
			if not ship._deck_overrun_announced:
				ship._deck_overrun_announced = true
				if is_instance_valid(ship._cached_hud) and ship._cached_hud.has_method("show_message"):
					ship._cached_hud.show_message("적이 갑판을 장악했습니다!", 1.75)
			ship.call("trigger_boarding_overrun_game_over")
			return
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
		if ship_team == "player":
			SupportBoardingHelper.finish_support_rescue_boarding_if_safe(ship)

static func _find_attacker_ship_from_boarders(ship, ship_team: String) -> Node:
	for child in EntityRegistry.get_soldiers_by_ship(ship):
		if not is_instance_valid(child):
			continue
		if SoldierStateHelper.is_dead_soldier(child):
			continue
		var child_team: String = child.get_team_tag() if child.has_method("get_team_tag") else str(child.get("team"))
		if child_team == ship_team:
			continue
		var home_ship: Variant = child.get("home_ship") if child.get("home_ship") != null else null
		if is_instance_valid(home_ship) and home_ship is Node:
			return home_ship as Node
	return null


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


static func take_fire_damage(ship, dps: float, duration: float) -> void:
	if ship.is_burning:
		ship.burn_timer = max(ship.burn_timer, duration)
		return

	var chance_per_point := 0.012
	if "fire_damage_ignition_chance_per_point" in ship:
		chance_per_point = maxf(0.0, float(ship.fire_damage_ignition_chance_per_point))
	var ignition_chance := clampf(maxf(dps, 0.0) * maxf(duration, 0.0) * chance_per_point, 0.0, 0.65)
	try_ignite_fire(ship, ignition_chance, duration)


static func try_ignite_fire(ship, chance: float, duration: float) -> bool:
	if ship == null or ship.is_sinking or ship.is_dying:
		return false
	if ship.is_burning:
		ship.burn_timer = maxf(ship.burn_timer, duration)
		return true
	var ignition_chance := clampf(chance, 0.0, 1.0)
	if randf() > ignition_chance:
		return false
	ship.is_burning = true
	ship.fire_build_up = ship.fire_threshold
	ship.burn_timer = maxf(duration, 0.1)
	print("[Status] 배에 불이 붙었습니다!")
	return true


static func update_burning_status(ship, delta: float) -> void:
	if ship.is_burning:
		var burn_damage_per_second := 2.0
		if "burn_hull_damage_per_second" in ship:
			burn_damage_per_second = maxf(0.0, float(ship.burn_hull_damage_per_second))
		burn_damage_per_second *= get_furled_sail_fire_damage_multiplier(ship)
		ship.hull_hp = move_toward(ship.hull_hp, 0, burn_damage_per_second * delta)
		if ship.hull_hp <= 0:
			ship.die()

		_apply_burning_crew_damage(ship, delta)

		ship.burn_timer -= delta
		if ship.burn_timer <= 0:
			ship.is_burning = false
			ship.fire_build_up = 0.0
			_clear_burning_crew_damage_timer(ship)
	else:
		_clear_burning_crew_damage_timer(ship)
		if ship.fire_build_up > 0:
			ship.fire_build_up = move_toward(ship.fire_build_up, 0, 15.0 * delta)


static func get_furled_sail_fire_damage_multiplier(ship) -> float:
	if "sail_furled" in ship and ship.get("sail_furled") == true:
		if "furled_sail_fire_damage_multiplier" in ship and ship.get("furled_sail_fire_damage_multiplier") != null:
			return clampf(float(ship.get("furled_sail_fire_damage_multiplier")), 0.0, 1.0)
	return 1.0


static func _apply_burning_crew_damage(ship, delta: float) -> void:
	var damage_per_second := 1.0
	if "burning_crew_damage_per_second" in ship:
		damage_per_second = maxf(0.0, float(ship.burning_crew_damage_per_second))
	if damage_per_second <= 0.0:
		return
	var tick_interval := 1.0
	if "burning_crew_damage_tick_interval" in ship:
		tick_interval = clampf(float(ship.burning_crew_damage_tick_interval), 0.25, 3.0)
	var timer := float(ship.get_meta(BURNING_CREW_DAMAGE_TIMER_META, tick_interval))
	timer -= delta
	if timer > 0.0:
		ship.set_meta(BURNING_CREW_DAMAGE_TIMER_META, timer)
		return
	var tick_damage := damage_per_second * tick_interval
	ship.set_meta(BURNING_CREW_DAMAGE_TIMER_META, timer + tick_interval)
	for soldier in EntityRegistry.get_soldiers_by_ship(ship):
		if not is_instance_valid(soldier):
			continue
		if SoldierStateHelper.is_dead_soldier(soldier):
			continue
		if not soldier.has_method("take_damage"):
			continue
		soldier.take_damage(tick_damage, soldier.global_position, "fire")


static func _clear_burning_crew_damage_timer(ship) -> void:
	if ship != null and ship.has_meta(BURNING_CREW_DAMAGE_TIMER_META):
		ship.remove_meta(BURNING_CREW_DAMAGE_TIMER_META)


static func update_hull_regeneration(ship, delta: float) -> void:
	if ship.is_sinking or ship.is_dying or ship.hull_regen_rate <= 0:
		return
	if ship.deck_is_contested or ship.deck_is_overrun or ship.deck_hostile_boarder_count > 0:
		return

	if ship.hull_hp < ship.max_hull_hp:
		ship.hull_hp = move_toward(ship.hull_hp, ship.max_hull_hp, ship.hull_regen_rate * delta)


static func mark_rigging_damage_for_repair(ship) -> void:
	if ship == null:
		return
	ship._rigging_repair_cooldown = 0.0
	ship._rigging_repair_feedback_pending = false
	ship._rigging_repair_active_feedback_shown = false
	ship._rigging_repair_complete_feedback_shown = false


static func update_rigging_recovery(ship, delta: float) -> void:
	if ship == null or delta <= 0.0:
		return
	mark_rigging_damage_for_repair(ship)


static func _has_repairable_rigging_damage(_ship) -> bool:
	return false


static func _repair_rudder_to_field_target(ship, delta: float) -> void:
	if ship.rudder_max_health <= 0.0 or ship.rudder_field_repair_rate <= 0.0:
		return
	var target_health: float = ship.rudder_max_health * clampf(float(ship.rigging_repair_target_ratio), 0.0, 1.0)
	if ship.rudder_health >= target_health:
		return
	ship.rudder_health = minf(target_health, ship.rudder_health + ship.rudder_field_repair_rate * delta)
	if ship.rudder_health > ship.rudder_max_health * ship.rudder_critical_threshold:
		ship._rudder_critical_announced = false


static func _repair_sails_to_field_target(ship, delta: float) -> void:
	if ship.sail_field_repair_rate <= 0.0:
		return
	var max_field_damage: float = 1.0 - clampf(float(ship.rigging_repair_target_ratio), 0.0, 1.0)
	for mast in ship.masts:
		if not is_instance_valid(mast) or not mast.has_method("get_sail_damage") or not mast.has_method("repair_sail_damage"):
			continue
		var current_damage: float = float(mast.call("get_sail_damage"))
		if current_damage <= max_field_damage:
			continue
		var repair_amount: float = minf(ship.sail_field_repair_rate * delta, current_damage - max_field_damage)
		mast.call("repair_sail_damage", repair_amount)


static func _show_rigging_repair_active_feedback_if_needed(ship) -> void:
	ship._rigging_repair_active_feedback_shown = false


static func _show_rigging_repair_complete_feedback_if_needed(ship) -> void:
	ship._rigging_repair_feedback_pending = false
	ship._rigging_repair_complete_feedback_shown = false


static func _show_rigging_repair_feedback(ship, message: String, duration: float) -> void:
	if not _should_show_rigging_repair_feedback(ship):
		return
	if is_instance_valid(ship._cached_hud) and ship._cached_hud.has_method("show_message"):
		ship._cached_hud.show_message(message, duration)


static func _should_show_rigging_repair_feedback(ship) -> bool:
	if ship == null:
		return false
	if ship.get_meta("show_rigging_repair_feedback", false) == true:
		return true
	if ship.has_method("is_player_controlled_ship"):
		return ship.call("is_player_controlled_ship") == true
	return ship.get("is_player_controlled") == true if ship.get("is_player_controlled") != null else false
