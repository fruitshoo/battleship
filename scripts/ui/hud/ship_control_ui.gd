extends Control

## 배 조작 UI: 현재는 나침반/바람 표시만 담당

@export var controlled_ship: NodePath

var ship: Node3D = null
@onready var wind_panel: PanelContainer = $WindPanel
@onready var wind_indicator: Control = %WindIndicator
@onready var wind_arrow: Node2D = %Arrow
@onready var compass_wheel: Node2D = %CompassWheel
@onready var compass_art: Node2D = %CompassWheel/Art
@onready var compass_frame: Sprite2D = %CompassWheel/CompassFrame
@onready var compass_background: Panel = %CompassWheel/Background
@onready var site_marker: Node2D = %SiteMarker
@onready var site_marker_glow: Polygon2D = %SiteMarker/Glow
@onready var site_marker_dot: Polygon2D = %SiteMarker/Dot
@onready var north_label: Label = %CompassWheel/NorthLabel
@onready var east_label: Label = %CompassWheel/EastLabel
@onready var south_label: Label = %CompassWheel/SouthLabel
@onready var west_label: Label = %CompassWheel/WestLabel
@onready var arrow_tail: Polygon2D = %Arrow/Tail
@onready var arrow_glow: Polygon2D = %Arrow/Glow
@onready var arrow_shaft: ColorRect = %Arrow/Shaft
@onready var arrow_head: Polygon2D = %Arrow/Head
@onready var arrow_center_cap: Polygon2D = %Arrow/CenterCap

var _displayed_compass_rotation: float = 0.0
var _displayed_arrow_rotation: float = 0.0
var _displayed_arrow_scale: float = 1.0
var _displayed_site_marker_position := Vector2.ZERO
var _nearest_site: Node3D = null
var _site_marker_slots: Array[Dictionary] = []
var _site_marker_refresh_left: float = 0.0
var _site_marker_alpha: float = 0.0
var _rock_marker_slots: Array[Dictionary] = []
var _rock_marker_refresh_left: float = 0.0
var _glow_phase: float = 0.0

const SITE_MARKER_REFRESH_INTERVAL: float = 0.18
const SITE_MARKER_OUTER_RADIUS: float = 58.0
const SITE_MARKER_DISTANCE_AT_EDGE: float = 62.0
const SITE_MARKER_FADE_SPEED: float = 5.5
const MAX_SITE_MARKERS: int = 6
const ROCK_MARKER_REFRESH_INTERVAL: float = 0.22
const ROCK_MARKER_OUTER_RADIUS: float = 52.0
const ROCK_MARKER_DISTANCE_AT_EDGE: float = 72.0
const ROCK_MARKER_MAX_DISTANCE: float = 150.0
const ROCK_MARKER_DANGER_DISTANCE: float = 26.0
const MAX_ROCK_MARKERS: int = 5
const BASE_WIND_PANEL_SIZE: float = 180.0
const MAX_WIND_PANEL_SIZE: float = 204.0
const MIN_WIND_PANEL_SIZE: float = 170.0
const SEA_SITE_GROUP := "sea_site"
const TREASURE_CHEST_GROUP := "treasure_chest"
const SEA_ROCK_GROUP := "sea_rock_decor"
const SITE_MARKER_GLOW_COLOR := Color(0.24, 0.64, 1.0, 0.18)
const SITE_MARKER_DOT_COLOR := Color(1.0, 0.88, 0.28, 0.96)
const TREASURE_MARKER_GLOW_COLOR := Color(1.0, 0.62, 0.18, 0.20)
const TREASURE_MARKER_DOT_COLOR := Color(1.0, 0.94, 0.34, 1.0)
const ROCK_MARKER_FILL_COLOR := Color(0.58, 0.65, 0.63, 0.92)
const ROCK_MARKER_SHADOW_COLOR := Color(0.12, 0.16, 0.16, 0.72)
const ROCK_MARKER_DANGER_COLOR := Color(0.94, 0.40, 0.28, 0.96)

var _compass_base_scale: float = 1.0
var _last_layout_viewport_size := Vector2.ZERO
var _layout_update_queued: bool = false


func _resolve_controlled_ship() -> void:
	ship = null
	if controlled_ship != NodePath(""):
		var configured_ship: Node = get_node_or_null(controlled_ship)
		if is_instance_valid(configured_ship):
			ship = configured_ship as Node3D
			return
	var players = EntityRegistry.get_ships_by_team("player")
	for p in players:
		if is_instance_valid(p) and p.get("is_player_controlled") == true:
			ship = p
			return
	if players.size() > 0:
		ship = players[0]


