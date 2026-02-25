extends Decal

## 전역 구름 그림자 매니저
## 거대한 데칼 노드를 일정 방향으로 이동시켜 구름 그림자 효과를 냅니다.

@export var cloud_speed: Vector2 = Vector2(1.5, 0.8) # 초당 이동 거리 (미터)
@export var reset_distance: float = 1000.0 # 이 거리를 벗어나면 반대편으로 루프

var _initial_pos: Vector3
var _update_accum: float = 0.0
const UPDATE_INTERVAL: float = 0.1 # 0.1초마다 위치 갱신 (10fps)

func _ready() -> void:
	_initial_pos = global_position
	
func _process(delta: float) -> void:
	# 구름 이동은 고빈도 업데이트 불필요 — 0.1초마다만 실행
	_update_accum += delta
	if _update_accum < UPDATE_INTERVAL:
		return
	var step = _update_accum
	_update_accum = 0.0
	
	# 바람 시스템과 연동 (WindManager가 있으면 바람 방향/강도 반영)
	var move_vec = Vector2.ZERO
	if is_instance_valid(WindManager):
		var wind_dir = WindManager.get_wind_direction()
		var wind_str = WindManager.get_wind_strength()
		move_vec = wind_dir * (wind_str * cloud_speed.length() * 5.0)
	else:
		move_vec = cloud_speed
	
	# 위치 이동
	global_position.x += move_vec.x * step
	global_position.z += move_vec.y * step
	
	# 일정 범위를 벗어나면 반대편으로 루프
	if abs(global_position.x - _initial_pos.x) > reset_distance:
		global_position.x = _initial_pos.x - (reset_distance * sign(cloud_speed.x))
	if abs(global_position.z - _initial_pos.z) > reset_distance:
		global_position.z = _initial_pos.z - (reset_distance * sign(cloud_speed.y))
