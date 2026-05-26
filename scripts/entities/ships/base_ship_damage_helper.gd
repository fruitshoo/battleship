extends RefCounted
class_name BaseShipDamageHelper

const WoodSplinter = preload("res://scripts/effects/wood_splinter.gd")
const DEBUG_DAMAGE_LOGS := false
const DEFERRED_LETHAL_DAMAGE_META := "deferred_lethal_damage_pending"
const DEFERRED_LETHAL_ACTIVE_META := "deferred_lethal_damage_active"
const DEFERRED_LETHAL_PREVIOUS_NONBLOCKING_META := "deferred_lethal_previous_nonblocking"
const DEFERRED_LETHAL_DURATION := 0.18
const DEFERRED_LETHAL_MIN_HOLD_HP := 3.0
const DEFERRED_LETHAL_HOLD_HP_RATIO := 0.03


static func apply_hull_damage(ship, amount: float, hit_position: Vector3 = Vector3.ZERO, damage_source: String = "") -> void:
	if ship.is_sinking or ship.is_dying:
		return
	
	var final_damage := get_final_hull_damage(ship, amount, damage_source)
	_apply_final_hull_damage(ship, amount, final_damage, hit_position, damage_source, true)


static func _apply_final_hull_damage(ship, raw_amount: float, final_damage: float, hit_position: Vector3, damage_source: String, allow_deferred_lethal: bool) -> void:
	if ship.is_sinking or ship.is_dying:
		return
	var hp_before: float = ship.hull_hp
	var feedback_damage := final_damage
	var applied_damage := final_damage
	if allow_deferred_lethal:
		applied_damage = _prepare_deferred_lethal_damage(ship, final_damage, hit_position, damage_source)
	if applied_damage > 0.0:
		ship.hull_hp -= applied_damage
		ship._apply_sail_damage_from_hit(applied_damage, damage_source)
		ship._apply_rudder_damage_from_hit(applied_damage, hit_position, damage_source)
	
	_log_damage_if_enabled(ship, raw_amount, applied_damage, hp_before, damage_source)
	_sink_derelict_if_needed(ship, damage_source)
	_record_player_weapon_damage_if_needed(ship, damage_source, applied_damage)
	_spawn_damage_splinters_if_ready(ship, hit_position, maxf(applied_damage, feedback_damage))
			
	ship._flash_damage(maxf(applied_damage, feedback_damage))
	ship._trigger_anchor_impact_sway(maxf(applied_damage, feedback_damage), hit_position, damage_source)
	
	if ship.hull_hp <= 0:
		ship.die()


static func get_final_hull_damage(ship, amount: float, damage_source: String = "") -> float:
	var adjusted_amount := amount
	if ship.deck_is_contested and is_contested_hull_damage_source(damage_source):
		adjusted_amount *= ship.contested_hull_damage_multiplier
	if damage_source == "boarding_capture":
		return maxf(adjusted_amount, 1.0)
	return maxf(adjusted_amount - ship.hull_defense, 1.0)


static func is_contested_hull_damage_source(damage_source: String) -> bool:
	if damage_source.is_empty():
		return false
	if damage_source.begins_with("cannon") or damage_source.contains("cannon"):
		return true
	if damage_source.contains("ballista") or damage_source.contains("singigeon"):
		return true
	if damage_source.begins_with("janggun") or damage_source.contains("fire"):
		return true
	return false


static func _prepare_deferred_lethal_damage(ship, final_damage: float, hit_position: Vector3, damage_source: String) -> float:
	if not _should_defer_lethal_damage(ship, final_damage, damage_source):
		return final_damage
	var hold_hp := _get_deferred_lethal_hold_hp(ship)
	var immediate_damage := maxf(0.0, ship.hull_hp - hold_hp)
	var deferred_damage := maxf(0.0, final_damage - immediate_damage)
	if deferred_damage <= 0.0:
		return final_damage
	var pending := float(ship.get_meta(DEFERRED_LETHAL_DAMAGE_META, 0.0))
	ship.set_meta(DEFERRED_LETHAL_DAMAGE_META, pending + deferred_damage)
	_schedule_deferred_lethal_finish(ship, hit_position, damage_source)
	return immediate_damage


static func _should_defer_lethal_damage(ship, final_damage: float, damage_source: String) -> bool:
	if final_damage <= 0.0:
		return false
	if ship.get_meta(DEFERRED_LETHAL_ACTIVE_META, false) == true:
		return _is_deferred_lethal_damage_source(damage_source)
	if ship.get("is_derelict") == true:
		return false
	if not _is_deferred_lethal_damage_source(damage_source):
		return false
	return ship.hull_hp - final_damage <= 0.0


static func _is_deferred_lethal_damage_source(damage_source: String) -> bool:
	return damage_source == "ramming" or damage_source == "ramming_boost" or damage_source == "ship_collision"


