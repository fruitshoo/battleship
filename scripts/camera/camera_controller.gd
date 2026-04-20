extends Camera3D

## 3rd Person Camera Controller
## 타겟(배)을 부드럽게 따라다니며 줌/회전 기능 제공

@export var target_path: NodePath
@export_group("Follow Settings")
@export_range(0.5, 12.0) var smooth_speed: float = 3.5
@export_range(-80.0, -20.0) var pitch_degrees: float = -45.0
@export_range(0.0, 30.0) var lead_distance: float = 7.5
@export_range(0.0, 10.0) var lead_smooth_speed: float = 4.5
@export var offset: Vector3 = Vector3(0, 15, 20)

@export_group("Control Settings")
@export var zoom_speed: float = 2.0
@export var min_zoom: float = 10.0
@export var max_zoom: float = 88.0 # +10% 줌아웃 (기존 80.0)
@export_range(1.0, 20.0) var zoom_smooth_speed: float = 12.0
@export var rotation_sensitivity: float = 0.005

@export_group("Fog Settings")
@export_range(0.0, 300.0) var fog_begin_min: float = 90.0
@export_range(0.0, 600.0) var fog_end_min: float = 240.0
@export_range(0.0, 10.0) var fog_begin_zoom_multiplier: float = 2.2
@export_range(0.0, 12.0) var fog_end_zoom_multiplier: float = 6.0

@export_group("Sail Occlusion Fade")
@export var sail_occlusion_fade_enabled: bool = true
@export_range(0.4, 1.0, 0.01) var sail_occlusion_alpha: float = 0.72
@export_range(0.02, 0.4, 0.01) var sail_occlusion_update_interval: float = 0.08
@export_range(0.0, 80.0, 1.0) var sail_occlusion_screen_padding: float = 28.0
@export_range(6.0, 60.0, 1.0) var sail_occlusion_world_distance: float = 34.0
@export_group("Decor Occlusion Fade")
@export var decor_occlusion_fade_enabled: bool = false
@export_range(0.55, 1.0, 0.01) var decor_occlusion_alpha: float = 0.78
@export_range(0.0, 120.0, 1.0) var decor_occlusion_screen_padding: float = 18.0
@export_range(0.0, 40.0, 1.0) var decor_occlusion_min_world_distance: float = 11.0
@export_range(12.0, 180.0, 1.0) var decor_occlusion_world_distance: float = 110.0

var target: Node3D = null
var current_zoom: float = 0.0
var target_zoom: float = 0.0
var _cam_rotation: Vector2 = Vector2.ZERO
var _smoothed_look_target: Vector3 = Vector3.ZERO

var shake_intensity: float = 0.0
var shake_timer: float = 0.0
var shake_duration: float = 0.0
var _last_zoom: float = -1.0 # 마지막으로 포그가 업데이트된 줌 레벨
var audio_listener: AudioListener3D
var _sail_occlusion_update_left: float = 0.0

func _ready() -> void:
	if target_path:
		target = get_node_or_null(target_path)
	
	current_zoom = offset.length()
	target_zoom = current_zoom
	
	# 초기 회전값 설정
	var rot = transform.basis.get_euler()
	_cam_rotation.x = rot.y
	_cam_rotation.y = rot.x
	if is_instance_valid(target):
		_smoothed_look_target = target.global_position
	
	# 카메라 줌에 따른 오디오 볼륨 불균형 해결을 위한 독립적인 리스너 추가
	audio_listener = AudioListener3D.new()
	add_child(audio_listener)
	audio_listener.make_current()