func _ready() -> void:
	_resolve_controlled_ship()
	_apply_theme()
	_apply_layout_density()
	if get_viewport() != null:
		get_viewport().size_changed.connect(_queue_layout_density_update)
	if is_instance_valid(compass_wheel):
		_displayed_compass_rotation = compass_wheel.rotation
	if is_instance_valid(wind_arrow):
		_displayed_arrow_rotation = wind_arrow.rotation


func _process(delta: float) -> void:
	var viewport_size := _get_layout_viewport_size()
	if viewport_size != Vector2.ZERO and viewport_size != _last_layout_viewport_size:
		_apply_layout_density()
	# 카메라 yaw를 반영하므로 매 프레임 갱신해도 부담이 적고 더 자연스럽다.
	if not is_instance_valid(ship):
		_resolve_controlled_ship()
		if not is_instance_valid(ship):
			return
	_update_wind_indicator(delta)


func _apply_theme() -> void:
	if is_instance_valid(wind_panel):
		wind_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	if is_instance_valid(compass_background):
		compass_background.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	if is_instance_valid(compass_frame):
		compass_frame.visible = false
	if is_instance_valid(compass_art) and compass_art.has_method("set_palette"):
		compass_art.call(
			"set_palette",
			Color(0.06, 0.12, 0.15, 0.84),
			Color(0.78, 0.62, 0.36, 0.98),
			Color(0.93, 0.80, 0.54, 0.56),
			Color(0.92, 0.84, 0.65, 0.90),
			Color(0.70, 0.62, 0.45, 0.36),
			Color(0.88, 0.22, 0.18, 0.96),
			Color(0.56, 0.72, 0.75, 0.18)
		)
		compass_art.set("draw_swirl", false)
	NavalUiTheme.style_accent(north_label, 15)
	north_label.add_theme_color_override("font_color", Color(0.82, 0.40, 0.30, 1.0))
	for label in [east_label, south_label, west_label]:
		NavalUiTheme.style_accent(label, 14)
		label.add_theme_color_override("font_color", Color(0.88, 0.82, 0.66, 0.90))
	var arrow_color := Color(0.97, 0.86, 0.62, 1.0)
	var arrow_tail_color := Color(0.60, 0.54, 0.43, 0.66)
	var cap_color := Color(0.96, 0.89, 0.72, 0.96)
	if is_instance_valid(arrow_shaft):
		arrow_shaft.color = arrow_color
		arrow_shaft.offset_left = -2.0
		arrow_shaft.offset_right = 2.0
		arrow_shaft.offset_top = -43.0
		arrow_shaft.offset_bottom = 4.0
	if is_instance_valid(arrow_head):
		arrow_head.color = arrow_color
		arrow_head.polygon = PackedVector2Array([
			Vector2(-8, -43),
			Vector2(8, -43),
			Vector2(0, -63),
		])
	if is_instance_valid(arrow_tail):
		arrow_tail.color = arrow_tail_color
		arrow_tail.polygon = PackedVector2Array([
			Vector2(-4, 6),
			Vector2(4, 6),
			Vector2(0, 20),
		])
	if is_instance_valid(arrow_glow):
		arrow_glow.color = Color(0.96, 0.82, 0.42, 0.06)
		arrow_glow.visible = false
	if is_instance_valid(arrow_center_cap):
		arrow_center_cap.color = cap_color
	_apply_site_marker_palette_to_marker(site_marker, null)
	_sync_rock_marker_slots([])

