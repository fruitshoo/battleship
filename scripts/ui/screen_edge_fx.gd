extends CanvasLayer

const UiOverlayFx = preload("res://scripts/ui/ui_overlay_fx.gd")

@export var player_ship_path: NodePath = NodePath("../PlayerShip")
@export_range(0.0, 1.0, 0.01) var base_vignette_strength: float = 0.18
@export_range(0.0, 1.0, 0.01) var base_blur_strength: float = 0.92
@export_range(0.0, 1.0, 0.01) var motion_boost_strength: float = 0.36
@export_range(0.0, 1.0, 0.01) var motion_response_speed: float = 2.2

@onready var overlay: ColorRect = $Overlay

var _player_ship: Node3D = null
var _visual_motion_boost: float = 0.0
var _settings_enabled: bool = true
var _settings_strength: float = 1.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_refresh_user_settings(true)
	_apply_overlay_material()

func _process(delta: float) -> void:
	_refresh_user_settings()
	if not is_instance_valid(_player_ship):
		_player_ship = get_node_or_null(player_ship_path) as Node3D
		if not is_instance_valid(_player_ship):
			_player_ship = get_tree().get_first_node_in_group("player") as Node3D

	if not _settings_enabled:
		_visual_motion_boost = move_toward(_visual_motion_boost, 0.0, motion_response_speed * delta)
		_update_overlay_shader()
		return

	var target_motion_boost := _compute_target_motion_boost() * _get_motion_strength_scale()
	_visual_motion_boost = move_toward(_visual_motion_boost, target_motion_boost, motion_response_speed * delta)
	_update_overlay_shader()

func _apply_overlay_material() -> void:
	if not is_instance_valid(overlay):
		return
	overlay.material = UiOverlayFx.make_screen_edge_motion_material(_get_effective_vignette_strength(), _get_effective_blur_strength(), _visual_motion_boost)
	_update_overlay_shader()

func _compute_target_motion_boost() -> float:
	if not is_instance_valid(_player_ship):
		return 0.0
	var current_speed: float = float(_player_ship.get("current_speed")) if _player_ship.get("current_speed") != null else 0.0
	var max_speed: float = float(_player_ship.get("max_speed")) if _player_ship.get("max_speed") != null else 0.0
	var is_rowing: bool = _player_ship.get("is_rowing") == true if _player_ship.get("is_rowing") != null else false
	var rudder_angle: float = float(_player_ship.get("rudder_angle")) if _player_ship.get("rudder_angle") != null else 0.0

	var motion_speed := absf(current_speed)
	var speed_ratio := clampf(motion_speed / maxf(max_speed, 0.001), 0.0, 1.5)
	var motion := clampf(remap(speed_ratio, 0.35, 1.05, 0.0, 1.0), 0.0, 1.0) * 0.72
	if is_rowing:
		motion = maxf(motion, 0.28 + speed_ratio * 0.26)
	if absf(rudder_angle) >= 12.0 and motion_speed > 2.0:
		motion = maxf(motion, 0.22 + clampf(absf(rudder_angle) / 45.0, 0.0, 0.35))
	return clampf(motion * motion_boost_strength, 0.0, 0.42)

func _update_overlay_shader() -> void:
	if not is_instance_valid(overlay):
		return
	overlay.visible = _settings_enabled
	var material := overlay.material as ShaderMaterial
	if material == null:
		return
	UiOverlayFx.set_screen_edge_motion_params(
		material,
		_get_effective_vignette_strength(),
		_get_effective_blur_strength(),
		_visual_motion_boost if _settings_enabled else 0.0
	)

func _refresh_user_settings(force: bool = false) -> void:
	if not is_instance_valid(SaveManager):
		return
	var next_enabled: bool = SaveManager.get_setting("screen_edge_fx_enabled", true) == true
	var next_strength: float = clampf(float(SaveManager.get_setting("screen_edge_fx_strength", 0.75)), 0.0, 1.0)
	if force or next_enabled != _settings_enabled or not is_equal_approx(next_strength, _settings_strength):
		_settings_enabled = next_enabled
		_settings_strength = next_strength
		_update_overlay_shader()

func _get_effective_vignette_strength() -> float:
	if not _settings_enabled:
		return 0.0
	return base_vignette_strength * lerpf(0.35, 1.0, _settings_strength)

func _get_effective_blur_strength() -> float:
	if not _settings_enabled:
		return 0.0
	return base_blur_strength * lerpf(0.25, 1.0, _settings_strength)

func _get_motion_strength_scale() -> float:
	if not _settings_enabled:
		return 0.0
	return lerpf(0.22, 1.0, _settings_strength)
