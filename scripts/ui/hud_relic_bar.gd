extends MarginContainer

const MATERIAL_SYMBOLS_FONT = preload("res://assets/fonts/MaterialSymbolsOutlined.ttf")
const SLOT_SIZE := Vector2(40, 40)

var relic_container: HBoxContainer = null
var current_relic_count: int = 0

func _ready() -> void:
	add_theme_constant_override("margin_top", 10)
	relic_container = HBoxContainer.new()
	relic_container.layout_direction = Control.LAYOUT_DIRECTION_RTL
	relic_container.add_theme_constant_override("separation", 8)
	add_child(relic_container)

func clear_icons() -> void:
	if not is_instance_valid(relic_container):
		return
	for child in relic_container.get_children():
		child.queue_free()
	current_relic_count = 0

func add_icon(icon_data) -> PanelContainer:
	if current_relic_count >= 5 or not is_instance_valid(relic_container):
		return null

	var slot_bg: PanelContainer = _create_slot(icon_data)
	relic_container.add_child(slot_bg)
	var icon_control := slot_bg.get_child(0) as Control
	var slot_sb := slot_bg.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	slot_bg.add_theme_stylebox_override("panel", slot_sb)

	var tween = create_tween()
	tween.tween_property(slot_sb, "border_color", Color(1, 0.8, 0.2, 1.0), 0.2)
	if icon_control:
		tween.parallel().tween_property(icon_control, "scale", Vector2(1.2, 1.2), 0.2)
		tween.tween_property(icon_control, "scale", Vector2(1.0, 1.0), 0.2)
	tween.tween_property(slot_sb, "border_color", Color(0.6, 0.5, 0.1, 0.8), 0.5)

	current_relic_count += 1
	return slot_bg

func _create_slot(icon_data) -> PanelContainer:
	var slot_bg = PanelContainer.new()
	slot_bg.custom_minimum_size = SLOT_SIZE

	var slot_sb = StyleBoxFlat.new()
	slot_sb.bg_color = Color(0, 0, 0, 0.5)
	slot_sb.set_corner_radius_all(4)
	slot_sb.border_width_bottom = 1
	slot_sb.border_width_top = 1
	slot_sb.border_width_left = 1
	slot_sb.border_width_right = 1
	slot_sb.border_color = Color(0.3, 0.3, 0.3, 0.8)
	slot_bg.add_theme_stylebox_override("panel", slot_sb)

	var icon_texture := _resolve_icon_texture(icon_data)
	if icon_texture != null:
		var icon_rect := TextureRect.new()
		icon_rect.texture = icon_texture
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.custom_minimum_size = SLOT_SIZE - Vector2(4, 4)
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot_bg.add_child(icon_rect)
		return slot_bg

	var icon_label = Label.new()
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_label.add_theme_font_size_override("font_size", 24)
	icon_label.text = str(_extract_icon_data(icon_data))
	if MATERIAL_SYMBOLS_FONT:
		icon_label.add_theme_font_override("font", MATERIAL_SYMBOLS_FONT)

	slot_bg.add_child(icon_label)
	return slot_bg

func _resolve_icon_texture(icon_data) -> Texture2D:
	var resolved_icon_data = _extract_icon_data(icon_data)
	if resolved_icon_data is Texture2D:
		return resolved_icon_data
	if resolved_icon_data is String:
		var icon_path := String(resolved_icon_data)
		if icon_path.begins_with("res://") and ResourceLoader.exists(icon_path, "Texture2D"):
			return load(icon_path) as Texture2D
	return null

func _extract_icon_data(icon_data):
	if icon_data is Dictionary:
		return icon_data.get("icon_data", "")
	return icon_data