func _input(event: InputEvent) -> void:
	# 마우스 휠로 줌
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			target_zoom = clamp(target_zoom - zoom_speed, min_zoom, max_zoom)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target_zoom = clamp(target_zoom + zoom_speed, min_zoom, max_zoom)
	
	# 트랙패드 핀치로 줌 (Mac)
	if event is InputEventMagnifyGesture:
		var pinch_zoom_speed = zoom_speed * 5.0
		target_zoom = clamp(target_zoom - (event.factor - 1.0) * pinch_zoom_speed, min_zoom, max_zoom)
	
	# 트랙패드 두 손가락 팬으로 orbit 회전 (Mac)
	if event is InputEventPanGesture:
		_cam_rotation.x -= event.delta.x * rotation_sensitivity * 0.5
		_cam_rotation.y -= event.delta.y * rotation_sensitivity * 0.5
		_cam_rotation.y = clamp(_cam_rotation.y, -PI / 2 + 0.1, 0)
	
	# 우클릭 또는 휠클릭 드래그로 회전
	if event is InputEventMouseMotion and (Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)):
		_cam_rotation.x -= event.relative.x * rotation_sensitivity
		_cam_rotation.y -= event.relative.y * rotation_sensitivity
		_cam_rotation.y = clamp(_cam_rotation.y, -PI / 2 + 0.1, 0) # 땅 밑으로 안 가게 제한

func _physics_process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	
	current_zoom = move_toward(current_zoom, target_zoom, zoom_smooth_speed * delta)
	
	# 1. 타겟 위치 + 진행 방향 리드
	var target_pos = _get_desired_look_target()
	_smoothed_look_target = _smoothed_look_target.lerp(target_pos, clampf(lead_smooth_speed * delta, 0.0, 1.0))
	
	# 2. 쿼터뷰 고정 각도 (45도 위에서, 약간 뒤에서)
	# 수평 회전은 유저가 조절 가능, 수직 각도는 고정
	var quarter_view_angle = deg_to_rad(pitch_degrees)
	
	# 우클릭 드래그로 수평 회전만 가능
	var rot_basis = Basis.from_euler(Vector3(quarter_view_angle, _cam_rotation.x, 0))
	var final_offset = rot_basis * Vector3(0, 0, current_zoom)
	
	var desired_position = _smoothed_look_target + final_offset
	
	# 3. 부드러운 이동
	global_position = global_position.lerp(desired_position, clampf(smooth_speed * delta, 0.0, 1.0))
	
	# 4. 항상 타겟 바라보기
	look_at(_smoothed_look_target, Vector3.UP)
	
	# 5. 동적 포그 조절 (줌에 따라 안개 거리 조정)
	_update_dynamic_fog()
	_update_sail_occlusion_fade(delta)
	if decor_occlusion_fade_enabled:
		_update_decor_occlusion_fade()
	
	# 오디오 리스너 위치 고정 (카메라 줌에 상관없이 타겟 근처 유지하되, 약간의 거리감 허용)
	if is_instance_valid(audio_listener):
		# 카메라는 타겟에서 current_zoom 만큼 물러나 있으므로,
		# 로컬 공간에서 앞으로(-Z 방향) 당겨주면 타겟 쪽으로 갑니다.
		# 완전히 0 Z에 두면 거리감이 전혀 없으므로, 줌 아웃의 30% 정도만 거리가 멀어지게 설정합니다.
		var listener_distance = current_zoom * 0.3
		listener_distance = max(listener_distance, min_zoom)
		audio_listener.position = Vector3(0, 0, -current_zoom + listener_distance)
	
	# 6. 화면 흔들림 (Screen Shake)
	if shake_timer > 0:
		shake_timer -= delta
		var damping = shake_timer / max(0.001, shake_duration)
		var shake_offset = Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)
		) * shake_intensity * damping
		global_position += shake_offset

