extends RefCounted


static func update_sail_wind_visual(mast: Node3D) -> void:
	if not is_instance_valid(mast.sail_visual):
		return
	mast.sail_visual.rotation.y = deg_to_rad(-mast.sail_angle)

	if not is_instance_valid(mast._cached_wind_manager):
		mast._cached_wind_manager = mast.get_node_or_null("/root/WindManager")
	if not is_instance_valid(mast._cached_wind_manager) or not mast._cached_wind_manager.has_method("get_wind_direction"):
		apply_wind_strength_to_sails(mast, 0.0)
		return

	var wind_dir: Vector2 = mast._cached_wind_manager.get_wind_direction()
	var sail_fwd: Vector3 = -mast.sail_visual.global_transform.basis.z
	var sail_fwd_2d: Vector2 = Vector2(sail_fwd.x, sail_fwd.z)
	if sail_fwd_2d.length_squared() <= 0.0001:
		apply_wind_strength_to_sails(mast, 0.0)
		return
	sail_fwd_2d = sail_fwd_2d.normalized()
	mast._current_wind_intake = max(0.0, wind_dir.dot(sail_fwd_2d)) * mast.max_wind_intake
	apply_wind_strength_to_sails(mast, mast._current_wind_intake)


static func apply_wind_strength_to_sails(mast: Node3D, wind_strength_value: float) -> void:
	if is_equal_approx(mast._last_applied_wind_strength, wind_strength_value):
		return
	mast._last_applied_wind_strength = wind_strength_value
	for mesh in mast._get_sail_meshes():
		mesh.set_instance_shader_parameter("wind_strength", wind_strength_value)