func _apply_layout_density() -> void:
	var viewport := get_viewport()
	if viewport == null or not is_instance_valid(wind_panel):
		return
	var viewport_size := viewport.get_visible_rect().size
	if viewport_size == Vector2.ZERO:
		return
	_last_layout_viewport_size = viewport_size
	_layout_update_queued = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0

	var panel_size := clampf(min(viewport_size.x, viewport_size.y) * 0.20, MIN_WIND_PANEL_SIZE, MAX_WIND_PANEL_SIZE)
	var panel_margin := roundf(lerpf(12.0, 20.0, clampf((panel_size - MIN_WIND_PANEL_SIZE) / (MAX_WIND_PANEL_SIZE - MIN_WIND_PANEL_SIZE), 0.0, 1.0)))
	var top_offset := roundf(clampf(viewport_size.y * 0.028, 26.0, 32.0))
	wind_panel.anchor_left = 0.0
	wind_panel.anchor_right = 0.0
	wind_panel.anchor_top = 0.0
	wind_panel.anchor_bottom = 0.0
	wind_panel.offset_left = maxf(panel_margin, viewport_size.x - panel_margin - panel_size)
	wind_panel.offset_top = top_offset
	wind_panel.offset_right = wind_panel.offset_left + panel_size
	wind_panel.offset_bottom = top_offset + panel_size
	wind_panel.custom_minimum_size = Vector2(panel_size, panel_size)
	if is_instance_valid(wind_indicator):
		wind_indicator.custom_minimum_size = Vector2(panel_size, panel_size)
		wind_indicator.anchor_left = 0.5
		wind_indicator.anchor_right = 0.5
		wind_indicator.anchor_top = 0.5
		wind_indicator.anchor_bottom = 0.5
		wind_indicator.offset_left = -panel_size * 0.5
		wind_indicator.offset_top = -panel_size * 0.5
		wind_indicator.offset_right = panel_size * 0.5
		wind_indicator.offset_bottom = panel_size * 0.5
	var center := Vector2(panel_size * 0.5, panel_size * 0.5)
	_compass_base_scale = panel_size / BASE_WIND_PANEL_SIZE
	if is_instance_valid(compass_wheel):
		compass_wheel.position = center
		compass_wheel.scale = Vector2.ONE * _compass_base_scale
	if is_instance_valid(wind_arrow):
		wind_arrow.position = center


func _queue_layout_density_update() -> void:
	if _layout_update_queued:
		return
	_layout_update_queued = true
	call_deferred("_apply_layout_density")


func _get_layout_viewport_size() -> Vector2:
	var viewport := get_viewport()
	if viewport == null:
		return Vector2.ZERO
	return viewport.get_visible_rect().size

func _update_wind_indicator(delta: float) -> void:
	if not is_instance_valid(WindManager):
		return

	_glow_phase = wrapf(_glow_phase + delta * 2.0, 0.0, TAU)
	var cam = get_viewport().get_camera_3d()
	var cam_yaw = 0.0
	if is_instance_valid(cam):
		cam_yaw = cam.global_rotation.y

	if compass_wheel:
		_displayed_compass_rotation = lerp_angle(_displayed_compass_rotation, cam_yaw, minf(1.0, delta * 7.5))
		compass_wheel.rotation = _displayed_compass_rotation
		if is_instance_valid(compass_frame):
			compass_frame.rotation = -_displayed_compass_rotation

	var wind_dir: Vector2 = WindManager.get_wind_direction()
	var wind_angle_rad = atan2(wind_dir.x, -wind_dir.y)
	var wind_strength: float = WindManager.get_wind_strength()
	var target_rotation: float = wind_angle_rad + cam_yaw
	_displayed_arrow_rotation = lerp_angle(_displayed_arrow_rotation, target_rotation, minf(1.0, delta * 9.0))
	var target_scale: float = lerpf(0.92, 1.12, clampf((wind_strength - 0.55) / 0.35, 0.0, 1.0))
	_displayed_arrow_scale = lerpf(_displayed_arrow_scale, target_scale, minf(1.0, delta * 6.0))
	wind_arrow.rotation = _displayed_arrow_rotation
	wind_arrow.scale = Vector2.ONE * (_displayed_arrow_scale * _compass_base_scale)
	if is_instance_valid(arrow_glow):
		var glow_alpha: float = lerpf(0.10, 0.22, clampf((wind_strength - 0.55) / 0.35, 0.0, 1.0))
		glow_alpha += sin(_glow_phase) * 0.02
		var glow_color: Color = arrow_glow.color
		glow_color.a = clampf(glow_alpha * 0.35, 0.02, 0.08)
		arrow_glow.color = glow_color
	_update_site_marker(delta)
	_update_rock_markers(delta)


