extends RefCounted
class_name BaseShipBoardingRopeVisualHelper

const BOARDING_ROPE_RADIUS := 0.18
const BOARDING_ROPE_EXTRA_CULL_MARGIN := 24.0
const BOARDING_ROPE_DECK_HEIGHT_OFFSET := 0.85
const BOARDING_ROPE_MIN_ANCHOR_HEIGHT := 0.65
const BOARDING_ROPE_NORMAL_ALBEDO := Color(1.0, 0.88, 0.52, 1.0)
const BOARDING_ROPE_NORMAL_EMISSION := Color(1.0, 0.66, 0.24, 1.0)
const BOARDING_ROPE_STRAIN_ALBEDO := Color(1.0, 0.18, 0.08, 1.0)
const BOARDING_ROPE_STRAIN_EMISSION := Color(1.0, 0.06, 0.02, 1.0)
const BOARDING_HOOK_NORMAL_ALBEDO := Color(1.0, 0.86, 0.52, 0.95)
const BOARDING_HOOK_NORMAL_EMISSION := Color(1.0, 0.72, 0.28, 1.0)
const BOARDING_HOOK_STRAIN_ALBEDO := Color(1.0, 0.20, 0.08, 0.98)
const BOARDING_HOOK_STRAIN_EMISSION := Color(1.0, 0.08, 0.02, 1.0)


static func spawn_ropes(ship, count_override: int = -1) -> void:
	clear_ropes(ship, false)
	var count = count_override if count_override > 0 else randi_range(2, 3)
	count = max(1, count)
	for i in range(count):
		var mesh_instance = MeshInstance3D.new()
		var cylinder = CylinderMesh.new()
		cylinder.top_radius = BOARDING_ROPE_RADIUS
		cylinder.bottom_radius = BOARDING_ROPE_RADIUS
		cylinder.height = 1.0
		mesh_instance.mesh = cylinder
		mesh_instance.top_level = true
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh_instance.extra_cull_margin = BOARDING_ROPE_EXTRA_CULL_MARGIN
		mesh_instance.ignore_occlusion_culling = true
		
		var mat = StandardMaterial3D.new()
		mat.albedo_color = BOARDING_ROPE_NORMAL_ALBEDO
		mat.roughness = 0.55
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.emission_enabled = true
		mat.emission = BOARDING_ROPE_NORMAL_EMISSION
		mat.emission_energy_multiplier = 1.8
		mat.no_depth_test = false
		mesh_instance.material_override = mat
		
		ship.add_child(mesh_instance)

		var hook_visual := MeshInstance3D.new()
		var hook_mesh := SphereMesh.new()
		hook_mesh.radius = 0.28
		hook_mesh.height = 0.56
		hook_visual.mesh = hook_mesh
		var hook_mat := StandardMaterial3D.new()
		hook_mat.albedo_color = BOARDING_HOOK_NORMAL_ALBEDO
		hook_mat.emission_enabled = true
		hook_mat.emission = BOARDING_HOOK_NORMAL_EMISSION
		hook_mat.emission_energy_multiplier = 2.2
		hook_mat.roughness = 0.35
		hook_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		hook_mat.no_depth_test = false
		hook_visual.material_override = hook_mat
		hook_visual.top_level = true
		hook_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hook_visual.extra_cull_margin = BOARDING_ROPE_EXTRA_CULL_MARGIN
		hook_visual.ignore_occlusion_culling = true
		ship.add_child(hook_visual)
		
		var offset_z: float = 0.0
		var deck_half_extents: Vector2 = ship.get_deck_half_extents()
		if count > 1:
			var rope_spread: float = maxf(0.15, minf(2.0, deck_half_extents.y * 0.55))
			offset_z = lerp(-rope_spread, rope_spread, float(i) / float(count - 1))
		var anchor_side := 1.0
		if is_instance_valid(ship.boarding_target):
			var to_target = (ship.boarding_target.global_position - ship.global_position).normalized()
			var local_to_target = ship.global_transform.basis.inverse() * to_target
			if local_to_target.x < 0:
				anchor_side = -1.0
		var offset = get_source_anchor_local(ship, anchor_side, offset_z)
			
		mesh_instance.position = offset
		mesh_instance.set_meta("anchor_offset", offset)
		mesh_instance.set_meta("deploy_progress", 0.0)
		mesh_instance.set_meta("deploy_duration", maxf(0.05, ship.boarding_rope_throw_duration + randf_range(-0.06, 0.08)))
		mesh_instance.set_meta("hook_visual", hook_visual)
		ship.rope_instances.append(mesh_instance)


