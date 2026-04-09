extends RefCounted
class_name PreviewStateSnapshotHelper


static func format_yes_no(value: bool) -> String:
	return "Y" if value else "N"


static func planar_distance(a: Node3D, b: Node3D) -> float:
	if not is_instance_valid(a) or not is_instance_valid(b):
		return 0.0
	return Vector2(
		a.global_position.x - b.global_position.x,
		a.global_position.z - b.global_position.z
	).length()


static func build_firepot_text(has_target: bool, in_range: bool, has_tosser: bool, cooldown: float) -> String:
	return "target:%s range:%s tosser:%s cd:%.1f" % [
		format_yes_no(has_target),
		format_yes_no(in_range),
		format_yes_no(has_tosser),
		cooldown,
	]


static func build_boarding_navigation_text(mode: String, slot: String, side_value: float, is_boarding: bool) -> String:
	var side_text := "R" if side_value < -0.5 else ("L" if side_value > 0.5 else "-")
	return "mode:%s slot:%s side:%s board:%s" % [
		mode,
		slot,
		side_text,
		format_yes_no(is_boarding),
	]


static func build_enemy_role_text(is_gunner: bool, preferred_range: float, can_board: bool, can_use_fire_pot: bool) -> String:
	return "role:%s rng:%.1f board:%s pot:%s" % [
		"gunner" if is_gunner else "charger",
		preferred_range,
		format_yes_no(can_board),
		format_yes_no(can_use_fire_pot),
	]


static func build_boarding_preview_text(has_target: bool, distance_to_target: float, is_boarding: bool, prep_timer: float) -> String:
	return "target:%s dist:%.1f board:%s prep:%.1f" % [
		format_yes_no(has_target),
		distance_to_target,
		format_yes_no(is_boarding),
		prep_timer,
	]


static func build_cannon_player_text(range_value: float, active_cannons: int, total_cannons: int) -> String:
	return "range:%.1f active:%d/%d" % [range_value, active_cannons, total_cannons]


static func build_cannon_enemy_text(distance_to_target: float, range_value: float) -> String:
	var state_text := "IN" if distance_to_target <= range_value else "OUT"
	return "dist:%.1f range:%.1f %s" % [distance_to_target, range_value, state_text]
