@tool
extends "res://scripts/entities/ships/base_ship.gd"

const DEBUG_CHASER_LOGS := false

@export var team: String = "enemy"
@export var move_speed: float = 3.5
@export var soldier_scene: PackedScene
@export var cannon_scene: PackedScene
@export var hull_scene: PackedScene
@export var preferred_soldier_type: String = "general"
enum CombatRole {CHARGER, GUNNER}
@export var combat_role: CombatRole = CombatRole.CHARGER
@export_range(4.0, 30.0) var preferred_combat_range: float = 14.0
@export_range(0.5, 8.0) var combat_range_tolerance: float = 2.5
@export_range(2.0, 20.0) var retreat_distance: float = 8.0
@export var allow_boarding: bool = true
@export var formation_role_name: String = ""
@export var ship_type: String = "sekibune_melee"
var has_cannons: bool = true
var target: Node3D = null
var leaking_rate: float = 0.0
var _leak_tick_timer: float = 0.0
@export var minion_respawn_interval: float = 15.0
@export var max_minion_crew: int = 4
var minion_respawn_timer: float = 0.0
@export var max_crew: int = 6
var enemy_crew_composition: Array[String] = []
var _enemy_crew_spawn_index: int = 0
@export_range(0.5, 3.0) var ai_rudder_gain: float = 1.2
@export_range(20.0, 160.0) var ai_rudder_response_speed: float = 70.0
@export_range(10.0, 80.0) var ai_max_turn_rate: float = 30.0
@export_range(0.2, 1.0) var ai_turn_authority: float = 0.7
@export_range(4.0, 24.0) var ai_close_turn_soft_radius: float = 12.0
@export_range(0.2, 1.0) var ai_close_turn_scale: float = 0.6
@export_range(0.25, 1.5) var separation_pad_scale: float = 1.0
enum Formation {COLUMN, WING}
static var fleet_formation: Formation = Formation.COLUMN
var formation_spacing: float = 14.0
var _wave_timer: float = 0.0
var _last_ai_speed: float = 0.0
var _oar_time: float = 0.0
var stamina: float = 100.0
var max_stamina: float = 100.0
var is_sprinting: bool = false
var sprint_multiplier: float = 1.5
var fire_pot_cooldown_timer: float = 0.0
var fire_pot_scene: PackedScene = null
static var _cached_minion_list: Array = []
static var _last_minion_cache_frame: int = -1
static var _cached_ships_list: Array = []
static var _last_ships_cache_frame: int = -1
var _cached_wind_manager: Node = null
var cached_lm: Node = null
var separation_force: Vector3 = Vector3.ZERO
var separation_timer: float = 0.0
var logic_timer: float = 0.0
@export_range(0.05, 0.5, 0.01) var ai_logic_update_interval: float = 0.2
@export_range(0.0, 0.15, 0.01) var ai_logic_update_jitter: float = 0.05
var _ai_logic_update_interval_runtime: float = 0.2
@export_range(0.05, 0.5, 0.01) var ai_separation_update_interval: float = 0.12
var _ai_separation_update_interval_runtime: float = 0.12
var has_rammed: bool = false
var _merit_granted: bool = false