func _update_sail_occlusion_fade(delta: float) -> void:
	if not sail_occlusion_fade_enabled:
		_reset_all_sail_occlusion_fades()
		return
	_sail_occlusion_update_left -= delta
	if _sail_occlusion_update_left > 0.0:
		return
	_sail_occlusion_update_left = sail_occlusion_update_interval

	var ships: Array = EntityRegistry.get_ships()
	if ships.size() <= 1:
		_reset_all_sail_occlusion_fades(ships)
		return

	var faded_mast_ids: Dictionary = {}
	for ship_variant in ships:
		var ship: Node3D = ship_variant as Node3D
		if not _is_sail_occlusion_ship_valid(ship):
			continue
		var masts: Array = _get_ship_masts(ship)
		for mast_variant in masts:
			var mast: Node3D = mast_variant as Node3D
			if not is_instance_valid(mast):
				continue
			var sail_rect: Rect2 = _get_mast_sail_screen_rect(mast)
			if sail_rect.size == Vector2.ZERO:
				continue
			var sail_cam_dist: float = _get_mast_sail_nearest_camera_distance_squared(mast)
			for other_variant in ships:
				var other_ship: Node3D = other_variant as Node3D
				if other_ship == ship or not _is_sail_occlusion_ship_valid(other_ship):
					continue
				if ship.global_position.distance_to(other_ship.global_position) > sail_occlusion_world_distance:
					continue
				if _does_sail_cover_ship_points(sail_rect, sail_cam_dist, other_ship):
					faded_mast_ids[mast.get_instance_id()] = true
					break

	for ship_variant in ships:
		var ship: Node3D = ship_variant as Node3D
		if not is_instance_valid(ship):
			continue
		for mast_variant in _get_ship_masts(ship):
			var mast: Node3D = mast_variant as Node3D
			if not is_instance_valid(mast) or not mast.has_method("set_sail_view_fade_alpha"):
				continue
			var alpha: float = sail_occlusion_alpha if faded_mast_ids.has(mast.get_instance_id()) else 1.0
			mast.call("set_sail_view_fade_alpha", alpha)

func _reset_all_sail_occlusion_fades(ships: Array = []) -> void:
	var target_ships: Array = ships if not ships.is_empty() else EntityRegistry.get_ships()
	for ship_variant in target_ships:
		var ship: Node3D = ship_variant as Node3D
		if not is_instance_valid(ship):
			continue
		for mast_variant in _get_ship_masts(ship):
			var mast: Node3D = mast_variant as Node3D
			if is_instance_valid(mast) and mast.has_method("set_sail_view_fade_alpha"):
				mast.call("set_sail_view_fade_alpha", 1.0)

func _update_decor_occlusion_fade() -> void:
	if not decor_occlusion_fade_enabled:
		_reset_all_decor_occlusion_fades()
		return
	if not is_instance_valid(target):
		_reset_all_decor_occlusion_fades()
		return

	var ships: Array = EntityRegistry.get_ships()
	var faded_decor_ids: Dictionary = {}
	for decor_variant in get_tree().get_nodes_in_group("sea_rock_decor"):
		var decor: Node3D = decor_variant as Node3D
		if not _is_decor_occlusion_candidate_valid(decor):
			continue
		var decor_rect: Rect2 = _get_decor_screen_rect(decor)
		if decor_rect.size == Vector2.ZERO:
			continue
		var decor_cam_dist: float = _get_decor_nearest_camera_distance_squared(decor)
		for ship_variant in ships:
			var ship: Node3D = ship_variant as Node3D
			if not _is_sail_occlusion_ship_valid(ship):
				continue
			var decor_ship_distance := decor.global_position.distance_to(ship.global_position)
			if decor_ship_distance < decor_occlusion_min_world_distance:
				continue
			if decor_ship_distance > decor_occlusion_world_distance:
				continue
			if _does_sail_cover_ship_points(decor_rect, decor_cam_dist, ship):
				faded_decor_ids[decor.get_instance_id()] = true
				break

	for decor_variant in get_tree().get_nodes_in_group("sea_rock_decor"):
		var decor: Node3D = decor_variant as Node3D
		if not is_instance_valid(decor) or not decor.has_method("set_rock_view_fade_alpha"):
			continue
		var alpha: float = decor_occlusion_alpha if faded_decor_ids.has(decor.get_instance_id()) else 1.0
		decor.call("set_rock_view_fade_alpha", alpha)


func _reset_all_decor_occlusion_fades() -> void:
	for decor_variant in get_tree().get_nodes_in_group("sea_rock_decor"):
		var decor: Node3D = decor_variant as Node3D
		if is_instance_valid(decor) and decor.has_method("set_rock_view_fade_alpha"):
			decor.call("set_rock_view_fade_alpha", 1.0)


