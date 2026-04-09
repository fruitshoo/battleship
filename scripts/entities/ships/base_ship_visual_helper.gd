extends RefCounted
class_name BaseShipVisualHelper

const LevelManagerRegistry = preload("res://scripts/helpers/level_manager_registry.gd")
const NodeContractHelper = preload("res://scripts/helpers/node_contract_helper.gd")

static func cache_common_references(ship) -> void:
	if ship == null:
		return
	ship._cached_level_manager = LevelManagerRegistry.get_level_manager(ship.get_tree())

	if ship._cached_level_manager and "hud" in ship._cached_level_manager:
		ship._cached_hud = ship._cached_level_manager.hud

	ship._cached_audio_manager = ship.get_node_or_null("/root/AudioManager")
	ship._cached_environment_preset_manager = ship.get_tree().root.find_child("EnvironmentPresetManager", true, false)
	if is_instance_valid(ship._cached_environment_preset_manager) and ship._cached_environment_preset_manager.has_signal("preset_applied"):
		var cb = Callable(ship, "_on_environment_preset_applied")
		if not ship._cached_environment_preset_manager.is_connected("preset_applied", cb):
			ship._cached_environment_preset_manager.connect("preset_applied", cb)


static func on_environment_preset_applied(ship, _preset: int) -> void:
	if ship == null:
		return
	refresh_deck_light(ship)


static func is_clear_day_preset_active(ship) -> bool:
	if ship == null:
		return false
	if not ship.disable_deck_light_in_clear_day:
		return false
	if not is_instance_valid(ship._cached_environment_preset_manager):
		return false
	if ship._cached_environment_preset_manager.has_method("is_clear_day_active"):
		return ship._cached_environment_preset_manager.call("is_clear_day_active") == true
	if "current_preset" in ship._cached_environment_preset_manager:
		return int(ship._cached_environment_preset_manager.get("current_preset")) == 0
	return false


static func resolve_deck_light_parent(ship) -> Node3D:
	if ship == null:
		return null
	var hull_scene = ship.get_node_or_null("HullScene")
	if hull_scene is Node3D:
		return hull_scene as Node3D

	for child in ship.get_children():
		if child is Node3D and child.name.to_lower().contains("hull"):
			return child as Node3D

	return ship


static func refresh_deck_light(ship) -> void:
	if ship == null:
		return
	var should_enable = ship.enable_deck_light
	if should_enable and is_clear_day_preset_active(ship):
		should_enable = false
	if should_enable and ship.deck_light_player_only:
		var team_tag = NodeContractHelper.get_team_tag(ship)
		var is_player_controlled = NodeContractHelper.is_player_controlled_ship(ship)
		var is_player_tagged = team_tag == "player" or ship.is_in_group("player") or is_player_controlled
		should_enable = is_player_tagged

	if not should_enable:
		if is_instance_valid(ship.deck_light):
			ship.deck_light.queue_free()
			ship.deck_light = null
		return

	var light_parent = resolve_deck_light_parent(ship)
	if not is_instance_valid(ship.deck_light):
		ship.deck_light = OmniLight3D.new()
		ship.deck_light.name = "DeckLight"
		light_parent.add_child(ship.deck_light)
	elif ship.deck_light.get_parent() != light_parent:
		var old_parent = ship.deck_light.get_parent()
		if is_instance_valid(old_parent):
			old_parent.remove_child(ship.deck_light)
		light_parent.add_child(ship.deck_light)

	ship.deck_light.light_color = ship.deck_light_color
	ship.deck_light.light_energy = ship.deck_light_energy
	ship.deck_light.omni_range = ship.deck_light_range
	ship.deck_light.shadow_enabled = false
	ship.deck_light.position = Vector3(0.0, ship.deck_light_height, 0.0)


static func apply_bobbing_effect(ship) -> void:
	if ship == null:
		return
	if Engine.is_editor_hint():
		return

	var time = Time.get_ticks_msec() * 0.001
	var dt = ship.get_physics_process_delta_time()
	ship._wave_sample_timer = maxf(0.0, ship._wave_sample_timer - dt)

	if not is_instance_valid(ship._cached_ocean):
		var tree = ship.get_tree()
		if not tree:
			return
		var ocean = tree.root.find_child("Ocean", true, false)
		if ocean:
			ship._cached_ocean = ocean

	var wave_h = 0.0
	if is_instance_valid(ship._cached_ocean) and ship._cached_ocean.has_method("get_wave_height"):
		if ship._wave_sample_timer <= 0.0:
			ship._cached_wave_height = ship._cached_ocean.get_wave_height(ship.global_position)
			ship._wave_sample_timer = ship.wave_sample_interval
		wave_h = ship._cached_wave_height
	else:
		ship._cached_wave_height = 0.0

	var bob_offset = sin(time * ship.bobbing_speed) * ship.bobbing_amplitude * 0.2
	var target_y = ship.base_y + wave_h + bob_offset
	ship.position.y = lerp(ship.position.y, target_y, 3.0 * dt)

	var turn_factor = ship.rudder_angle / 45.0
	var speed_ratio = clamp(ship.current_speed / ship.max_speed, 0.0, 1.0)
	var target_centrifugal = deg_to_rad(-turn_factor * speed_ratio * 12.0)

	ship._centrifugal_tilt = lerp(ship._centrifugal_tilt, target_centrifugal, 2.5 * dt)
	ship.rotation.z = (sin(time * ship.bobbing_speed * 0.8) * ship.rocking_amplitude) + ship.tilt_offset + ship._centrifugal_tilt


static func update_sail_visual(ship) -> void:
	if ship == null:
		return
	var burn_ratio: float = 0.0
	if ship.has_meta("debug_sail_burn_override_active") and ship.get_meta("debug_sail_burn_override_active") == true:
		burn_ratio = clampf(float(ship.get_meta("debug_sail_burn_override_value", 0.0)), 0.0, 1.0)
	elif ship.is_burning:
		var fire_ratio: float = 0.0
		if "fire_threshold" in ship and float(ship.fire_threshold) > 0.0:
			fire_ratio = clampf(float(ship.fire_build_up) / float(ship.fire_threshold), 0.0, 1.0)
		# Burning ships should read clearly even before heavy sail holes appear.
		burn_ratio = maxf(pow(fire_ratio, 0.7), 0.62)
	for mast in ship.masts:
		if is_instance_valid(mast) and mast.has_method("set_sail_angle"):
			mast.set_sail_angle(ship.sail_angle)
		if is_instance_valid(mast) and mast.has_method("set_burn_amount"):
			mast.set_burn_amount(burn_ratio)


static func update_rudder_visual(ship) -> void:
	if ship == null:
		return
	if ship.rudder_visual:
		ship.rudder_visual.rotation.y = deg_to_rad(ship.rudder_angle)


static func set_wake_state(ship, active: bool, speed_ratio: float = 0.0, turn_ratio: float = 0.0, turbulence: float = 0.0) -> void:
	if ship == null:
		return
	if not is_instance_valid(ship.wake_trail):
		return
	if ship.wake_trail.has_method("set_wake_state"):
		ship.wake_trail.call("set_wake_state", active, speed_ratio, turn_ratio, turbulence)
	elif "emitting" in ship.wake_trail:
		ship.wake_trail.set("emitting", active)