func _update_site_marker(delta: float) -> void:
	if not is_instance_valid(site_marker) or not is_instance_valid(compass_wheel) or not is_instance_valid(ship):
		return

	_site_marker_refresh_left -= delta
	if _site_marker_refresh_left <= 0.0:
		_site_marker_refresh_left = SITE_MARKER_REFRESH_INTERVAL
		_sync_site_marker_slots(_collect_site_marker_targets())

	var active_count := 0
	for slot_index in range(_site_marker_slots.size()):
		var slot := _site_marker_slots[slot_index]
		var marker_variant: Variant = slot.get("node", null)
		if not is_instance_valid(marker_variant) or not (marker_variant is Node2D):
			continue
		var marker := marker_variant as Node2D

		var target_variant: Variant = slot.get("site", null)
		if not _is_valid_site_marker_target(target_variant):
			slot["site"] = null
			slot["site_id"] = 0
			slot["alpha"] = 0.0
			_site_marker_slots[slot_index] = slot
			marker.visible = false
			continue
		var target := target_variant as Node3D
		if not _is_valid_site_marker_target(target):
			marker.visible = false
			continue

		var offset := target.global_position - ship.global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance <= 0.01:
			marker.visible = false
			continue

		var distance_ratio := _get_site_marker_distance_ratio(distance)
		var target_position := _get_site_marker_target_position(offset)
		var displayed_position: Vector2 = slot.get("position", target_position)
		var target_id := int(target.get_instance_id())
		if int(slot.get("site_id", 0)) != target_id or not marker.visible:
			displayed_position = target_position
			slot["alpha"] = 0.0
			slot["site_id"] = target_id
		else:
			var follow_weight := minf(1.0, delta * lerpf(18.0, 9.0, distance_ratio))
			displayed_position = displayed_position.lerp(target_position, follow_weight)

		var alpha := move_toward(float(slot.get("alpha", 0.0)), 1.0, delta * SITE_MARKER_FADE_SPEED)
		slot["position"] = displayed_position
		slot["alpha"] = alpha
		marker.position = displayed_position
		marker.modulate = Color(1.0, 1.0, 1.0, alpha)
		marker.visible = true
		_apply_site_marker_palette_to_marker(marker, target)
		_apply_site_marker_pulse(marker, distance_ratio)
		_site_marker_slots[slot_index] = slot
		active_count += 1

	_site_marker_alpha = 1.0 if active_count > 0 else 0.0


func _update_rock_markers(delta: float) -> void:
	if not is_instance_valid(compass_wheel) or not is_instance_valid(ship):
		return

	_rock_marker_refresh_left -= delta
	if _rock_marker_refresh_left <= 0.0:
		_rock_marker_refresh_left = ROCK_MARKER_REFRESH_INTERVAL
		_sync_rock_marker_slots(_collect_rock_marker_targets())

	for slot_index in range(_rock_marker_slots.size()):
		var slot := _rock_marker_slots[slot_index]
		var marker_variant: Variant = slot.get("node", null)
		if not is_instance_valid(marker_variant) or not (marker_variant is Node2D):
			continue
		var marker := marker_variant as Node2D
		var rock_variant: Variant = slot.get("rock", null)
		if not _is_valid_rock_marker_target(rock_variant):
			slot["rock"] = null
			slot["rock_id"] = 0
			slot["alpha"] = 0.0
			_rock_marker_slots[slot_index] = slot
			marker.visible = false
			continue

		var rock := rock_variant as Node3D
		var offset := rock.global_position - ship.global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance <= 0.01 or distance > ROCK_MARKER_MAX_DISTANCE:
			marker.visible = false
			continue

		var distance_ratio := _get_rock_marker_distance_ratio(distance)
		var target_position := _get_marker_target_position(offset, ROCK_MARKER_OUTER_RADIUS, ROCK_MARKER_DISTANCE_AT_EDGE)
		var displayed_position: Vector2 = slot.get("position", target_position)
		var target_id := int(rock.get_instance_id())
		if int(slot.get("rock_id", 0)) != target_id or not marker.visible:
			displayed_position = target_position
			slot["alpha"] = 0.0
			slot["rock_id"] = target_id
		else:
			displayed_position = displayed_position.lerp(target_position, minf(1.0, delta * lerpf(16.0, 8.0, distance_ratio)))

		var alpha := move_toward(float(slot.get("alpha", 0.0)), 1.0, delta * SITE_MARKER_FADE_SPEED)
		slot["position"] = displayed_position
		slot["alpha"] = alpha
		marker.position = displayed_position
		marker.modulate = Color(1.0, 1.0, 1.0, alpha)
		marker.visible = true
		_apply_marker_screen_upright(marker)
		_apply_rock_marker_palette(marker, distance)
		_rock_marker_slots[slot_index] = slot


