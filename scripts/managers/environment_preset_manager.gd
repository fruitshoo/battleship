extends Node

## 환경 프리셋 전환 매니저
## - start_preset: 시작 시 적용할 프리셋
## - 디버그 빌드에서 F7/F8로 즉시 전환

enum Preset {
	CLEAR_DAY,
	STORM_EVE,
}

signal preset_applied(preset: int)

@export var start_preset: Preset = Preset.CLEAR_DAY
@export var allow_debug_hotkeys: bool = true
@export var world_environment_path: NodePath = NodePath("../WorldEnvironment")
@export var camera_path: NodePath = NodePath("../Camera3D")
@export var directional_light_path: NodePath = NodePath("../DirectionalLight3D")

@export var clear_day_environment: Environment = preload("res://resources/environment/world_environment_clear_day.tres")
@export var storm_eve_environment: Environment = preload("res://resources/environment/world_environment_storm_eve.tres")

var _world_environment: WorldEnvironment = null
var _camera: Camera3D = null
var _directional_light: DirectionalLight3D = null
var current_preset: Preset = Preset.CLEAR_DAY

func _ready() -> void:
	_world_environment = get_node_or_null(world_environment_path) as WorldEnvironment
	_camera = get_node_or_null(camera_path) as Camera3D
	_directional_light = get_node_or_null(directional_light_path) as DirectionalLight3D
	apply_preset(start_preset)

func _unhandled_input(event: InputEvent) -> void:
	if not allow_debug_hotkeys or not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F7:
			apply_preset(Preset.CLEAR_DAY)
		elif event.keycode == KEY_F8:
			apply_preset(Preset.STORM_EVE)

func apply_preset(preset: Preset) -> void:
	current_preset = preset
	var env: Environment = clear_day_environment if preset == Preset.CLEAR_DAY else storm_eve_environment
	if is_instance_valid(_world_environment):
		_world_environment.environment = env
	if is_instance_valid(_camera):
		_camera.environment = env

	if is_instance_valid(_directional_light):
		match preset:
			Preset.CLEAR_DAY:
				_directional_light.light_color = Color(1.0, 0.96, 0.90, 1.0)
				_directional_light.light_energy = 1.35
				_directional_light.light_indirect_energy = 1.05
				_directional_light.light_volumetric_fog_energy = 0.95
			Preset.STORM_EVE:
				_directional_light.light_color = Color(0.72, 0.79, 0.95, 1.0)
				_directional_light.light_energy = 0.95
				_directional_light.light_indirect_energy = 0.82
				_directional_light.light_volumetric_fog_energy = 0.55

	preset_applied.emit(int(current_preset))

func is_clear_day_active() -> bool:
	return current_preset == Preset.CLEAR_DAY