func _is_decor_occlusion_candidate_valid(decor: Node3D) -> bool:
	if not is_instance_valid(decor) or not decor.visible:
		return false
	if is_position_behind(decor.global_position):
		return false
	return true

func _is_sail_occlusion_ship_valid(ship: Node3D) -> bool:
	if not is_instance_valid(ship):
		return false
	if ship.get("is_sinking") == true or ship.get("is_dying") == true:
		return false
	if is_position_behind(ship.global_position):
		return false
	return true

func _get_ship_masts(ship: Node3D) -> Array:
	if not is_instance_valid(ship):
		return []
	var raw_masts: Variant = ship.get("masts")
	if raw_masts is Array:
		return raw_masts as Array
	return []

func _get_ship_occlusion_focus(ship: Node3D) -> Vector3:
	var deck_height: float = 1.2
	if ship.get("deck_height") != null:
		deck_height = maxf(float(ship.get("deck_height")) + 0.8, 1.2)
	return ship.global_position + Vector3(0.0, deck_height, 0.0)

func _does_sail_cover_ship_points(sail_rect: Rect2, sail_cam_dist: float, ship: Node3D) -> bool:
	var covered_points := 0
	for focus_point in _get_ship_occlusion_points(ship):
		if is_position_behind(focus_point):
			continue
		if global_position.distance_squared_to(focus_point) <= sail_cam_dist + 0.25:
			continue
		if sail_rect.has_point(unproject_position(focus_point)):
			covered_points += 1
			if covered_points >= 2:
				return true
	return false

func _get_ship_occlusion_points(ship: Node3D) -> Array[Vector3]:
	var center: Vector3 = _get_ship_occlusion_focus(ship)
	var half_extents := Vector2(2.0, 4.0)
	if ship.has_method("get_collision_half_extents"):
		var raw_extents: Variant = ship.call("get_collision_half_extents")
		if raw_extents is Vector2:
			half_extents = raw_extents as Vector2
	var right: Vector3 = ship.global_basis.x.normalized()
	var forward: Vector3 = -ship.global_basis.z.normalized()
	var half_width: float = maxf(half_extents.x, 1.6)
	var half_length: float = maxf(half_extents.y, 2.8)
	return [
		center,
		center + forward * half_length,
		center - forward * half_length,
		center + right * half_width,
		center - right * half_width,
		center + forward * half_length + right * half_width,
		center + forward * half_length - right * half_width,
		center - forward * half_length + right * half_width,
		center - forward * half_length - right * half_width,
	]

func _get_mast_sail_nearest_camera_distance_squared(mast: Node3D) -> float:
	var sail_mesh: MeshInstance3D = mast.get_node_or_null("SailVisual/SailMesh") as MeshInstance3D
	if not is_instance_valid(sail_mesh) or sail_mesh.mesh == null:
		return global_position.distance_squared_to(mast.global_position + Vector3(0.0, 4.0, 0.0))
	var min_dist: float = INF
	for local_corner in _aabb_corners(sail_mesh.mesh.get_aabb()):
		var world_corner: Vector3 = sail_mesh.global_transform * local_corner
		min_dist = minf(min_dist, global_position.distance_squared_to(world_corner))
	return min_dist

func _get_mast_sail_screen_rect(mast: Node3D) -> Rect2:
	var sail_mesh: MeshInstance3D = mast.get_node_or_null("SailVisual/SailMesh") as MeshInstance3D
	if not is_instance_valid(sail_mesh) or sail_mesh.mesh == null or not sail_mesh.visible:
		return Rect2()
	var local_aabb: AABB = sail_mesh.mesh.get_aabb()
	var corners: Array[Vector3] = _aabb_corners(local_aabb)
	var found: bool = false
	var rect: Rect2 = Rect2()
	for local_corner in corners:
		var world_corner: Vector3 = sail_mesh.global_transform * local_corner
		if is_position_behind(world_corner):
			continue
		var screen_point: Vector2 = unproject_position(world_corner)
		if not found:
			rect = Rect2(screen_point, Vector2.ZERO)
			found = true
		else:
			rect = rect.expand(screen_point)
	if not found:
		return Rect2()
	return rect.grow(sail_occlusion_screen_padding)

