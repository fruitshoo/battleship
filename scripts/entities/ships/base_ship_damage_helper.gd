extends RefCounted
class_name BaseShipDamageHelper

const WoodSplinter = preload("res://scripts/effects/wood_splinter.gd")
const DEBUG_DAMAGE_LOGS := false


static func apply_hull_damage(ship, amount: float, hit_position: Vector3 = Vector3.ZERO, damage_source: String = "") -> void:
	if ship.is_sinking or ship.is_dying:
		return
	
	var hp_before: float = ship.hull_hp
	var final_damage := get_final_hull_damage(ship, amount, damage_source)
	ship.hull_hp -= final_damage
	ship._apply_sail_damage_from_hit(final_damage, damage_source)
	ship._apply_rudder_damage_from_hit(final_damage, hit_position, damage_source)
	
	_log_damage_if_enabled(ship, amount, final_damage, hp_before, damage_source)
	_sink_derelict_if_needed(ship, damage_source)
	_record_player_weapon_damage_if_needed(ship, damage_source, final_damage)
	_spawn_damage_splinters_if_ready(ship, hit_position, final_damage)
			
	ship._flash_damage(final_damage)
	ship._trigger_anchor_impact_sway(final_damage, hit_position, damage_source)
	
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
