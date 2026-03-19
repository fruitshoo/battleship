extends RefCounted

static func add_stuck_object(ship, obj: Node3D, s_mult: float, t_mult: float) -> void:
	if not obj in ship.stuck_objects:
		ship.stuck_objects.append(obj)
		ship.speed_mult *= s_mult
		ship.turn_mult *= t_mult
		var tilt_dir = 1.0 if obj.global_position.x > ship.global_position.x else -1.0
		var new_tilt = deg_to_rad(randf_range(5.0, 10.0)) * tilt_dir
		ship.tilt_offset = clamp(ship.tilt_offset + new_tilt, -deg_to_rad(12.0), deg_to_rad(12.0))
		print("[Impact] 배에 물체가 박힘! (현재 속도 배율: %.2f, 선회 배율: %.2f, 최종 기울기: %.1f)" % [ship.speed_mult, ship.turn_mult, rad_to_deg(ship.tilt_offset)])
		if ship._cached_hud and ship._cached_hud.has_method("show_message"):
			ship._cached_hud.show_message("!! 기동성 저하 기동성 저하 !!", 2.0)

static func remove_stuck_object(ship, obj: Node3D, s_mult: float, t_mult: float) -> void:
	if obj in ship.stuck_objects:
		ship.stuck_objects.erase(obj)
		ship.speed_mult /= s_mult
		ship.turn_mult /= t_mult
		ship.speed_mult = min(1.0, ship.speed_mult)
		ship.turn_mult = min(1.0, ship.turn_mult)
		ship.tilt_offset *= 0.5
		if ship.stuck_objects.is_empty():
			ship.tilt_offset = 0.0
