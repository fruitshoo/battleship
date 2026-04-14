extends Node3D

const PreviewHarnessHelper = preload("res://scripts/test/preview_harness_helper.gd")
const NavalUiTheme = preload("res://scripts/ui/naval_ui_theme.gd")
const ShipControlPanelScene = preload("res://scenes/ui/ship_control_panel.tscn")

const SITE_PREVIEWS := [
	{
		"path": "res://scenes/world/sea_sites/reef_marker_site.tscn",
		"label": "Reef Marker",
		"offset": Vector3(-16.0, 0.0, -20.0),
	},
	{
		"path": "res://scenes/world/sea_sites/tiny_islet_site.tscn",
		"label": "Tiny Islet",
		"offset": Vector3(0.0, 0.0, -22.0),
	},
	{
		"path": "res://scenes/world/sea_sites/temporary_outpost_site.tscn",
		"label": "Temporary Outpost",
		"offset": Vector3(16.0, 0.0, -20.0),
	},
]

@export var auto_open_debug_panel: bool = false
@export var stop_regular_spawns: bool = true
@export var auto_quit_delay_seconds: float = 0.08


func _ready() -> void:
	call_deferred("_configure_preview")


func _configure_preview() -> void:
	PreviewHarnessHelper.setup_common(self, auto_open_debug_panel, stop_regular_spawns)
	_spawn_sites()
	_ensure_ship_control_panel()
	_ensure_overlay()
	if _env_flag_enabled("BATTLESHIP_SEA_SITE_PREVIEW_AUTO_QUIT"):
		call_deferred("_quit_after_report")


func _spawn_sites() -> void:
	var player_ship := get_node_or_null("PlayerShip") as Node3D
	var origin := Vector3.ZERO
	if is_instance_valid(player_ship):
		origin = player_ship.global_position
	for config in SITE_PREVIEWS:
		var scene_path := str(config.get("path", ""))
		var packed := load(scene_path) as PackedScene
		if packed == null:
			push_error("[SeaSitePreview] failed to load %s" % scene_path)
			continue
		var site := packed.instantiate() as Node3D
		if site == null:
			push_error("[SeaSitePreview] failed to instantiate %s" % scene_path)
			continue
		site.name = str(config.get("label", "Sea Site")).replace(" ", "")
		add_child(site)
		site.global_position = origin + (config.get("offset", Vector3.ZERO) as Vector3)
		site.global_position.y = 0.0
		PreviewHarnessHelper.add_billboard_label(
			site,
			str(config.get("label", "Sea Site")),
			Vector3(0.0, 4.2, 0.0),
			Color(1.0, 0.93, 0.64, 1.0),
			34
		)


func _ensure_ship_control_panel() -> void:
	if is_instance_valid(get_node_or_null("SeaSitePreviewUI/ShipControlPanel")):
		return
	var ui_layer := get_node_or_null("SeaSitePreviewUI") as CanvasLayer
	if not is_instance_valid(ui_layer):
		ui_layer = CanvasLayer.new()
		ui_layer.name = "SeaSitePreviewUI"
		add_child(ui_layer)
	var panel := ShipControlPanelScene.instantiate() as Control
	if not is_instance_valid(panel):
		push_error("[SeaSitePreview] failed to instantiate ship control panel")
		return
	ui_layer.add_child(panel)


func _ensure_overlay() -> void:
	var hud: Node = get_node_or_null("GameHUD")
	if not is_instance_valid(hud):
		return

	var panel := PanelContainer.new()
	panel.name = "SeaSitePreviewOverlay"
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 20.0
	panel.offset_top = 20.0
	panel.offset_right = 520.0
	panel.offset_bottom = 120.0
	panel.z_index = 100
	panel.add_theme_stylebox_override(
		"panel",
		NavalUiTheme.make_panel_style(NavalUiTheme.PANEL_BG_SOFT, NavalUiTheme.BORDER_GOLD_DIM, 8, 1, 10.0, 8.0, 10.0, 8.0)
	)
	var label := Label.new()
	label.text = "Sea Site Preview\nCheck size, waterline, labels, and compass marker direction."
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	NavalUiTheme.style_body(label, 13)
	panel.add_child(label)
	hud.add_child(panel)


func _quit_after_report() -> void:
	await get_tree().create_timer(maxf(auto_quit_delay_seconds, 0.01)).timeout
	var failures := _validate_preview_contract()
	if not failures.is_empty():
		for failure in failures:
			push_error("[SeaSitePreview] %s" % failure)
		get_tree().quit(1)
		return
	print("[SeaSitePreview] ok")
	get_tree().quit()


func _validate_preview_contract() -> Array[String]:
	var failures: Array[String] = []
	var static_sites := 0
	for node in get_tree().get_nodes_in_group("static_reward_site"):
		if node is Node3D and node.is_inside_tree():
			static_sites += 1
	if static_sites < SITE_PREVIEWS.size():
		failures.append("expected %d static sites, found %d" % [SITE_PREVIEWS.size(), static_sites])

	var marker := get_node_or_null("SeaSitePreviewUI/ShipControlPanel/WindPanel/WindIndicator/CompassWheel/SiteMarker") as Node2D
	if not is_instance_valid(marker):
		failures.append("missing compass site marker")
	elif not marker.visible:
		failures.append("compass site marker is not visible")
	elif marker.position.length() <= 8.0:
		failures.append("compass site marker did not move toward preview sites: %.2f" % marker.position.length())
	return failures


func _env_flag_enabled(name: String) -> bool:
	var value := OS.get_environment(name).strip_edges().to_lower()
	return value == "1" or value == "true" or value == "yes" or value == "on"
