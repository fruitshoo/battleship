extends MeshInstance3D

## 플레이어를 따라다니는 수면 평면
## 작은 메시 하나로 무한 바다처럼 보이게 하는 표준 기법 (포그로 경계 숨김)

@export var follow_target_path: NodePath
@export var update_interval: float = 0.1 # 0.1초마다 위치 동기화

var _target: Node3D = null
var _accum: float = 0.0

func _ready() -> void:
	# Y는 항상 0 (수면)으로 고정
	global_position = Vector3(global_position.x, 0.0, global_position.z)
	
	if follow_target_path:
		_target = get_node_or_null(follow_target_path)
	
	# 타겟 못 찾으면 PlayerShip 그룹에서 탐색
	if not is_instance_valid(_target):
		var ships = get_tree().get_nodes_in_group("player")
		if ships.size() > 0:
			_target = ships[0]

func _process(delta: float) -> void:
	_accum += delta
	if _accum < update_interval:
		return
	_accum = 0.0
	
	if not is_instance_valid(_target):
		return
	
	# XZ만 추적, Y는 항상 수면 높이(0) 유지
	global_position.x = _target.global_position.x
	global_position.z = _target.global_position.z
