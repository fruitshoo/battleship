extends "res://scripts/entities/ships/chaser_ship.gd"
class_name EnemyMeleeShip


func is_gunner_role() -> bool:
	return false


func can_board_targets() -> bool:
	return true


func get_preferred_engagement_range() -> float:
	return 3.8


func get_engagement_range_tolerance() -> float:
	return 0.8


func get_retreat_engagement_distance() -> float:
	return 3.0


func _apply_default_combat_profile_for_ship_type() -> void:
	super._apply_default_combat_profile_for_ship_type()
	_sync_combat_profile_from_role_accessors()