func _get_decor_nearest_camera_distance_squared(decor: Node3D) -> float:
	var visual := decor.get_node_or_null("Visual") as Node3D
	if not is_instance_valid(visual):
		visual = decor
	var min_dist: float = INF
	for mesh in _collect_mesh_instances(visual):
		if not is_instance_valid(mesh.mesh):
			continue
		for local_corner in _aabb_corners(mesh.mesh.get_aabb()):
			var world_corner: Vector3 = mesh.global_transform * local_corner
			min_dist = minf(min_dist, global_position.distance_squared_to(world_corner))
	if min_dist == INF:
		return global_position.distance_squared_to(decor.global_position)
	return min_dist

func _get_decor_screen_rect(decor: Node3D) -> Rect2:
	var visual := decor.get_node_or_null("Visual") as Node3D
	if not is_instance_valid(visual):
		visual = decor
	var found: bool = false
	var rect: Rect2 = Rect2()
	for mesh in _collect_mesh_instances(visual):
		if not is_instance_valid(mesh.mesh) or not mesh.visible:
			continue
		for local_corner in _aabb_corners(mesh.mesh.get_aabb()):
			var world_corner: Vector3 = mesh.global_transform * local_corner
			if is_position_behind(world_corner):
				continue
			var screen_point: Vector2 = unproject_position(world_corner)
			if not found:
				rect = Rect2(screen_point, Vector2.ZERO)
				found = true
			else:
				rect = rect.expand(screen_point)
	if not found:
		return Rect2()
	return rect.grow(decor_occlusion_screen_padding)

func _collect_mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		meshes.append(root as MeshInstance3D)
	for child in root.get_children():
		meshes.append_array(_collect_mesh_instances(child))
	return meshes

func _aabb_corners(aabb: AABB) -> Array[Vector3]:
	var p: Vector3 = aabb.position
	var s: Vector3 = aabb.size
	return [
		p,
		p + Vector3(s.x, 0, 0),
		p + Vector3(0, s.y, 0),
		p + Vector3(0, 0, s.z),
		p + Vector3(s.x, s.y, 0),
		p + Vector3(s.x, 0, s.z),
		p + Vector3(0, s.y, s.z),
		p + s,
	]

func shake(intensity: float, duration: float) -> void:
	shake_intensity = intensity
	shake_duration = duration
	shake_timer = duration

func _get_desired_look_target() -> Vector3:
	var base_target := target.global_position
	var speed_ratio := 0.0
	var current_speed_value := 0.0
	var max_speed_value := 0.0
	
	if "current_speed" in target:
		current_speed_value = float(target.get("current_speed"))
	if "max_speed" in target:
		max_speed_value = maxf(float(target.get("max_speed")), 0.01)
	if max_speed_value > 0.0:
		speed_ratio = clampf(current_speed_value / max_speed_value, 0.0, 1.0)
	
	if speed_ratio <= 0.01 or lead_distance <= 0.0:
		return base_target
	
	var forward := Vector3(-sin(target.rotation.y), 0.0, -cos(target.rotation.y)).normalized()
	var lead_strength := speed_ratio * speed_ratio
	return base_target + forward * lead_distance * lead_strength

## 줌 레벨에 따라 안개 시작/끝 거리를 동적으로 조절합니다.
func _update_dynamic_fog() -> void:
	if not environment: return
	# 줌 변화가 없으면 실행 건너뜀: GPU re-upload 방지
	if abs(current_zoom - _last_zoom) < 0.5: return
	_last_zoom = current_zoom
	# 전투에 적당한 줌아웃 위치에서는 시야를 먼저 가리지 않도록,
	# 기본 시작/종료 거리를 확보한 뒤 줌에 따라 더 뒤로 민다.
	environment.fog_depth_begin = maxf(fog_begin_min, current_zoom * fog_begin_zoom_multiplier)
	environment.fog_depth_end = maxf(fog_end_min, current_zoom * fog_end_zoom_multiplier)
