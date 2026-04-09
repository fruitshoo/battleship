extends Control
const EntityRegistry = preload("res://scripts/helpers/entity_registry.gd")
const NavalUiTheme = preload("res://scripts/ui/naval_ui_theme.gd")

## 배 조작 UI: 현재는 나침반/바람 표시만 담당

@export var controlled_ship: NodePath

var ship: Node3D = null
@onready var wind_indicator: Control = %WindIndicator
@onready var wind_arrow: Node2D = %Arrow
@onready var compass_wheel: Node2D = %CompassWheel
@onready var compass_art: Node2D = %CompassWheel/Art
@onready var compass_background: Panel = %CompassWheel/Background
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
var _glow_phase: float = 0.0


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
	if is_instance_valid(compass_background):
		compass_background.add_theme_stylebox_override(
			"panel",
			NavalUiTheme.make_panel_style(
				NavalUiTheme.PANEL_BG_SOFT,
				NavalUiTheme.BORDER_GOLD_SOFT,
				90,
				2,
				0.0,
				0.0,
				0.0,
				0.0
			)
		)
	if is_instance_valid(compass_art) and compass_art.has_method("set_palette"):
		compass_art.call(
			"set_palette",
			Color(0.05, 0.08, 0.12, 0.12),
			NavalUiTheme.BORDER_GOLD,
			NavalUiTheme.BORDER_GOLD_DIM,
			Color(0.96, 0.89, 0.71, 0.88),
			Color(0.72, 0.64, 0.47, 0.26),
			Color(0.76, 0.31, 0.22, 0.95),
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

	var wind_dir: Vector2 = WindManager.get_wind_direction()
	var wind_angle_rad = atan2(wind_dir.x, -wind_dir.y)
	var wind_strength: float = WindManager.get_wind_strength()
	var target_rotation: float = wind_angle_rad + cam_yaw
	_displayed_arrow_rotation = lerp_angle(_displayed_arrow_rotation, target_rotation, minf(1.0, delta * 9.0))
	var target_scale: float = lerpf(0.92, 1.12, clampf((wind_strength - 0.55) / 0.35, 0.0, 1.0))
	_displayed_arrow_scale = lerpf(_displayed_arrow_scale, target_scale, minf(1.0, delta * 6.0))
	wind_arrow.rotation = _displayed_arrow_rotation
	wind_arrow.scale = Vector2(_displayed_arrow_scale, _displayed_arrow_scale)
	if is_instance_valid(arrow_glow):
		var glow_alpha: float = lerpf(0.10, 0.22, clampf((wind_strength - 0.55) / 0.35, 0.0, 1.0))
		glow_alpha += sin(_glow_phase) * 0.02
		var glow_color: Color = arrow_glow.color
		glow_color.a = clampf(glow_alpha * 0.35, 0.02, 0.08)
		arrow_glow.color = glow_color
