class_name DebugDrawBridge
extends RefCounted

const DEFAULT_SEGMENTS := 72
const DEFAULT_THICKNESS := 0.035
const DEBUG_DRAW_3D_EXTENSION_PATH := "res://addons/debug_draw_3d/debug_draw_3d.gdextension"
const CHANNEL_SHIP_BOUNDS := "ship_bounds"
const CHANNEL_COLLISION := "collision"
const CHANNEL_PROJECTILE := "projectile"
const CHANNEL_SUPPORT := "support"
const CHANNEL_AI_INTENT := "ai_intent"
const CHANNEL_SPAWN := "spawn"
const CHANNEL_CREW_WORK := "crew_work"
const CHANNEL_WIND := "wind"
const CHANNEL_SITE := "site"
const CHANNEL_ORDER := [
	CHANNEL_SHIP_BOUNDS,
	CHANNEL_COLLISION,
	CHANNEL_PROJECTILE,
	CHANNEL_SUPPORT,
	CHANNEL_AI_INTENT,
	CHANNEL_SPAWN,
	CHANNEL_CREW_WORK,
	CHANNEL_WIND,
	CHANNEL_SITE,
]
const CHANNEL_LABELS := {
	CHANNEL_SHIP_BOUNDS: "선박영역",
	CHANNEL_COLLISION: "충돌",
	CHANNEL_PROJECTILE: "탄착",
	CHANNEL_SUPPORT: "지원",
	CHANNEL_AI_INTENT: "AI",
	CHANNEL_SPAWN: "스폰",
	CHANNEL_CREW_WORK: "선원",
	CHANNEL_WIND: "바람",
	CHANNEL_SITE: "사이트",
}

static var collision_debug_enabled: bool = false
static var projectile_debug_enabled: bool = false
static var support_debug_enabled: bool = false
static var _channels := {
	CHANNEL_SHIP_BOUNDS: false,
	CHANNEL_COLLISION: false,
	CHANNEL_PROJECTILE: false,
	CHANNEL_SUPPORT: false,
	CHANNEL_AI_INTENT: false,
	CHANNEL_SPAWN: false,
	CHANNEL_CREW_WORK: false,
	CHANNEL_WIND: false,
	CHANNEL_SITE: false,
}
static var _load_attempted: bool = false


static func set_collision_debug_enabled(enabled: bool) -> void:
	set_channel_enabled(CHANNEL_COLLISION, enabled)
	set_channel_enabled(CHANNEL_PROJECTILE, enabled)


static func set_ship_bounds_debug_enabled(enabled: bool) -> void:
	set_channel_enabled(CHANNEL_SHIP_BOUNDS, enabled)


static func set_projectile_debug_enabled(enabled: bool) -> void:
	set_channel_enabled(CHANNEL_PROJECTILE, enabled)


static func set_support_debug_enabled(enabled: bool) -> void:
	set_channel_enabled(CHANNEL_SUPPORT, enabled)


static func set_channel_enabled(channel: String, enabled: bool) -> void:
	if not _channels.has(channel):
		_channels[channel] = false
	_channels[channel] = enabled
	_sync_legacy_flags()


static func toggle_channel(channel: String) -> bool:
	var next_enabled := not is_channel_enabled(channel)
	set_channel_enabled(channel, next_enabled)
	return next_enabled


static func is_channel_enabled(channel: String) -> bool:
	return bool(_channels.get(channel, false))


static func get_channel_label(channel: String) -> String:
	return str(CHANNEL_LABELS.get(channel, channel))


static func get_channel_status_text(channels: Array = []) -> String:
	var parts: Array[String] = []
	var target_channels: Array = channels if not channels.is_empty() else CHANNEL_ORDER
	for channel_variant in target_channels:
		var channel := str(channel_variant)
		var state := "ON" if is_channel_enabled(channel) else "OFF"
		parts.append("%s %s" % [get_channel_label(channel), state])
	return " | ".join(parts)


static func _sync_legacy_flags() -> void:
	collision_debug_enabled = is_channel_enabled(CHANNEL_COLLISION)
	projectile_debug_enabled = is_channel_enabled(CHANNEL_PROJECTILE)
	support_debug_enabled = is_channel_enabled(CHANNEL_SUPPORT)


static func can_draw() -> bool:
	if not OS.is_debug_build() and not Engine.is_editor_hint():
		return false
	if _has_debug_draw_3d():
		return true
	_try_load_debug_draw_3d()
	return _has_debug_draw_3d()


