extends ProgressBar
class_name HudGaugeBar

## ProgressBar-compatible HUD gauge with a delayed damage trail and subtle material polish.

@export var damage_trail_enabled: bool = true
@export var low_pulse_enabled: bool = false
@export var segment_count: int = 0
@export_range(0.0, 1.0, 0.01) var low_pulse_threshold: float = 0.25
@export_range(0.0, 1.0, 0.01) var shine_strength: float = 0.28
@export_range(0.0, 2.0, 0.01) var trail_hold_seconds: float = 0.14
@export_range(0.1, 12.0, 0.1) var trail_follow_speed: float = 2.8

var _display_ratio: float = 0.0
var _trail_ratio: float = 0.0
var _last_target_ratio: float = -1.0
var _trail_hold_left: float = 0.0
var _pulse_time: float = 0.0
var _last_bg_color: Color = Color.TRANSPARENT
var _last_fill_color: Color = Color.TRANSPARENT


func _ready() -> void:
	show_percentage = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_display_ratio = _get_target_ratio()
	_trail_ratio = _display_ratio
	_last_target_ratio = _display_ratio
	value_changed.connect(_on_value_changed)
	resized.connect(_on_resized)
	set_process(true)
	queue_redraw()


func configure_gauge(bg_color: Color, fill_color: Color, radius: int = 4, options: Dictionary = {}) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = bg_color
	bg.border_color = options.get("border_color", NavalUiTheme.BORDER_GOLD_DIM)
	bg.set_border_width_all(int(options.get("border_width", 1)))
	bg.set_corner_radius_all(radius)
	add_theme_stylebox_override("background", bg)

	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(maxi(1, radius - 1))
	add_theme_stylebox_override("fill", fill)

	damage_trail_enabled = bool(options.get("damage_trail", damage_trail_enabled))
	low_pulse_enabled = bool(options.get("low_pulse", low_pulse_enabled))
	segment_count = int(options.get("segments", segment_count))
	low_pulse_threshold = float(options.get("low_pulse_threshold", low_pulse_threshold))
	shine_strength = float(options.get("shine_strength", shine_strength))
	trail_follow_speed = float(options.get("trail_follow_speed", trail_follow_speed))
	trail_hold_seconds = float(options.get("trail_hold_seconds", trail_hold_seconds))
	queue_redraw()


func _process(delta: float) -> void:
	var target_ratio := _get_target_ratio()
	_pulse_time += delta

	if _last_target_ratio < -0.5:
		_last_target_ratio = target_ratio
		_display_ratio = target_ratio
		_trail_ratio = target_ratio
	elif target_ratio < _last_target_ratio - 0.001:
		_trail_hold_left = trail_hold_seconds
		_last_target_ratio = target_ratio
	elif target_ratio > _last_target_ratio + 0.001:
		_last_target_ratio = target_ratio

	var display_speed := 12.0 if target_ratio >= _display_ratio else 18.0
	_display_ratio = _approach_ratio(_display_ratio, target_ratio, delta, display_speed)

	if damage_trail_enabled and target_ratio < _trail_ratio:
		_trail_hold_left = maxf(0.0, _trail_hold_left - delta)
		if _trail_hold_left <= 0.0:
			_trail_ratio = _approach_ratio(_trail_ratio, target_ratio, delta, trail_follow_speed)
	else:
		_trail_ratio = maxf(_display_ratio, target_ratio)

	var bg_color := _get_stylebox_color("background", Color(0.04, 0.05, 0.07, 0.90))
	var fill_color := _get_stylebox_color("fill", NavalUiTheme.STATUS_GOOD)
	var style_changed := bg_color != _last_bg_color or fill_color != _last_fill_color
	_last_bg_color = bg_color
	_last_fill_color = fill_color

	if style_changed or absf(_display_ratio - target_ratio) > 0.001 or absf(_trail_ratio - target_ratio) > 0.001 or low_pulse_enabled:
		queue_redraw()