static func _get_deferred_lethal_hold_hp(ship) -> float:
	var max_hull := maxf(float(ship.get("max_hull_hp")) if ship.get("max_hull_hp") != null else ship.hull_hp, 1.0)
	return minf(maxf(DEFERRED_LETHAL_MIN_HOLD_HP, max_hull * DEFERRED_LETHAL_HOLD_HP_RATIO), maxf(ship.hull_hp, 0.0))


static func _schedule_deferred_lethal_finish(ship, hit_position: Vector3, damage_source: String) -> void:
	if ship.get_meta(DEFERRED_LETHAL_ACTIVE_META, false) == true:
		return
	ship.set_meta(DEFERRED_LETHAL_ACTIVE_META, true)
	_begin_deferred_lethal_collapse_feedback(ship)
	if not ship.is_inside_tree():
		_finish_deferred_lethal_damage(ship, hit_position, damage_source)
		return
	var timer: SceneTreeTimer = ship.get_tree().create_timer(DEFERRED_LETHAL_DURATION)
	timer.timeout.connect(func() -> void:
		_finish_deferred_lethal_damage(ship, hit_position, damage_source)
	)


static func _begin_deferred_lethal_collapse_feedback(ship) -> void:
	if not is_instance_valid(ship):
		return
	ship.set_meta(DEFERRED_LETHAL_PREVIOUS_NONBLOCKING_META, ship.get_meta("derelict_nonblocking", false) == true)


static func _finish_deferred_lethal_damage(ship, hit_position: Vector3, damage_source: String) -> void:
	if not is_instance_valid(ship):
		return
	var pending := float(ship.get_meta(DEFERRED_LETHAL_DAMAGE_META, 0.0))
	ship.remove_meta(DEFERRED_LETHAL_DAMAGE_META)
	ship.remove_meta(DEFERRED_LETHAL_ACTIVE_META)
	if ship.get_meta(DEFERRED_LETHAL_PREVIOUS_NONBLOCKING_META, false) != true:
		ship.set_meta("derelict_nonblocking", false)
	ship.remove_meta(DEFERRED_LETHAL_PREVIOUS_NONBLOCKING_META)
	if pending <= 0.0 or ship.is_sinking or ship.is_dying:
		return
	_apply_final_hull_damage(ship, pending, pending, hit_position, damage_source, false)


static func _log_damage_if_enabled(ship, raw_amount: float, final_damage: float, hp_before: float, damage_source: String) -> void:
	if not DEBUG_DAMAGE_LOGS or not OS.is_debug_build():
		return
	var source_label: String = damage_source if not damage_source.is_empty() else "unknown"
	var ship_label: String = ship.name
	if not ship.get_ship_type_value().is_empty():
		ship_label += "/" + ship.get_ship_type_value()
	print("[DamageLog][%s][%s] source=%s raw=%.1f defense=%.1f final=%.1f hp=%.1f->%.1f" % [
		ship_label,
		ship.get_team_tag(),
		source_label,
		raw_amount,
		ship.hull_defense,
		final_damage,
		hp_before,
		ship.hull_hp,
	])


static func _sink_derelict_if_needed(ship, damage_source: String) -> void:
	var is_derelict_disposal_fire_pot: bool = damage_source == "fire_pot" and ship.get_meta("derelict_contact_ignition_started", false) == true
	if ship.is_derelict and not is_derelict_disposal_fire_pot and not damage_source.is_empty() and damage_source != "leak" and ship.has_method("_sink_derelict"):
		ship.call_deferred("_sink_derelict")


static func _record_player_weapon_damage_if_needed(ship, damage_source: String, final_damage: float) -> void:
	if damage_source.is_empty() or not ship.is_enemy_team():
		return
	if is_instance_valid(ship._cached_level_manager) and ship._cached_level_manager.has_method("add_player_weapon_damage"):
		ship._cached_level_manager.add_player_weapon_damage(damage_source, final_damage)


static func _spawn_damage_splinters_if_ready(ship, hit_position: Vector3, final_damage: float) -> void:
	if not ship.wood_splinter_scene:
		return
	var current_time := Time.get_ticks_msec() / 1000.0
	if current_time - ship._last_splinter_time <= 0.2:
		return
	ship._last_splinter_time = current_time
	var splinter_position := _get_splinter_position(ship, hit_position)
	WoodSplinter.spawn_burst(ship.get_tree(), ship.wood_splinter_scene, splinter_position, final_damage, splinter_position - ship.global_position)


static func _get_splinter_position(ship, hit_position: Vector3) -> Vector3:
	if hit_position != Vector3.ZERO:
		return hit_position + Vector3(0, 0.5, 0)
	return ship.global_position + Vector3(randf_range(-1, 1), 1.5, randf_range(-1, 1))
