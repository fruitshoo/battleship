extends MeshInstance3D

## 플레이어를 따라다니는 수면 평면
## 작은 메시 하나로 무한 바다처럼 보이게 하는 표준 기법 (포그로 경계 숨김)

@export var follow_target_path: NodePath
@export var grid_size: float = 100.0 # 100미터 단위로 이동

var _target: Node3D = null

func _ready() -> void:
	# Y는 항상 0 (수면)으로 고정
	global_position.y = 0.0
	print("[Ocean] 스크립트 로드 완료 (Grid Size: %.1f)" % grid_size)

func _process(_delta: float) -> void:
	# 타겟이 없으면 매 프레임 찾기 시도 (초기화 타이밍 문제 해결)
	if not is_instance_valid(_target):
		var ships = get_tree().get_nodes_in_group("player")
		if ships.size() > 0:
			_target = ships[0]
			print("[Ocean] 타겟 발견: ", _target.name)
		else:
			return # 타겟 찾을 때까지 대기
	
	# 격차 이동 로직 (Grid Snapping)
	var target_pos = _target.global_position
	
	var new_x = round(target_pos.x / grid_size) * grid_size
	var new_z = round(target_pos.z / grid_size) * grid_size
	
	if abs(global_position.x - new_x) > 0.1 or abs(global_position.z - new_z) > 0.1:
		print("[Ocean] 위치 이동: ", global_position, " -> ", Vector3(new_x, 0, new_z))
		global_position.x = new_x
		global_position.z = new_z