func _draw() -> void:
	if size.x <= 1.0 or size.y <= 1.0:
		return

	var radius := _get_background_radius()
	var outer := Rect2(Vector2.ZERO, size)
	var bg_color := _get_stylebox_color("background", Color(0.04, 0.05, 0.07, 0.90))
	var fill_color := _get_stylebox_color("fill", NavalUiTheme.STATUS_GOOD)
	var border_color := _get_background_border_color()

	_draw_flat_box(outer, bg_color, radius, border_color, 1)

	var pad := 2.0 if size.y >= 12.0 else 1.0
	var inner := Rect2(Vector2(pad, pad), Vector2(maxf(0.0, size.x - pad * 2.0), maxf(0.0, size.y - pad * 2.0)))
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return

	draw_rect(inner, Color(0.0, 0.0, 0.0, 0.18), true)

	var trail_w := inner.size.x * clampf(_trail_ratio, 0.0, 1.0)
	var fill_w := inner.size.x * clampf(_display_ratio, 0.0, 1.0)
	if damage_trail_enabled and trail_w > fill_w + 0.5:
		var trail_rect := Rect2(inner.position, Vector2(trail_w, inner.size.y))
		_draw_flat_box(trail_rect, Color(0.95, 0.30, 0.18, 0.48), maxi(1, radius - 1), Color.TRANSPARENT, 0)

	if fill_w > 0.5:
		var fill_rect := Rect2(inner.position, Vector2(fill_w, inner.size.y))
		_draw_flat_box(fill_rect, fill_color, maxi(1, radius - 1), Color.TRANSPARENT, 0)
		var shine_h := maxf(1.0, floorf(inner.size.y * 0.34))
		var shine_rect := Rect2(fill_rect.position + Vector2(1.0, 1.0), Vector2(maxf(0.0, fill_rect.size.x - 2.0), shine_h))
		if shine_rect.size.x > 0.0:
			draw_rect(shine_rect, _with_alpha(fill_color.lightened(0.42), clampf(shine_strength, 0.0, 1.0)), true)
		var shade_h := maxf(1.0, floorf(inner.size.y * 0.26))
		var shade_rect := Rect2(Vector2(fill_rect.position.x + 1.0, fill_rect.end.y - shade_h - 1.0), Vector2(maxf(0.0, fill_rect.size.x - 2.0), shade_h))
		if shade_rect.size.x > 0.0:
			draw_rect(shade_rect, Color(0.0, 0.0, 0.0, 0.14), true)

	if segment_count > 1 and size.x >= 80.0 and size.y >= 10.0:
		var line_color := Color(1.0, 0.92, 0.72, 0.13)
		for i in range(1, segment_count):
			var x := inner.position.x + inner.size.x * (float(i) / float(segment_count))
			draw_line(Vector2(x, inner.position.y + 1.0), Vector2(x, inner.end.y - 1.0), line_color, 1.0)

	var top_edge := Color(1.0, 0.94, 0.72, 0.18)
	draw_line(Vector2(pad + 1.0, pad), Vector2(maxf(pad + 1.0, size.x - pad - 1.0), pad), top_edge, 1.0)

	if low_pulse_enabled and _get_target_ratio() <= low_pulse_threshold:
		var pulse := 0.45 + 0.35 * sin(_pulse_time * 7.0)
		var pulse_color := _with_alpha(NavalUiTheme.STATUS_DANGER.lightened(0.28), pulse)
		_draw_flat_box(outer.grow(-0.5), Color.TRANSPARENT, radius, pulse_color, 1)


func _on_value_changed(_new_value: float) -> void:
	queue_redraw()


func _on_resized() -> void:
	queue_redraw()


func _get_target_ratio() -> float:
	var span := maxf(max_value - min_value, 0.001)
	return clampf((value - min_value) / span, 0.0, 1.0)


func _approach_ratio(from_value: float, to_value: float, delta: float, speed: float) -> float:
	var weight := 1.0 - exp(-maxf(speed, 0.01) * delta)
	return lerpf(from_value, to_value, clampf(weight, 0.0, 1.0))


func _with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, alpha)


func _get_stylebox_color(name: StringName, fallback: Color) -> Color:
	var style := get_theme_stylebox(name)
	if style is StyleBoxFlat:
		return (style as StyleBoxFlat).bg_color
	return fallback


func _get_background_border_color() -> Color:
	var style := get_theme_stylebox("background")
	if style is StyleBoxFlat:
		var flat := style as StyleBoxFlat
		if flat.border_color.a > 0.0:
			return flat.border_color
	return NavalUiTheme.BORDER_GOLD_DIM


func _get_background_radius() -> int:
	var style := get_theme_stylebox("background")
	if style is StyleBoxFlat:
		return maxi(0, (style as StyleBoxFlat).corner_radius_top_left)
	return 4


func _draw_flat_box(rect: Rect2, color: Color, radius: int, border_color: Color, border_width: int) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = border_color
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	draw_style_box(box, rect)