func _sync_rock_marker_slots(targets: Array[Node3D]) -> void:
	for index in range(MAX_ROCK_MARKERS):
		var marker := _ensure_rock_marker_slot(index)
		if not is_instance_valid(marker):
			continue
		if index >= targets.size():
			marker.visible = false
			if index < _rock_marker_slots.size():
				var inactive_slot := _rock_marker_slots[index]
				inactive_slot["rock"] = null
				inactive_slot["rock_id"] = 0
				inactive_slot["alpha"] = 0.0
				_rock_marker_slots[index] = inactive_slot
			continue

		var rock := targets[index]
		var offset := rock.global_position - ship.global_position
		offset.y = 0.0
		var target_position := _get_marker_target_position(offset, ROCK_MARKER_OUTER_RADIUS, ROCK_MARKER_DISTANCE_AT_EDGE)
		var slot := _rock_marker_slots[index]
		if int(slot.get("rock_id", 0)) != int(rock.get_instance_id()):
			slot["position"] = target_position
			slot["alpha"] = 0.0
		slot["rock"] = rock
		slot["rock_id"] = int(rock.get_instance_id())
		_rock_marker_slots[index] = slot


func _ensure_rock_marker_slot(index: int) -> Node2D:
	while _rock_marker_slots.size() <= index:
		var marker := _make_rock_marker()
		if is_instance_valid(marker):
			marker.name = "RockMarker%d" % _rock_marker_slots.size()
			compass_wheel.add_child(marker)
		if not is_instance_valid(marker):
			return null
		marker.visible = false
		_rock_marker_slots.append({
			"node": marker,
			"rock": null,
			"rock_id": 0,
			"position": Vector2.ZERO,
			"alpha": 0.0,
		})
	var marker_variant: Variant = _rock_marker_slots[index].get("node", null)
	if is_instance_valid(marker_variant) and marker_variant is Node2D:
		return marker_variant as Node2D
	return null


func _make_rock_marker() -> Node2D:
	var marker := Node2D.new()

	var shadow := Polygon2D.new()
	shadow.name = "Shadow"
	shadow.color = ROCK_MARKER_SHADOW_COLOR
	shadow.polygon = PackedVector2Array([
		Vector2(-6.5, 4.0),
		Vector2(-2.2, -5.0),
		Vector2(2.8, -2.8),
		Vector2(6.0, 4.0),
	])
	marker.add_child(shadow)

	var crest := Polygon2D.new()
	crest.name = "Crest"
	crest.color = ROCK_MARKER_FILL_COLOR
	crest.polygon = PackedVector2Array([
		Vector2(-4.8, 3.0),
		Vector2(-1.7, -4.8),
		Vector2(1.0, -1.3),
		Vector2(3.6, -4.0),
		Vector2(5.3, 3.0),
	])
	marker.add_child(crest)
	return marker


func _apply_marker_screen_upright(marker: Node2D) -> void:
	if not is_instance_valid(marker):
		return
	marker.rotation = -_displayed_compass_rotation


func _sync_site_marker_slots(targets: Array[Node3D]) -> void:
	_nearest_site = targets[0] if not targets.is_empty() else null
	for index in range(MAX_SITE_MARKERS):
		var marker := _ensure_site_marker_slot(index)
		if not is_instance_valid(marker):
			continue
		if index >= targets.size():
			marker.visible = false
			if index < _site_marker_slots.size():
				var inactive_slot := _site_marker_slots[index]
				inactive_slot["site"] = null
				inactive_slot["site_id"] = 0
				inactive_slot["alpha"] = 0.0
				_site_marker_slots[index] = inactive_slot
			continue

		var target := targets[index]
		var offset := target.global_position - ship.global_position
		offset.y = 0.0
		var target_position := _get_site_marker_target_position(offset)
		var slot := _site_marker_slots[index]
		if int(slot.get("site_id", 0)) != int(target.get_instance_id()):
			slot["position"] = target_position
			slot["alpha"] = 0.0
		slot["site"] = target
		slot["site_id"] = int(target.get_instance_id())
		_site_marker_slots[index] = slot


