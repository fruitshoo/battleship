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
var _site_marker_refresh_left: float = 0.0
var _site_marker_alpha: float = 0.0
var _glow_phase: float = 0.0

const SITE_MARKER_REFRESH_INTERVAL: float = 0.18
const SITE_MARKER_OUTER_RADIUS: float = 64.0
const SITE_MARKER_DISTANCE_AT_EDGE: float = 90.0
const SITE_MARKER_FADE_SPEED: float = 5.5
const BASE_WIND_PANEL_SIZE: float = 220.0
const SEA_SITE_GROUP := "sea_site"
const TREASURE_CHEST_GROUP := "treasure_chest"
const SITE_MARKER_GLOW_COLOR := Color(0.24, 0.64, 1.0, 0.18)
const SITE_MARKER_DOT_COLOR := Color(1.0, 0.88, 0.28, 0.96)
const TREASURE_MARKER_GLOW_COLOR := Color(1.0, 0.62, 0.18, 0.20)
const TREASURE_MARKER_DOT_COLOR := Color(1.0, 0.94, 0.34, 1.0)

var _compass_base_scale: float = 1.0


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
		get_viewport().size_changed.connect(_apply_layout_density)
	if is_instance_valid(compass_wheel):
		_displayed_compass_rotation = compass_wheel.rotation
	if is_instance_valid(wind_arrow):
		_displayed_arrow_rotation = wind_arrow.rotation


func _process(delta: float) -> void:
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
		compass_background.add_theme_stylebox_override(
			"panel",
			NavalUiTheme.make_panel_style(
				Color(0.04, 0.08, 0.12, 0.52),
				NavalUiTheme.BORDER_GOLD_SOFT,
				90,
				1,
				0.0,
				0.0,
				0.0,
				0.0
			)
		)
	if is_instance_valid(compass_art) and compass_art.has_method("set_palette"):
		compass_art.call(
			"set_palette",
			Color(0.05, 0.08, 0.12, 0.0),
			Color(0.82, 0.69, 0.42, 0.10),
			Color(0.55, 0.47, 0.27, 0.08),
			Color(0.96, 0.89, 0.71, 0.42),
			Color(0.72, 0.64, 0.47, 0.08),
			Color(0.76, 0.31, 0.22, 0.82),
			Color(0.92, 0.84, 0.66, 0.0)
		)
		compass_art.set("draw_swirl", false)
	NavalUiTheme.style_accent(north_label, 18)
	north_label.add_theme_color_override("font_color", Color(0.82, 0.40, 0.30, 1.0))
	for label in [east_label, south_label, west_label]:
		NavalUiTheme.style_accent(label, 18)
	var arrow_color := Color(0.97, 0.86, 0.62, 1.0)
	var arrow_tail_color := Color(0.60, 0.54, 0.43, 0.66)
	var cap_color := Color(0.96, 0.89, 0.72, 0.96)
	if is_instance_valid(arrow_shaft):
		arrow_shaft.color = arrow_color
		arrow_shaft.offset_left = -2.5
		arrow_shaft.offset_right = 2.5
		arrow_shaft.offset_top = -46.0
		arrow_shaft.offset_bottom = 4.0
	if is_instance_valid(arrow_head):
		arrow_head.color = arrow_color
		arrow_head.polygon = PackedVector2Array([
			Vector2(-9, -46),
			Vector2(9, -46),
			Vector2(0, -66),
		])
	if is_instance_valid(arrow_tail):
		arrow_tail.color = arrow_tail_color
		arrow_tail.polygon = PackedVector2Array([
			Vector2(-5, 6),
			Vector2(5, 6),
			Vector2(0, 22),
		])
	if is_instance_valid(arrow_glow):
		arrow_glow.color = Color(0.96, 0.82, 0.42, 0.06)
		arrow_glow.visible = false
	if is_instance_valid(arrow_center_cap):
		arrow_center_cap.color = cap_color
	_apply_site_marker_palette(_nearest_site)

