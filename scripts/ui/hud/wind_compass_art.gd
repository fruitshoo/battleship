extends Node2D

@export_range(40.0, 120.0, 1.0) var radius: float = 78.0
@export var panel_color: Color = Color(0.07, 0.12, 0.15, 0.82)
@export var outer_ring_color: Color = Color(0.76, 0.61, 0.36, 0.98)
@export var inner_ring_color: Color = Color(0.95, 0.84, 0.58, 0.62)
@export var major_tick_color: Color = Color(0.92, 0.84, 0.65, 0.90)
@export var minor_tick_color: Color = Color(0.70, 0.62, 0.45, 0.34)
@export var north_marker_color: Color = Color(0.88, 0.22, 0.18, 0.96)
@export var swirl_color: Color = Color(0.56, 0.72, 0.75, 0.18)
@export var draw_swirl: bool = false

var _swirl_phase: float = 0.0


func _ready() -> void:
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_swirl_phase = wrapf(_swirl_phase + (delta * 0.22), 0.0, TAU)
	queue_redraw()


func set_palette(
	new_panel_color: Color,
	new_outer_ring_color: Color,
	new_inner_ring_color: Color,
	new_major_tick_color: Color,
	new_minor_tick_color: Color,
	new_north_marker_color: Color,
	new_swirl_color: Color
) -> void:
	panel_color = new_panel_color
	outer_ring_color = new_outer_ring_color
	inner_ring_color = new_inner_ring_color
	major_tick_color = new_major_tick_color
	minor_tick_color = new_minor_tick_color
	north_marker_color = new_north_marker_color
	swirl_color = new_swirl_color
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius - 5.0, Color(0.0, 0.0, 0.0, 0.18))
	draw_circle(Vector2.ZERO, radius - 8.0, panel_color)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 96, outer_ring_color, 6.0, true)
	draw_arc(Vector2.ZERO, radius - 7.0, 0.0, TAU, 96, Color(0.28, 0.20, 0.12, 0.72), 2.0, true)
	draw_arc(Vector2.ZERO, radius - 14.0, 0.0, TAU, 96, inner_ring_color, 1.1, true)
	_draw_subtle_waves()
	_draw_ticks()
	if draw_swirl and swirl_color.a > 0.001:
		_draw_swirl_arcs()
	_draw_north_marker()


func _draw_ticks() -> void:
	for i in range(32):
		var angle: float = (TAU / 32.0) * float(i) - PI * 0.5
		var is_major: bool = (i % 8) == 0
		var is_mid: bool = (i % 4) == 0 and not is_major
		var start_radius: float = radius - (25.0 if is_major else 20.0 if is_mid else 15.0)
		var end_radius: float = radius - 13.0
		var thickness: float = 1.9 if is_major else 1.25 if is_mid else 0.75
		var tick_color: Color = major_tick_color if is_major else minor_tick_color
		var start := Vector2.RIGHT.rotated(angle) * start_radius
		var end := Vector2.RIGHT.rotated(angle) * end_radius
		draw_line(start, end, tick_color, thickness, true)


func _draw_subtle_waves() -> void:
	var wave_color := swirl_color
	if wave_color.a <= 0.001:
		return
	for row in range(3):
		var y := -18.0 + float(row) * 15.0
		var width := 22.0 - float(row) * 3.0
		var x_offset := -width * 0.5 + sin(_swirl_phase + float(row)) * 2.0
		var points := PackedVector2Array()
		for i in range(9):
			var t := float(i) / 8.0
			points.append(Vector2(x_offset + t * width, y + sin(t * TAU) * 1.8))
		draw_polyline(points, wave_color, 1.2, true)


func _draw_swirl_arcs() -> void:
	for i in range(3):
		var arc_radius: float = radius - 28.0 - float(i) * 10.0
		var start_angle: float = _swirl_phase + float(i) * 0.85
		var end_angle: float = start_angle + 1.35
		draw_arc(Vector2.ZERO, arc_radius, start_angle, end_angle, 26, swirl_color, 1.6, true)


func _draw_north_marker() -> void:
	var tip := Vector2(0.0, -radius - 2.0)
	var left := Vector2(-7.0, -radius + 13.0)
	var right := Vector2(7.0, -radius + 13.0)
	draw_colored_polygon(PackedVector2Array([tip, left, right]), north_marker_color)
