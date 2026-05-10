class_name ShipDefeatIllustration
extends Control

var ship_id: String = "kobayabune"


func setup(type_id: String) -> void:
	ship_id = type_id.strip_edges().to_lower()
	queue_redraw()


func _ready() -> void:
	custom_minimum_size = Vector2(92.0, 54.0)


func _draw() -> void:
	var w: float = maxf(size.x, 1.0)
	var h: float = maxf(size.y, 1.0)
	var family := _family()
	var wood := Color(0.36, 0.19, 0.14, 1.0)
	var dark_wood := Color(0.18, 0.10, 0.08, 1.0)
	var rail := Color(0.55, 0.18, 0.20, 1.0)
	var sail := Color(0.90, 0.79, 0.55, 1.0)
	var sail_shadow := Color(0.64, 0.48, 0.28, 1.0)
	var gold := Color(0.86, 0.66, 0.28, 1.0)
	var smoke := Color(0.70, 0.76, 0.78, 0.55)

	_draw_ellipse_polygon(Vector2(w * 0.50, h * 0.82), Vector2(w * 0.40, h * 0.07), Color(0.0, 0.0, 0.0, 0.22))

	if family == "atake":
		_draw_atake(w, h, wood, dark_wood, rail, sail, sail_shadow, gold, smoke)
	elif family == "sekibune":
		_draw_sekibune(w, h, wood, dark_wood, rail, sail, sail_shadow, gold, smoke)
	else:
		_draw_kobayabune(w, h, wood, dark_wood, rail, sail, sail_shadow)


func _draw_kobayabune(w: float, h: float, wood: Color, dark_wood: Color, rail: Color, sail: Color, sail_shadow: Color) -> void:
	var hull := PackedVector2Array([
		Vector2(w * 0.11, h * 0.66),
		Vector2(w * 0.28, h * 0.49),
		Vector2(w * 0.72, h * 0.50),
		Vector2(w * 0.88, h * 0.64),
		Vector2(w * 0.74, h * 0.77),
		Vector2(w * 0.25, h * 0.77),
	])
	draw_colored_polygon(hull, wood)
	draw_polyline(hull, dark_wood, 1.5, true)
	draw_line(Vector2(w * 0.23, h * 0.55), Vector2(w * 0.78, h * 0.57), rail, 3.0, true)
	_draw_oars(w, h, 1, dark_wood)
	draw_line(Vector2(w * 0.49, h * 0.20), Vector2(w * 0.49, h * 0.62), dark_wood, 2.0, true)
	_draw_sail(Vector2(w * 0.50, h * 0.21), Vector2(w * 0.49, h * 0.60), w * 0.17, sail, sail_shadow)


func _draw_sekibune(w: float, h: float, wood: Color, dark_wood: Color, rail: Color, sail: Color, sail_shadow: Color, gold: Color, smoke: Color) -> void:
	var hull := PackedVector2Array([
		Vector2(w * 0.07, h * 0.67),
		Vector2(w * 0.20, h * 0.49),
		Vector2(w * 0.76, h * 0.47),
		Vector2(w * 0.93, h * 0.60),
		Vector2(w * 0.79, h * 0.79),
		Vector2(w * 0.22, h * 0.80),
	])
	draw_colored_polygon(hull, wood)
	draw_polyline(hull, dark_wood, 1.5, true)
	draw_rect(Rect2(Vector2(w * 0.56, h * 0.35), Vector2(w * 0.20, h * 0.20)), rail)
	draw_rect(Rect2(Vector2(w * 0.59, h * 0.25), Vector2(w * 0.14, h * 0.12)), dark_wood)
	draw_line(Vector2(w * 0.18, h * 0.56), Vector2(w * 0.84, h * 0.56), rail, 3.0, true)
	_draw_oars(w, h, 2, dark_wood)
	draw_line(Vector2(w * 0.43, h * 0.17), Vector2(w * 0.43, h * 0.62), dark_wood, 2.2, true)
	_draw_sail(Vector2(w * 0.44, h * 0.18), Vector2(w * 0.43, h * 0.61), w * 0.19, sail, sail_shadow)
	if ship_id.contains("cannon") or ship_id.contains("gunner"):
		draw_line(Vector2(w * 0.68, h * 0.42), Vector2(w * 0.91, h * 0.33), dark_wood, 2.4, true)
		draw_circle(Vector2(w * 0.93, h * 0.32), h * 0.035, gold)
		draw_circle(Vector2(w * 0.96, h * 0.28), h * 0.045, smoke)