static func draw_line(a: Vector3, b: Vector3, color: Color, duration: float = 0.0, thickness: float = DEFAULT_THICKNESS, no_depth_test: bool = true) -> void:
	if not can_draw():
		return
	var _scope = _make_scope(thickness, no_depth_test)
	_call_3d("draw_line", [a, b, color, duration])


static func draw_line_raised(a: Vector3, b: Vector3, y_offset: float, color: Color, duration: float = 0.0, thickness: float = DEFAULT_THICKNESS) -> void:
	draw_line(a + Vector3.UP * y_offset, b + Vector3.UP * y_offset, color, duration, thickness, true)


static func draw_arrow(a: Vector3, b: Vector3, color: Color, duration: float = 0.0, arrow_size: float = 0.65, thickness: float = DEFAULT_THICKNESS) -> void:
	if not can_draw():
		return
	var _scope = _make_scope(thickness, true)
	_call_3d("draw_arrow", [a, b, color, arrow_size, true, duration])


static func draw_marker(position: Vector3, color: Color, label: String = "", duration: float = 0.0, radius: float = 0.28, y_offset: float = 0.0) -> void:
	if not can_draw():
		return
	var pos := position + Vector3.UP * y_offset
	var _scope = _make_scope(DEFAULT_THICKNESS, true)
	_call_3d("draw_sphere", [pos, radius, color, duration])
	_call_3d("draw_position", [Transform3D(Basis.IDENTITY, pos), color, duration])
	if not label.is_empty():
		_call_3d("draw_text", [pos + Vector3.UP * (radius + 0.45), label, 18, color, duration])


static func draw_text(position: Vector3, text: String, color: Color, duration: float = 0.0, size: int = 18) -> void:
	if not can_draw():
		return
	var _scope = _make_scope(DEFAULT_THICKNESS, true)
	_call_3d("draw_text", [position, text, size, color, duration])


static func draw_circle_xz(center: Vector3, radius: float, color: Color, y_offset: float = 0.0, duration: float = 0.0, segments: int = DEFAULT_SEGMENTS, thickness: float = DEFAULT_THICKNESS) -> void:
	draw_ellipse_xz(center, Basis.IDENTITY, radius, radius, color, y_offset, duration, segments, thickness)


static func draw_box(transform: Transform3D, size: Vector3, color: Color, duration: float = 0.0, thickness: float = DEFAULT_THICKNESS) -> void:
	if size.x <= 0.01 or size.y <= 0.01 or size.z <= 0.01 or not can_draw():
		return
	var half := size * 0.5
	var corners := [
		Vector3(-half.x, -half.y, -half.z),
		Vector3(half.x, -half.y, -half.z),
		Vector3(half.x, -half.y, half.z),
		Vector3(-half.x, -half.y, half.z),
		Vector3(-half.x, half.y, -half.z),
		Vector3(half.x, half.y, -half.z),
		Vector3(half.x, half.y, half.z),
		Vector3(-half.x, half.y, half.z),
	]
	for index in range(corners.size()):
		corners[index] = transform * corners[index]
	var edges := [
		Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3), Vector2i(3, 0),
		Vector2i(4, 5), Vector2i(5, 6), Vector2i(6, 7), Vector2i(7, 4),
		Vector2i(0, 4), Vector2i(1, 5), Vector2i(2, 6), Vector2i(3, 7),
	]
	var _scope = _make_scope(thickness, true)
	for edge in edges:
		_call_3d("draw_line", [corners[edge.x], corners[edge.y], color, duration])


static func draw_ellipse_xz(center: Vector3, basis: Basis, radius_x: float, radius_z: float, color: Color, y_offset: float = 0.0, duration: float = 0.0, segments: int = DEFAULT_SEGMENTS, thickness: float = DEFAULT_THICKNESS) -> void:
	if radius_x <= 0.01 or radius_z <= 0.01 or not can_draw():
		return
	segments = maxi(12, segments)
	var right := basis.x
	var forward := basis.z
	var up := Vector3.UP
	right.y = 0.0
	forward.y = 0.0
	if right.length_squared() <= 0.0001:
		right = Vector3.RIGHT
	if forward.length_squared() <= 0.0001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	right = (right - forward * right.dot(forward))
	if right.length_squared() <= 0.0001:
		right = Vector3.UP.cross(forward)
	right = right.normalized()
	var origin := center + up * y_offset
	var path := PackedVector3Array()
	path.resize(segments + 1)
	for i in range(segments + 1):
		var t := TAU * float(i) / float(segments)
		path[i] = origin + right * cos(t) * radius_x + forward * sin(t) * radius_z
	var _scope = _make_scope(thickness, true)
	_call_3d("draw_line_path", [path, color, duration])


