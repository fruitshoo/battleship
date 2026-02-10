extends Node

## 글로벌 바람 시스템 관리
## AutoLoad로 설정하여 모든 배가 접근 가능

# 바람 방향 (정규화된 Vector2, XZ 평면)
# Vector2(0, -1) = 북풍 (-Z 방향으로 분다)
var wind_direction: Vector2 = Vector2(1, 0) # 기본값: 서풍 (+X 방향으로 분다)

# 바람 강도 (0.0 ~ 1.0)
@export var wind_strength: float = 0.7

# 바람 각도 (도 단위, UI 표시용)
var wind_angle_degrees: float = 0.0


func _ready() -> void:
	_update_wind_angle()


## 바람 방향 설정 (Vector2, XZ 평면)
func set_wind_direction(direction: Vector2) -> void:
	wind_direction = direction.normalized()
	_update_wind_angle()


## 바람 각도로 방향 설정 (도 단위, 0 = 북쪽에서 불어옴, 시계방향)
## 바람이 "불어가는" 방향을 나타냄
func set_wind_angle(angle_degrees: float) -> void:
	wind_angle_degrees = angle_degrees
	var angle_rad = deg_to_rad(angle_degrees)
	# 0도 = -Z 방향으로 바람이 분다 (북풍)
	# 90도 = +X 방향으로 바람이 분다 (서풍)
	wind_direction = Vector2(sin(angle_rad), -cos(angle_rad)).normalized()


## 바람 강도 설정
func set_wind_strength(strength: float) -> void:
	wind_strength = clamp(strength, 0.0, 1.0)


## 현재 바람 방향 벡터 반환
func get_wind_direction() -> Vector2:
	return wind_direction


## 현재 바람 강도 반환
func get_wind_strength() -> float:
	return wind_strength


## 내부: 각도 업데이트 (UI 표시용)
func _update_wind_angle() -> void:
	# Vector2(x, z) → 각도 (0 = 북쪽 = -Z)
	wind_angle_degrees = rad_to_deg(atan2(wind_direction.x, -wind_direction.y))
	if wind_angle_degrees < 0:
		wind_angle_degrees += 360