func _ensure_site_marker_slot(index: int) -> Node2D:
	while _site_marker_slots.size() <= index:
		var marker: Node2D = site_marker if _site_marker_slots.is_empty() else null
		if marker == null:
			marker = site_marker.duplicate() as Node2D
			if is_instance_valid(marker):
				marker.name = "SiteMarkerExtra%d" % _site_marker_slots.size()
				compass_wheel.add_child(marker)
		if not is_instance_valid(marker):
			return null
		marker.visible = false
		_site_marker_slots.append({
			"node": marker,
			"site": null,
			"site_id": 0,
			"position": Vector2.ZERO,
			"alpha": 0.0,
		})
	var marker_variant: Variant = _site_marker_slots[index].get("node", null)
	if is_instance_valid(marker_variant) and marker_variant is Node2D:
		return marker_variant as Node2D
	return null


func _get_site_marker_target_position(offset: Vector3) -> Vector2:
	return _get_marker_target_position(offset, SITE_MARKER_OUTER_RADIUS, SITE_MARKER_DISTANCE_AT_EDGE)


func _get_marker_target_position(offset: Vector3, outer_radius: float, distance_at_edge: float) -> Vector2:
	var flat_offset := offset
	flat_offset.y = 0.0
	var distance := flat_offset.length()
	if distance <= 0.01:
		return Vector2.ZERO
	var angle := atan2(flat_offset.x, -flat_offset.z)
	return Vector2(sin(angle), -cos(angle)) * _get_marker_radius(distance, outer_radius, distance_at_edge)


func _get_site_marker_radius(distance: float) -> float:
	return _get_marker_radius(distance, SITE_MARKER_OUTER_RADIUS, SITE_MARKER_DISTANCE_AT_EDGE)


func _get_marker_radius(distance: float, outer_radius: float, distance_at_edge: float) -> float:
	var distance_ratio := clampf(distance / maxf(distance_at_edge, 0.01), 0.0, 1.0)
	return outer_radius * smoothstep(0.0, 1.0, distance_ratio)


func _get_site_marker_distance_ratio(distance: float) -> float:
	return clampf(distance / SITE_MARKER_DISTANCE_AT_EDGE, 0.0, 1.0)


func _get_rock_marker_distance_ratio(distance: float) -> float:
	return clampf(distance / ROCK_MARKER_DISTANCE_AT_EDGE, 0.0, 1.0)


func _collect_rock_marker_targets() -> Array[Node3D]:
	var candidates: Array[Dictionary] = []
	for candidate in get_tree().get_nodes_in_group(SEA_ROCK_GROUP):
		if not _is_valid_rock_marker_target(candidate):
			continue
		var rock := candidate as Node3D
		var offset := rock.global_position - ship.global_position
		offset.y = 0.0
		var distance_sq := offset.length_squared()
		if distance_sq > ROCK_MARKER_MAX_DISTANCE * ROCK_MARKER_MAX_DISTANCE:
			continue
		candidates.append({
			"rock": rock,
			"distance_sq": distance_sq,
		})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("distance_sq", INF)) < float(b.get("distance_sq", INF))
	)
	var targets: Array[Node3D] = []
	for candidate in candidates:
		if targets.size() >= MAX_ROCK_MARKERS:
			break
		var rock := candidate.get("rock", null) as Node3D
		if _is_valid_rock_marker_target(rock):
			targets.append(rock)
	return targets


func _collect_site_marker_targets() -> Array[Node3D]:
	var candidates: Array[Dictionary] = []
	var seen: Dictionary = {}
	_append_site_marker_candidates(candidates, seen, TREASURE_CHEST_GROUP, 2)
	_append_site_marker_candidates(candidates, seen, SEA_SITE_GROUP, 1)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var priority_a := int(a.get("priority", 0))
		var priority_b := int(b.get("priority", 0))
		if priority_a != priority_b:
			return priority_a > priority_b
		return float(a.get("distance_sq", INF)) < float(b.get("distance_sq", INF))
	)
	var targets: Array[Node3D] = []
	for candidate in candidates:
		if targets.size() >= MAX_SITE_MARKERS:
			break
		var site := candidate.get("site", null) as Node3D
		if _is_valid_site_marker_target(site):
			targets.append(site)
	return targets


func _append_site_marker_candidates(candidates: Array[Dictionary], seen: Dictionary, group_name: String, priority: int) -> void:
	for candidate in get_tree().get_nodes_in_group(group_name):
		if not is_instance_valid(candidate) or not (candidate is Node3D):
			continue
		var site := candidate as Node3D
		if not _is_valid_site_marker_target(site):
			continue
		var site_id := int(site.get_instance_id())
		if seen.has(site_id):
			continue
		seen[site_id] = true
		var offset := site.global_position - ship.global_position
		offset.y = 0.0
		candidates.append({
			"site": site,
			"priority": priority,
			"distance_sq": offset.length_squared(),
		})