func _apply_layout_density() -> void:
	var viewport := get_viewport()
	if viewport == null or not is_instance_valid(wind_panel):
		return
	var viewport_size := viewport.get_visible_rect().size
	var panel_size := clampf(min(viewport_size.x, viewport_size.y) * 0.17, 156.0, BASE_WIND_PANEL_SIZE)
	var panel_margin := roundf(lerpf(12.0, 20.0, clampf((panel_size - 164.0) / (BASE_WIND_PANEL_SIZE - 164.0), 0.0, 1.0)))
	var top_offset := roundf(clampf(viewport_size.y * 0.07, 48.0, 72.0))
	wind_panel.offset_left = -panel_size - panel_margin
	wind_panel.offset_top = top_offset
	wind_panel.offset_right = -panel_margin
	wind_panel.offset_bottom = top_offset + panel_size
	if is_instance_valid(wind_indicator):
		wind_indicator.custom_minimum_size = Vector2(panel_size, panel_size)
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


func _update_site_marker(delta: float) -> void:
	if not is_instance_valid(site_marker) or not is_instance_valid(ship):
		return

	_site_marker_refresh_left -= delta
	var previous_site := _nearest_site
	if not _is_valid_site_marker_target(previous_site):
		previous_site = null
	if _site_marker_refresh_left <= 0.0 or not _is_valid_site_marker_target(_nearest_site):
		_site_marker_refresh_left = SITE_MARKER_REFRESH_INTERVAL
		_nearest_site = _find_nearest_site()

	if not _is_valid_site_marker_target(_nearest_site):
		_nearest_site = null
		_site_marker_alpha = move_toward(_site_marker_alpha, 0.0, delta * SITE_MARKER_FADE_SPEED)
		site_marker.modulate = Color(1.0, 1.0, 1.0, _site_marker_alpha)
		site_marker.visible = false
		return

	var offset := _nearest_site.global_position - ship.global_position
	offset.y = 0.0
	var distance := offset.length()
	if distance <= 0.01:
		site_marker.visible = false
		return

	var distance_ratio := _get_site_marker_distance_ratio(distance)
	var target_position := _get_site_marker_target_position(offset)
	if previous_site != _nearest_site or not site_marker.visible or _site_marker_alpha <= 0.01:
		_displayed_site_marker_position = target_position
		_site_marker_alpha = 0.0
	else:
		var follow_weight := minf(1.0, delta * lerpf(18.0, 9.0, distance_ratio))
		_displayed_site_marker_position = _displayed_site_marker_position.lerp(target_position, follow_weight)
	site_marker.position = _displayed_site_marker_position
	_site_marker_alpha = move_toward(_site_marker_alpha, 1.0, delta * SITE_MARKER_FADE_SPEED)
	site_marker.modulate = Color(1.0, 1.0, 1.0, _site_marker_alpha)
	site_marker.visible = true
	_apply_site_marker_palette(_nearest_site)

	var pulse := 0.12 + sin(_glow_phase * 1.7) * 0.035
	if is_instance_valid(site_marker_glow):
		site_marker_glow.modulate = Color(1.0, 1.0, 1.0, clampf(pulse, 0.06, 0.18))
	if is_instance_valid(site_marker_dot):
		site_marker_dot.modulate = Color(1.0, 1.0, 1.0, lerpf(0.82, 1.0, 1.0 - distance_ratio))


func _get_site_marker_target_position(offset: Vector3) -> Vector2:
	var flat_offset := offset
	flat_offset.y = 0.0
	var distance := flat_offset.length()
	if distance <= 0.01:
		return Vector2.ZERO
	var angle := atan2(flat_offset.x, -flat_offset.z)
	return Vector2(sin(angle), -cos(angle)) * _get_site_marker_radius(distance)


func _get_site_marker_radius(distance: float) -> float:
	var distance_ratio := _get_site_marker_distance_ratio(distance)
	return SITE_MARKER_OUTER_RADIUS * smoothstep(0.0, 1.0, distance_ratio)


func _get_site_marker_distance_ratio(distance: float) -> float:
	return clampf(distance / SITE_MARKER_DISTANCE_AT_EDGE, 0.0, 1.0)


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


func _is_treasure_marker_target(site: Variant) -> bool:
	return is_instance_valid(site) and site.is_in_group(TREASURE_CHEST_GROUP)


func _apply_site_marker_palette(target: Variant) -> void:
	var is_treasure := _is_treasure_marker_target(target)
	if is_instance_valid(site_marker_glow):
		site_marker_glow.color = TREASURE_MARKER_GLOW_COLOR if is_treasure else SITE_MARKER_GLOW_COLOR
	if is_instance_valid(site_marker_dot):
		site_marker_dot.color = TREASURE_MARKER_DOT_COLOR if is_treasure else SITE_MARKER_DOT_COLOR