func _draw_atake(w: float, h: float, wood: Color, dark_wood: Color, rail: Color, sail: Color, sail_shadow: Color, gold: Color, smoke: Color) -> void:
	var hull := PackedVector2Array([
		Vector2(w * 0.05, h * 0.69),
		Vector2(w * 0.17, h * 0.49),
		Vector2(w * 0.80, h * 0.45),
		Vector2(w * 0.96, h * 0.59),
		Vector2(w * 0.82, h * 0.82),
		Vector2(w * 0.20, h * 0.83),
	])
	draw_colored_polygon(hull, wood)
	draw_polyline(hull, dark_wood, 1.7, true)
	draw_rect(Rect2(Vector2(w * 0.46, h * 0.28), Vector2(w * 0.25, h * 0.25)), rail)
	draw_rect(Rect2(Vector2(w * 0.51, h * 0.16), Vector2(w * 0.17, h * 0.15)), dark_wood)
	draw_rect(Rect2(Vector2(w * 0.55, h * 0.09), Vector2(w * 0.10, h * 0.09)), rail)
	draw_line(Vector2(w * 0.15, h * 0.57), Vector2(w * 0.88, h * 0.56), rail, 3.2, true)
	_draw_oars(w, h, 4, dark_wood)
	draw_line(Vector2(w * 0.36, h * 0.14), Vector2(w * 0.36, h * 0.64), dark_wood, 2.4, true)
	_draw_sail(Vector2(w * 0.37, h * 0.15), Vector2(w * 0.36, h * 0.62), w * 0.20, sail, sail_shadow)
	draw_line(Vector2(w * 0.67, h * 0.34), Vector2(w * 0.91, h * 0.25), dark_wood, 2.4, true)
	draw_circle(Vector2(w * 0.93, h * 0.24), h * 0.035, gold)
	if ship_id.contains("final"):
		draw_line(Vector2(w * 0.63, h * 0.09), Vector2(w * 0.63, h * 0.02), dark_wood, 1.3, true)
		draw_colored_polygon(PackedVector2Array([
			Vector2(w * 0.64, h * 0.03),
			Vector2(w * 0.78, h * 0.06),
			Vector2(w * 0.64, h * 0.11),
		]), gold)
		draw_circle(Vector2(w * 0.96, h * 0.20), h * 0.045, smoke)


func _draw_sail(top: Vector2, bottom: Vector2, width: float, sail: Color, sail_shadow: Color) -> void:
	var sail_poly := PackedVector2Array([
		top,
		Vector2(bottom.x + width, bottom.y - 2.0),
		Vector2(bottom.x, bottom.y),
	])
	draw_colored_polygon(sail_poly, sail)
	draw_line(top, Vector2(bottom.x + width, bottom.y - 2.0), sail_shadow, 1.2, true)
	draw_line(Vector2(bottom.x + width * 0.46, bottom.y * 0.66), Vector2(bottom.x + width * 0.18, bottom.y * 0.95), sail_shadow, 1.0, true)


func _draw_oars(w: float, h: float, count: int, color: Color) -> void:
	var start_x := w * 0.30
	var gap := w * 0.12
	for i in range(count):
		var x := start_x + gap * float(i)
		draw_line(Vector2(x, h * 0.68), Vector2(x - w * 0.13, h * 0.88), color, 1.6, true)
		draw_line(Vector2(x + w * 0.08, h * 0.68), Vector2(x + w * 0.21, h * 0.88), color, 1.6, true)


func _draw_ellipse_polygon(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(28):
		var angle := TAU * float(i) / 28.0
		points.append(Vector2(center.x + cos(angle) * radius.x, center.y + sin(angle) * radius.y))
	draw_colored_polygon(points, color)


func _family() -> String:
	if ship_id.contains("atake"):
		return "atake"
	if ship_id.contains("seki"):
		return "sekibune"
	return "kobayabune"