static func update_ropes(ship, delta: float = 0.0) -> void:
	if not is_instance_valid(ship.boarding_target):
		clear_ropes(ship)
		return
	var rope_resist_ratio := clampf(get_visual_resist_ratio(ship) + ship.boarding_rope_visual_pulse * 0.62, 0.0, 1.0)
		
	for rope in ship.rope_instances:
		if not is_instance_valid(rope):
			continue
		
		var offset = rope.get_meta("anchor_offset", Vector3.ZERO)
		var start_pos = ship.to_global(offset)
		var target_anchor = get_target_anchor_global(ship, start_pos)
		
		var deploy_progress = float(rope.get_meta("deploy_progress", 1.0))
		var deploy_duration = maxf(0.05, float(rope.get_meta("deploy_duration", ship.boarding_rope_throw_duration)))
		if deploy_progress < 1.0:
			deploy_progress = clampf(deploy_progress + (delta / deploy_duration), 0.0, 1.0)
			rope.set_meta("deploy_progress", deploy_progress)
		
		var current_end = start_pos.lerp(target_anchor, deploy_progress)
		if ship.boarding_rope_visual_pulse > 0.0 and deploy_progress >= 0.98:
			var pullback_dir: Vector3 = start_pos - current_end
			if pullback_dir.length_squared() > 0.0001:
				current_end += pullback_dir.normalized() * minf(0.72, start_pos.distance_to(current_end) * 0.075) * ship.boarding_rope_visual_pulse
		var dist = maxf(0.05, start_pos.distance_to(current_end))
		var rope_dir = (current_end - start_pos).normalized()
		if ship.boarding_rope_visual_pulse > 0.0 and deploy_progress >= 0.98:
			var side_dir: Vector3 = rope_dir.cross(Vector3.UP)
			if side_dir.length_squared() > 0.0001:
				var jitter: float = sin(float(Time.get_ticks_msec()) * 0.043 + float(rope.get_instance_id() % 37)) * 0.12 * ship.boarding_rope_visual_pulse
				current_end += side_dir.normalized() * jitter
				dist = maxf(0.05, start_pos.distance_to(current_end))
				rope_dir = (current_end - start_pos).normalized()
		var sag_amount = minf(0.28, dist * 0.025) * deploy_progress * maxf(0.0, 1.0 - ship.boarding_rope_visual_pulse * 0.92)
		var sag_mid = (start_pos + current_end) * 0.5 + Vector3(0.0, -sag_amount, 0.0)
		
		rope.global_transform = Transform3D().looking_at(current_end - sag_mid, Vector3.UP)
		rope.global_position = sag_mid
		
		rope.rotate_object_local(Vector3.RIGHT, deg_to_rad(-90))
		var pull_snap: float = 1.0 + ship.boarding_rope_visual_pulse * 0.78
		rope.scale = Vector3(pull_snap, dist, pull_snap) * (1.0 + (1.0 - deploy_progress) * 0.12)
		_update_rope_material(ship, rope, rope_resist_ratio, deploy_progress)
		var hook_visual = rope.get_meta("hook_visual", null) as MeshInstance3D
		if is_instance_valid(hook_visual):
			hook_visual.visible = deploy_progress >= 0.18
			hook_visual.global_position = current_end
			var hook_basis := Basis.looking_at(-rope_dir, Vector3.UP)
			hook_visual.global_transform = Transform3D(hook_basis, current_end)
			var strain_pulse := sin(float(Time.get_ticks_msec()) * 0.028) * 0.07 * rope_resist_ratio
			strain_pulse += ship.boarding_rope_visual_pulse * 0.34
			hook_visual.scale = Vector3.ONE * (lerpf(0.65, 1.0, deploy_progress) + strain_pulse)
			_update_hook_material(ship, hook_visual, rope_resist_ratio, deploy_progress)


static func pulse_feedback(ship, intensity: float = 1.0) -> void:
	if ship.rope_instances.is_empty():
		return
	if is_instance_valid(ship._boarding_rope_visual_tween):
		ship._boarding_rope_visual_tween.kill()
	var pulse_peak := clampf(intensity, 0.0, 1.0) * 1.18
	ship.boarding_rope_visual_pulse = maxf(ship.boarding_rope_visual_pulse, pulse_peak * 0.68)
	ship._boarding_rope_visual_tween = ship.create_tween()
	ship._boarding_rope_visual_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	ship._boarding_rope_visual_tween.tween_property(ship, "boarding_rope_visual_pulse", pulse_peak, 0.075)
	ship._boarding_rope_visual_tween.tween_property(ship, "boarding_rope_visual_pulse", 0.0, 0.24).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


static func get_visual_resist_ratio(ship) -> float:
	if not is_instance_valid(ship.boarding_target):
		return 0.0
	if ship.boarding_target.has_method("get_boarding_rope_resist_ratio"):
		return clampf(float(ship.boarding_target.call("get_boarding_rope_resist_ratio")), 0.0, 1.0)
	return 0.0


static func get_source_anchor_local(ship, side_sign: float, along_offset: float) -> Vector3:
	var half_extents: Vector2 = ship.get_deck_half_extents()
	var x_margin: float = minf(0.24, half_extents.x * 0.35)
	var z_margin: float = minf(0.45, half_extents.y * 0.25)
	var safe_half_x: float = maxf(0.12, half_extents.x - x_margin)
	var safe_half_z: float = maxf(0.12, half_extents.y - z_margin)
	var local_x: float = signf(side_sign) * safe_half_x
	var local_z: float = clampf(along_offset, -safe_half_z, safe_half_z)
	var fallback := Vector3(local_x, get_local_anchor_height(ship), local_z)
	if ship.prefer_authoring_boarding_anchors:
		return ShipAuthoringHelper.get_boarding_anchor_local(ship, side_sign, local_z, fallback)
	return fallback