static func draw_hit_ray(start: Vector3, end: Vector3, hit: Vector3, is_hit: bool, label: String = "", duration: float = 1.2) -> void:
	if not can_draw():
		return
	var _scope = _make_scope(0.045, true)
	var hit_color := Color(1.0, 0.16, 0.08, 0.95)
	var after_hit_color := Color(1.0, 0.16, 0.08, 0.28)
	_call_3d("draw_line_hit", [start, end, hit, is_hit, 0.35, hit_color, after_hit_color, duration])
	if is_hit:
		_call_3d("draw_sphere", [hit, 0.34, hit_color, duration])
		if not label.is_empty():
			_call_3d("draw_text", [hit + Vector3.UP * 0.85, label, 18, hit_color, duration])


static func draw_targeting_solution(origin: Vector3, target_pos: Vector3, predicted_pos: Vector3, fire_direction: Vector3, range: float, label: String, duration: float = 0.9) -> void:
	if not can_draw():
		return
	var _scope = _make_scope(0.04, true)
	var aim_color := Color(1.0, 0.92, 0.28, 0.85)
	var predict_color := Color(0.35, 0.95, 1.0, 0.9)
	var shot_color := Color(1.0, 0.42, 0.18, 0.85)
	_call_3d("draw_line", [origin, target_pos, aim_color, duration])
	_call_3d("draw_sphere", [target_pos, 0.24, aim_color, duration])
	_call_3d("draw_sphere", [predicted_pos, 0.32, predict_color, duration])
	if not fire_direction.is_zero_approx():
		var shot_len: float = minf(maxf(origin.distance_to(predicted_pos), 3.0), maxf(range, 3.0))
		_call_3d("draw_arrow", [origin, origin + fire_direction.normalized() * shot_len, shot_color, 0.65, true, duration])
	if not label.is_empty():
		_call_3d("draw_text", [predicted_pos + Vector3.UP * 0.8, label, 18, predict_color, duration])


static func _make_scope(thickness: float, no_depth_test: bool) -> Variant:
	var scope = _call_3d("new_scoped_config", [])
	if scope != null:
		if scope.has_method("set_thickness"):
			scope.call("set_thickness", thickness)
		if scope.has_method("set_no_depth_test"):
			scope.call("set_no_depth_test", no_depth_test)
	return scope


static func _has_debug_draw_3d() -> bool:
	return Engine.has_singleton("DebugDraw3D") or ClassDB.class_exists("DebugDraw3D")


static func _try_load_debug_draw_3d() -> void:
	if _load_attempted:
		return
	_load_attempted = true
	if not ResourceLoader.exists(DEBUG_DRAW_3D_EXTENSION_PATH):
		return
	if not Engine.has_singleton("GDExtensionManager"):
		return
	var manager := Engine.get_singleton("GDExtensionManager")
	if not is_instance_valid(manager):
		return
	if manager.has_method("is_extension_loaded") and bool(manager.call("is_extension_loaded", DEBUG_DRAW_3D_EXTENSION_PATH)):
		return
	if manager.has_method("load_extension"):
		manager.call("load_extension", DEBUG_DRAW_3D_EXTENSION_PATH)


static func _call_3d(method: StringName, args: Array) -> Variant:
	if Engine.has_singleton("DebugDraw3D"):
		var singleton := Engine.get_singleton("DebugDraw3D")
		if is_instance_valid(singleton):
			return singleton.callv(method, args)
	if not ClassDB.class_exists("DebugDraw3D"):
		return null
	match args.size():
		0:
			return ClassDB.class_call_static("DebugDraw3D", method)
		3:
			return ClassDB.class_call_static("DebugDraw3D", method, args[0], args[1], args[2])
		4:
			return ClassDB.class_call_static("DebugDraw3D", method, args[0], args[1], args[2], args[3])
		5:
			return ClassDB.class_call_static("DebugDraw3D", method, args[0], args[1], args[2], args[3], args[4])
		6:
			return ClassDB.class_call_static("DebugDraw3D", method, args[0], args[1], args[2], args[3], args[4], args[5])
		8:
			return ClassDB.class_call_static("DebugDraw3D", method, args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7])
	return null
