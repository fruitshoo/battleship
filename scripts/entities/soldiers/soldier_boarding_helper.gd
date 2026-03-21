extends RefCounted
class_name SoldierBoardingHelper

const SoldierShipHelper = preload("res://scripts/entities/soldiers/soldier_ship_helper.gd")


static func try_evacuate_to_home(soldier) -> void:
	if not is_instance_valid(soldier.home_ship) or soldier.home_ship == soldier.owned_ship:
		return

	var dist: float = soldier.global_position.distance_to(soldier.home_ship.global_position)
	if dist < 12.0:
		jump_to_ship(soldier, soldier.home_ship)
	else:
		teleport_to_ship(soldier, soldier.home_ship)


static func jump_to_ship(soldier, target_ship: Node3D, is_capture_attempt: bool = false) -> void:
	var target_soldiers: Node = target_ship.get_node_or_null("Soldiers")
	if not target_soldiers:
		target_soldiers = target_ship

	soldier._is_jumping = true
	var d_h: float = target_ship.get("deck_height") if "deck_height" in target_ship else 0.4
	var target_half_ext: Vector2 = SoldierShipHelper.get_ship_deck_half_extents(soldier, target_ship)
	var jump_offset := Vector3(
		randf_range(-target_half_ext.x, target_half_ext.x),
		d_h,
		randf_range(-target_half_ext.y, target_half_ext.y)
	)

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
	y_tween.finished.connect(func(): soldier._is_jumping = false)

	if soldier.team == "enemy" and is_instance_valid(target_ship) and target_ship.get("team") == "player":
		soldier.chaos_duration_timer = 8.0
		soldier.chaos_tick_timer = 1.0

	if is_capture_attempt:
		tween.finished.connect(func():
			if is_instance_valid(target_ship):
				target_ship.set_meta("being_boarded", false)
		)

	if not is_capture_attempt:
		print("[Critical] 함선 침몰! 플레이어 본선으로 긴급 복귀합니다.")


static func teleport_to_ship(soldier, _target_ship: Node3D) -> void:
	if soldier.SURVIVOR_SCENE:
		var survivor = soldier.SURVIVOR_SCENE.instantiate()
		soldier.get_tree().root.add_child.call_deferred(survivor)
		var spawn_pos: Vector3 = soldier.global_position
		spawn_pos.y = 0.5
		survivor.set_deferred("global_position", spawn_pos)
		print("[Rescue] 병사가 바다에 빠져 생존자가 되었습니다!")
	soldier.queue_free()
