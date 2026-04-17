extends RefCounted
class_name SoldierBoardingHelper

const SoldierShipHelper = preload("res://scripts/entities/soldiers/soldier_ship_helper.gd")

const BOARDING_LANDING_INSET := 0.45


static func try_evacuate_to_home(soldier) -> void:
	if not is_instance_valid(soldier.home_ship) or soldier.home_ship == soldier.owned_ship:
		return
	if not has_active_boarding_link_between(soldier.owned_ship, soldier.home_ship):
		return

	var dist: float = soldier.global_position.distance_to(soldier.home_ship.global_position)
	if dist < 12.0:
		jump_to_ship(soldier, soldier.home_ship)


static func jump_to_ship(soldier, target_ship: Node3D, is_capture_attempt: bool = false) -> void:
	var target_soldiers: Node = target_ship.get_node_or_null("Soldiers")
	if not target_soldiers:
		target_soldiers = target_ship

	var transfer_status: String = "returning" if is_instance_valid(soldier.home_ship) and target_ship == soldier.home_ship and soldier.owned_ship != target_ship else "boarding"
	_begin_boarding_jump_pose(soldier, transfer_status)
	var d_h: float = target_ship.get("deck_height") if "deck_height" in target_ship else 0.4
	var target_half_ext: Vector2 = SoldierShipHelper.get_ship_deck_half_extents(soldier, target_ship)
	var jump_offset := _get_nearest_deck_landing_local(target_ship, soldier.global_position, target_half_ext, d_h)

	var start_glob: Vector3 = soldier.global_position
	soldier.reparent(target_soldiers)
	soldier.global_position = start_glob

	soldier.owned_ship = target_ship

	var start_local_pos: Vector3 = soldier.position
	var start_local_y: float = start_local_pos.y
	var horiz_dist: float = Vector2(start_local_pos.x - jump_offset.x, start_local_pos.z - jump_offset.z).length()
	var jump_height: float = maxf(2.5, horiz_dist * 0.4)
	var travel_time: float = clampf(horiz_dist / 15.0, 0.6, 1.0)

	var tween = soldier.create_tween()
	tween.set_parallel(true)
	tween.tween_property(soldier, "position:x", jump_offset.x, travel_time)
	tween.tween_property(soldier, "position:z", jump_offset.z, travel_time)

	var y_tween = soldier.create_tween()
	y_tween.tween_property(soldier, "position:y", start_local_y + jump_height, travel_time * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	y_tween.tween_property(soldier, "position:y", jump_offset.y, travel_time * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	var soldier_id: int = soldier.get_instance_id()
	y_tween.finished.connect(func():
		var jumping_soldier = instance_from_id(soldier_id)
		if is_instance_valid(jumping_soldier):
			_finish_boarding_jump_pose(jumping_soldier, "on_deck")
	)

	if soldier.team == "enemy" and is_instance_valid(target_ship) and target_ship.get("team") == "player":
		soldier.chaos_duration_timer = 0.0
		soldier.chaos_tick_timer = 1.0

	if is_capture_attempt:
		var target_ship_id: int = target_ship.get_instance_id()
		tween.finished.connect(func():
			var boarded_ship = instance_from_id(target_ship_id)
			if is_instance_valid(boarded_ship):
				boarded_ship.set_meta("being_boarded", false)
		)

	if not is_capture_attempt:
		print("[Critical] 함선 침몰! 플레이어 본선으로 긴급 복귀합니다.")


static func teleport_to_ship(soldier, _target_ship: Node3D) -> void:
	_set_boarding_status(soldier, "stranded")
	if soldier.team == "player" and soldier.SURVIVOR_SCENE:
		var survivor = soldier.ScenePool.acquire(soldier.get_tree(), soldier.SURVIVOR_SCENE)
		soldier.get_tree().root.add_child.call_deferred(survivor)
		var spawn_pos: Vector3 = soldier.global_position
		spawn_pos.y = 0.5
		survivor.set_deferred("global_position", spawn_pos)
		print("[Rescue] 병사가 바다에 빠져 생존자가 되었습니다!")
	soldier.queue_free()


static func _get_nearest_deck_landing_local(target_ship: Node3D, approach_global: Vector3, target_half_ext: Vector2, target_deck_h: float) -> Vector3:
	var approach_local: Vector3 = target_ship.to_local(approach_global)
	var inset_x := minf(BOARDING_LANDING_INSET, maxf(0.0, target_half_ext.x - 0.05))
	var inset_z := minf(BOARDING_LANDING_INSET, maxf(0.0, target_half_ext.y - 0.05))
	var outside_x := absf(approach_local.x) > target_half_ext.x
	var outside_z := absf(approach_local.z) > target_half_ext.y

	var landing_x := clampf(approach_local.x, -target_half_ext.x + inset_x, target_half_ext.x - inset_x)
	var landing_z := clampf(approach_local.z, -target_half_ext.y + inset_z, target_half_ext.y - inset_z)
	if outside_x:
		landing_x = (target_half_ext.x - inset_x) * (1.0 if approach_local.x >= 0.0 else -1.0)
	if outside_z:
		landing_z = (target_half_ext.y - inset_z) * (1.0 if approach_local.z >= 0.0 else -1.0)

	return Vector3(landing_x, target_deck_h, landing_z)


static func has_active_boarding_link_between(ship_a: Node3D, ship_b: Node3D) -> bool:
	return _ship_has_active_boarding_link_to(ship_a, ship_b) or _ship_has_active_boarding_link_to(ship_b, ship_a)


static func _ship_has_active_boarding_link_to(from_ship: Node3D, to_ship: Node3D) -> bool:
	if not is_instance_valid(from_ship) or not is_instance_valid(to_ship):
		return false
	if from_ship.has_method("has_boarding_rope_link_to"):
		return from_ship.has_boarding_rope_link_to(to_ship) == true
	var target_ship: Node3D = null
	if from_ship.has_method("get_boarding_target_ship"):
		target_ship = from_ship.get_boarding_target_ship()
	elif "boarding_target" in from_ship:
		target_ship = from_ship.get("boarding_target")
	if target_ship != to_ship:
		return false
	if "_initial_rope_deployed" in from_ship:
		return from_ship.get("_initial_rope_deployed") == true
	return false


static func _set_boarding_status(soldier, status: String) -> void:
	if not is_instance_valid(soldier):
		return
	if soldier.has_method("set_boarding_status"):
		soldier.call("set_boarding_status", status)
	elif soldier.has_method("set_meta"):
		soldier.set_meta("boarding_status", status)


static func _begin_boarding_jump_pose(soldier, status: String) -> void:
	if not is_instance_valid(soldier):
		return
	if soldier.has_method("begin_boarding_jump_pose"):
		soldier.call("begin_boarding_jump_pose", status)
		return
	if "_is_jumping" in soldier:
		soldier.set("_is_jumping", true)
	_set_boarding_status(soldier, status)


static func _finish_boarding_jump_pose(soldier, status: String) -> void:
	if not is_instance_valid(soldier):
		return
	if soldier.has_method("finish_boarding_jump_pose"):
		soldier.call("finish_boarding_jump_pose", status)
		return
	if "_is_jumping" in soldier:
		soldier.set("_is_jumping", false)
	_set_boarding_status(soldier, status)
