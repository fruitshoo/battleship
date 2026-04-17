extends "res://scripts/entities/ships/chaser_ship.gd"
class_name EnemyGunnerShip


func is_gunner_role() -> bool:
	return true


func can_board_targets() -> bool:
	return false


func can_use_fire_pot_attack() -> bool:
	return true


func get_preferred_engagement_range() -> float:
	return 14.0


func get_engagement_range_tolerance() -> float:
	return 2.5


func get_retreat_engagement_distance() -> float:
	return 8.5


func _apply_default_combat_profile_for_ship_type() -> void:
	super._apply_default_combat_profile_for_ship_type()
	_sync_combat_profile_from_role_accessors()
