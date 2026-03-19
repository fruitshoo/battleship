extends Control
const SceneGroupCache = preload("res://scripts/helpers/scene_group_cache.gd")

## 배 조작 UI: 현재는 나침반/바람 표시만 담당

@export var controlled_ship: NodePath

var ship: Node3D = null
@onready var wind_indicator: Control = %WindIndicator
@onready var wind_arrow: Node2D = %Arrow
@onready var compass_wheel: Node2D = %CompassWheel


func _resolve_controlled_ship() -> void:
	ship = null
	if controlled_ship != NodePath(""):
		var configured_ship: Node = get_node_or_null(controlled_ship)
		if is_instance_valid(configured_ship):
			ship = configured_ship as Node3D
			return
	var players = SceneGroupCache.get_nodes(get_tree(), "player")
	for p in players:
		if is_instance_valid(p) and p.get("is_player_controlled") == true:
			ship = p
			return
	if players.size() > 0:
		ship = players[0]


func _ready() -> void:
	_resolve_controlled_ship()


func _process(delta: float) -> void:
	# 카메라 yaw를 반영하므로 매 프레임 갱신해도 부담이 적고 더 자연스럽다.
	if not is_instance_valid(ship):
		_resolve_controlled_ship()
		if not is_instance_valid(ship):
			return
	_update_wind_indicator()

func _update_wind_indicator() -> void:
	if not is_instance_valid(WindManager):
		return

	var cam = get_viewport().get_camera_3d()
	var cam_yaw = 0.0
	if is_instance_valid(cam):
		cam_yaw = cam.global_rotation.y

	if compass_wheel:
		compass_wheel.rotation = cam_yaw

	var wind_dir: Vector2 = WindManager.get_wind_direction()
	var wind_angle_rad = atan2(wind_dir.x, -wind_dir.y)
	wind_arrow.rotation = wind_angle_rad + cam_yaw