static func get_target_anchor_global(ship, start_global: Vector3) -> Vector3:
	if not is_instance_valid(ship.boarding_target):
		return start_global
	var target_local: Vector3 = ship.boarding_target.to_local(start_global)
	var half_extents := get_target_deck_half_extents(ship.boarding_target)
	var x_margin: float = minf(0.24, half_extents.x * 0.35)
	var z_margin: float = minf(0.45, half_extents.y * 0.25)
	var safe_half_x: float = maxf(0.12, half_extents.x - x_margin)
	var safe_half_z: float = maxf(0.12, half_extents.y - z_margin)
	target_local.x = clampf(target_local.x, -safe_half_x, safe_half_x)
	target_local.z = clampf(target_local.z, -safe_half_z, safe_half_z)
	target_local.y = get_local_anchor_height(ship.boarding_target)
	var fallback_global: Vector3 = ship.boarding_target.to_global(target_local)
	if ship.prefer_authoring_boarding_anchors:
		return ShipAuthoringHelper.get_nearest_boarding_anchor_global(ship.boarding_target, start_global, fallback_global)
	return fallback_global


static func get_target_deck_half_extents(target_ship: Node3D) -> Vector2:
	if is_instance_valid(target_ship) and target_ship.has_method("get_deck_half_extents"):
		var extents = target_ship.call("get_deck_half_extents")
		if extents is Vector2 and extents.x > 0.01 and extents.y > 0.01:
			return extents
	if is_instance_valid(target_ship) and target_ship.has_method("get_collision_half_extents"):
		var collision_extents = target_ship.call("get_collision_half_extents")
		if collision_extents is Vector2 and collision_extents.x > 0.01 and collision_extents.y > 0.01:
			return collision_extents
	return Vector2(1.0, 1.5)


static func get_local_anchor_height(ship_node: Node) -> float:
	if is_instance_valid(ship_node) and ship_node.get("deck_height") != null:
		return maxf(BOARDING_ROPE_MIN_ANCHOR_HEIGHT, float(ship_node.get("deck_height")) + BOARDING_ROPE_DECK_HEIGHT_OFFSET)
	return BOARDING_ROPE_MIN_ANCHOR_HEIGHT + BOARDING_ROPE_DECK_HEIGHT_OFFSET


static func clear_ropes(ship, reset_pull_velocity: bool = true) -> void:
	if is_instance_valid(ship._boarding_rope_visual_tween):
		ship._boarding_rope_visual_tween.kill()
	ship._boarding_rope_visual_tween = null
	ship.boarding_rope_visual_pulse = 0.0
	for rope in ship.rope_instances:
		if is_instance_valid(rope):
			var hook_visual = rope.get_meta("hook_visual", null) as MeshInstance3D
			if is_instance_valid(hook_visual):
				hook_visual.queue_free()
			rope.queue_free()
	ship.rope_instances.clear()
	if reset_pull_velocity:
		ship.boarding_pull_velocity = Vector3.ZERO


static func _update_rope_material(ship, rope: MeshInstance3D, resist_ratio: float, deploy_progress: float) -> void:
	var rope_material: StandardMaterial3D = rope.material_override as StandardMaterial3D
	if not is_instance_valid(rope_material):
		return
	var t := smoothstep(0.0, 1.0, clampf(resist_ratio, 0.0, 1.0))
	rope_material.albedo_color = BOARDING_ROPE_NORMAL_ALBEDO.lerp(BOARDING_ROPE_STRAIN_ALBEDO, t)
	rope_material.emission = BOARDING_ROPE_NORMAL_EMISSION.lerp(BOARDING_ROPE_STRAIN_EMISSION, t)
	var pulse := sin(float(Time.get_ticks_msec()) * 0.032) * 0.65 * t
	rope_material.emission_energy_multiplier = lerpf(1.2, 2.6, deploy_progress) + (3.2 * t) + pulse + ship.boarding_rope_visual_pulse * 1.1


static func _update_hook_material(ship, hook_visual: MeshInstance3D, resist_ratio: float, deploy_progress: float) -> void:
	var hook_material: StandardMaterial3D = hook_visual.material_override as StandardMaterial3D
	if not is_instance_valid(hook_material):
		return
	var t := smoothstep(0.0, 1.0, clampf(resist_ratio, 0.0, 1.0))
	hook_material.albedo_color = BOARDING_HOOK_NORMAL_ALBEDO.lerp(BOARDING_HOOK_STRAIN_ALBEDO, t)
	hook_material.emission = BOARDING_HOOK_NORMAL_EMISSION.lerp(BOARDING_HOOK_STRAIN_EMISSION, t)
	var pulse := sin(float(Time.get_ticks_msec()) * 0.034) * 0.8 * t
	hook_material.emission_energy_multiplier = lerpf(1.6, 2.4, deploy_progress) + (3.6 * t) + pulse + ship.boarding_rope_visual_pulse * 1.4
