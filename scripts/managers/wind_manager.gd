extends Node

## 글로벌 바람 시스템 관리
## AutoLoad로 설정하여 모든 배가 접근 가능

# === 기본 바람 ===
# 바람 방향 (정규화된 Vector2, XZ 평면)
var wind_direction: Vector2 = Vector2(1, 0) # 기본값: 서풍
# 바람 강도 (0.0 ~ 1.0)
@export var wind_strength: float = 0.7
# 바람 각도 (도 단위, UI 표시용)
var wind_angle_degrees: float = 0.0

# === 느린 회전 (Slow Drift) ===
@export var drift_enabled: bool = true
@export var drift_speed: float = 0.2 # 초당 회전 각도 (도) → 분당 12도, ~30분에 한 바퀴
var drift_direction: float = 1.0 # 1.0 = 시계, -1.0 = 반시계

# === 돌풍 (Gust) ===
@export var gust_enabled: bool = true
@export var gust_interval_min: float = 30.0 # 최소 간격 (초)
@export var gust_interval_max: float = 60.0 # 최대 간격 (초)
@export var gust_duration: float = 3.0 # 돌풍 지속 시간
@export var gust_strength_multiplier: float = 2.0 # 돌풍 시 강도 배율

var _gust_timer: float = 0.0
var _gust_remaining: float = 0.0 # > 0이면 돌풍 중
var _gust_angle_offset: float = 0.0 # 돌풍 방향 오프셋 (도)
var _gust_blend: float = 0.0 # 0 = 평상시, 1 = 돌풍 최대

# 시그널: UI 업데이트 등에 활용
signal wind_changed(direction: Vector2, strength: float)
signal gust_started(angle_offset: float)
signal gust_ended()


func _ready() -> void:
	# 시작 시 바람 방향 랜덤하게 설정 (180~270도 구간은 되도록 피함)
	var initial_angle = randf_range(0.0, 360.0)
	if initial_angle > 180.0 and initial_angle < 270.0:
		initial_angle = wrapf(initial_angle + 90.0, 0, 360) # 불편한 구간이면 즉시 90도 회전
	set_wind_angle(initial_angle)
	
	_reset_gust_timer()
	# 시작 시 회전 방향 랜덤
	drift_direction = 1.0 if randf() > 0.5 else -1.0


func _process(delta: float) -> void:
	var changed = false
	
	# 1. 느린 회전 (Slow Drift)
	if drift_enabled:
		var current_speed = drift_speed
		# 남서풍 구간 (180~270도)에서는 10배 빠르게 회전하여 신속하게 통과
		if wind_angle_degrees > 180.0 and wind_angle_degrees < 270.0:
			current_speed *= 10.0
			
		wind_angle_degrees += current_speed * drift_direction * delta
		# 360도 랩핑
		if wind_angle_degrees > 360.0:
			wind_angle_degrees -= 360.0
		elif wind_angle_degrees < 0.0:
			wind_angle_degrees += 360.0
		
		# 각도 → 방향 벡터 변환
		var angle_rad = deg_to_rad(wind_angle_degrees)
		wind_direction = Vector2(sin(angle_rad), -cos(angle_rad)).normalized()
		changed = true
	
	# 2. 돌풍 (Gust) 타이머
	if gust_enabled:
		if _gust_remaining > 0:
			# 돌풍 진행 중
			_gust_remaining -= delta
			
			# 블렌드: 시작 시 빠르게 올라가고, 끝날 때 서서히 꺼짐
			var gust_progress = 1.0 - (_gust_remaining / gust_duration)
			if gust_progress < 0.2:
				# 시작: 빠르게 올라감 (0→1 in 20%)
				_gust_blend = gust_progress / 0.2
			elif gust_progress > 0.7:
				# 종료: 서서히 꺼짐 (1→0 in 30%)
				_gust_blend = (1.0 - gust_progress) / 0.3
			else:
				_gust_blend = 1.0
			
			if _gust_remaining <= 0:
				_gust_blend = 0.0
				_reset_gust_timer()
				gust_ended.emit()
			
			changed = true
		else:
			# 돌풍 대기 중
			_gust_timer -= delta
			if _gust_timer <= 0:
				_start_gust()
	
	if changed:
		wind_changed.emit(get_wind_direction(), get_wind_strength())


## 바람 방향 설정 (Vector2, XZ 평면)
func set_wind_direction(direction: Vector2) -> void:
	wind_direction = direction.normalized()
	_update_wind_angle()


## 바람 각도로 방향 설정 (도 단위, 0 = 북쪽에서 불어옴, 시계방향)
func set_wind_angle(angle_degrees: float) -> void:
	wind_angle_degrees = angle_degrees
	var angle_rad = deg_to_rad(angle_degrees)
	wind_direction = Vector2(sin(angle_rad), -cos(angle_rad)).normalized()


## 바람 강도 설정
func set_wind_strength(strength: float) -> void:
	wind_strength = clamp(strength, 0.0, 1.0)


## 현재 바람 방향 벡터 반환 (돌풍 반영)
func get_wind_direction() -> Vector2:
	if _gust_blend > 0.01:
		# 돌풍 방향 = 기본 방향 + 오프셋 각도
		var gust_angle_rad = deg_to_rad(wind_angle_degrees + _gust_angle_offset)
		var gust_dir = Vector2(sin(gust_angle_rad), -cos(gust_angle_rad)).normalized()
		# 기본 방향과 돌풍 방향을 블렌드
		return wind_direction.lerp(gust_dir, _gust_blend).normalized()
	return wind_direction


## 현재 바람 강도 반환 (돌풍 반영)
func get_wind_strength() -> float:
	if _gust_blend > 0.01:
		return wind_strength * lerp(1.0, gust_strength_multiplier, _gust_blend)
	return wind_strength


## 내부: 각도 업데이트 (UI 표시용)
func _update_wind_angle() -> void:
	wind_angle_degrees = rad_to_deg(atan2(wind_direction.x, -wind_direction.y))
	if wind_angle_degrees < 0:
		wind_angle_degrees += 360


## 내부: 돌풍 타이머 리셋
func _reset_gust_timer() -> void:
	_gust_timer = randf_range(gust_interval_min, gust_interval_max)


## 내부: 돌풍 시작
func _start_gust() -> void:
	_gust_remaining = gust_duration
	# 돌풍 방향: 기본 바람 기준 ±30~90도 랜덤 오프셋
	_gust_angle_offset = randf_range(30.0, 90.0) * (1.0 if randf() > 0.5 else -1.0)
	_gust_blend = 0.0
	gust_started.emit(_gust_angle_offset)
	print("[Wind] 돌풍! 방향 오프셋: %.1f°, 지속: %.1f초" % [_gust_angle_offset, gust_duration])