func _find_nearest_site() -> Node3D:
	var closest_treasure := _find_nearest_site_in_group(TREASURE_CHEST_GROUP)
	if is_instance_valid(closest_treasure):
		return closest_treasure
	return _find_nearest_site_in_group(SEA_SITE_GROUP)


func _find_nearest_site_in_group(group_name: String) -> Node3D:
	var closest_site: Node3D = null
	var closest_distance_sq := INF
	for candidate in get_tree().get_nodes_in_group(group_name):
		if not is_instance_valid(candidate) or not (candidate is Node3D):
			continue
		var site := candidate as Node3D
		if not _is_valid_site_marker_target(site):
			continue
		var offset := site.global_position - ship.global_position
		offset.y = 0.0
		var distance_sq := offset.length_squared()
		if distance_sq < closest_distance_sq:
			closest_distance_sq = distance_sq
			closest_site = site
	return closest_site


func _is_valid_site_marker_target(site: Variant) -> bool:
	if not is_instance_valid(site) or not (site is Node3D):
		return false
	if not site.is_inside_tree():
		return false
	if site.is_queued_for_deletion():
		return false
	if _is_treasure_marker_target(site) and site.get("_is_collected") == true:
		return false
	if site.get("is_collected") != null and site.get("is_collected") == true:
		return false
	return true


func _is_valid_rock_marker_target(rock: Variant) -> bool:
	if not is_instance_valid(rock) or not (rock is Node3D):
		return false
	if not rock.is_inside_tree():
		return false
	if rock.is_queued_for_deletion():
		return false
	return rock.is_in_group(SEA_ROCK_GROUP)


func _is_treasure_marker_target(site: Variant) -> bool:
	return is_instance_valid(site) and site.is_in_group(TREASURE_CHEST_GROUP)


func _apply_site_marker_palette(target: Variant) -> void:
	_apply_site_marker_palette_to_marker(site_marker, target)


func _apply_site_marker_palette_to_marker(marker: Node2D, target: Variant) -> void:
	if not is_instance_valid(marker):
		return
	var is_treasure := _is_treasure_marker_target(target)
	var glow := marker.get_node_or_null("Glow") as Polygon2D
	var dot := marker.get_node_or_null("Dot") as Polygon2D
	if is_instance_valid(glow):
		glow.color = TREASURE_MARKER_GLOW_COLOR if is_treasure else SITE_MARKER_GLOW_COLOR
	if is_instance_valid(dot):
		dot.color = TREASURE_MARKER_DOT_COLOR if is_treasure else SITE_MARKER_DOT_COLOR


func _apply_site_marker_pulse(marker: Node2D, distance_ratio: float) -> void:
	if not is_instance_valid(marker):
		return
	var pulse := 0.12 + sin(_glow_phase * 1.7) * 0.035
	var glow := marker.get_node_or_null("Glow") as Polygon2D
	var dot := marker.get_node_or_null("Dot") as Polygon2D
	if is_instance_valid(glow):
		glow.modulate = Color(1.0, 1.0, 1.0, clampf(pulse, 0.06, 0.18))
	if is_instance_valid(dot):
		dot.modulate = Color(1.0, 1.0, 1.0, lerpf(0.82, 1.0, 1.0 - distance_ratio))


func _apply_rock_marker_palette(marker: Node2D, distance: float) -> void:
	if not is_instance_valid(marker):
		return
	var danger_ratio := clampf(1.0 - distance / ROCK_MARKER_DANGER_DISTANCE, 0.0, 1.0)
	var fill := ROCK_MARKER_FILL_COLOR.lerp(ROCK_MARKER_DANGER_COLOR, danger_ratio)
	var shadow := ROCK_MARKER_SHADOW_COLOR.lerp(Color(0.38, 0.12, 0.10, 0.82), danger_ratio)
	var crest := marker.get_node_or_null("Crest") as Polygon2D
	var shadow_poly := marker.get_node_or_null("Shadow") as Polygon2D
	if is_instance_valid(crest):
		crest.color = fill
	if is_instance_valid(shadow_poly):
		shadow_poly.color = shadow
	var pulse := 1.0 + sin(_glow_phase * 2.1) * 0.08 * danger_ratio
	marker.scale = Vector2.ONE * pulse
