class_name ShipCollisionProfile
extends Resource

## 선박 충돌 관련 파라미터를 한 곳에서 관리하는 프로파일

@export_range(2.0, 15.0) var base_collision_radius: float = 4.5
@export_range(0.1, 3.0) var length_multiplier: float = 1.0
@export_range(0.1, 3.0) var width_multiplier: float = 1.0

@export var auto_fit_collision_to_hull: bool = true
@export_range(0.75, 1.1) var auto_fit_scale: float = 1.0
@export_range(0.0, 2.0) var collision_padding: float = 0.02
@export_range(0.6, 1.0) var deck_bounds_ratio: float = 0.88

@export_range(0.5, 12.0) var min_ramming_speed: float = 6.0
@export_range(0.0, 6.0) var broad_phase_padding: float = 2.0
