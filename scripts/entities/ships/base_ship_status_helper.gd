extends RefCounted
class_name BaseShipStatusHelper

const FIRE_CRACKLE_STREAM: AudioStream = preload("res://assets/audio/sfx/sfx_fire_crackling.ogg")

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

	var all_crew_dead = true
	var soldiers_node = ship.get_node_or_null("Soldiers")
	if soldiers_node:
		for child in soldiers_node.get_children():
			if child.get("current_state") != 4:
				all_crew_dead = false
				break

	if all_crew_dead:
		var all_soldiers = ship.SceneGroupCache.get_nodes(ship.get_tree(), "soldiers")
		for s in all_soldiers:
			if s.get("home_ship") == ship and s.get("current_state") != 4:
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

	var ship_team_variant: Variant = ship.get("team")
	var ship_team: String = "enemy"
	if ship_team_variant != null:
		ship_team = String(ship_team_variant)
	var soldiers_node = ship.get_node_or_null("Soldiers")
	var friendly_count: int = 0
	var hostile_count: int = 0
	if soldiers_node:
		for child in soldiers_node.get_children():
			if child.get("current_state") == 4:
				continue
			if String(child.get("team")) == ship_team:
				friendly_count += 1
			else:
				hostile_count += 1

	var contested: bool = hostile_count > 0
	var overrun: bool = hostile_count > 0 and friendly_count <= 0
	ship.deck_friendly_crew_count = friendly_count
	ship.deck_hostile_boarder_count = hostile_count
	ship.deck_is_contested = contested
	ship.deck_is_overrun = overrun

	if overrun:
		ship.boarding_capture_progress = minf(float(ship.boarding_capture_duration), ship.boarding_capture_progress + delta)
		if ship_team == "player" and not ship._deck_overrun_announced:
			ship._deck_overrun_announced = true
			if is_instance_valid(ship._cached_hud) and ship._cached_hud.has_method("show_message"):
				ship._cached_hud.show_message("적이 갑판을 장악했습니다!", 1.75)
		if ship_team == "player" and ship.boarding_capture_progress >= float(ship.boarding_capture_duration):
			ship.boarding_capture_progress = 0.0
			var capture_tick_damage: float = maxf(float(ship.boarding_capture_damage_tick), float(ship.max_hull_hp) * 0.12)
			ship.take_damage(capture_tick_damage, ship.global_position, "boarding_capture")
	elif contested:
		ship.boarding_capture_progress = move_toward(ship.boarding_capture_progress, 0.0, delta * 0.7)
		if ship._deck_overrun_announced and ship_team == "player":
			ship._deck_overrun_announced = false
			if is_instance_valid(ship._cached_hud) and ship._cached_hud.has_method("show_message"):
				ship._cached_hud.show_message("갑판 방어를 회복했습니다.", 1.5)
	else:
		ship.boarding_capture_progress = 0.0
		ship._deck_overrun_announced = false


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

	if ship.hull_hp < ship.max_hull_hp:
		ship.hull_hp = move_toward(ship.hull_hp, ship.max_hull_hp, ship.hull_regen_rate * delta)
