extends Node3D
const LevelManagerRegistry = preload("res://scripts/helpers/level_manager_registry.gd")
const EntityRegistry = preload("res://scripts/helpers/entity_registry.gd")
const FieldItemHelper = preload("res://scripts/effects/field_item_helper.gd")

## 보물 상자 (Treasure Chest)
## 플레이어가 닿으면 특별한 업그레이드 보상을 제공

@export var collection_range: float = 0.85
@export var magnet_range: float = 18.0
@export var magnet_speed: float = 12.0

var _is_collected: bool = false
var _target_player: Node3D = null
var _collection_hint_visual: MeshInstance3D = null

func _ready() -> void:
	if _env_flag_enabled("BATTLESHIP_GAUNTLET_DISABLE_RECOVERY"):
		queue_free()
		return
	add_to_group("treasure_chest")
	_create_collection_hint_visual()
	# 부유 효과 (Tween)
	var tween = create_tween().set_loops()
	tween.tween_property(self , "position:y", 0.5, 1.5).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self , "position:y", 0.0, 1.5).set_trans(Tween.TRANS_SINE)
	
	# 회전 효과
	var rot_tween = create_tween().set_loops()
	rot_tween.tween_property(self , "rotation:y", rotation.y + TAU, 4.0)

func _process(delta: float) -> void:
	if _is_collected: return
	
	var p := _get_target_player()
	if not is_instance_valid(p):
		return
	var edge_distance: float = FieldItemHelper.get_ship_edge_distance(self, p)
	var effective_collection_range: float = collection_range
	var effective_magnet_range: float = maxf(magnet_range + _get_collection_radius_bonus(), effective_collection_range + 5.0)
	_update_collection_hint_visual(effective_magnet_range)
	if edge_distance <= effective_collection_range:
		_collect()
	elif edge_distance <= effective_magnet_range:
		var pull_speed: float = magnet_speed + (effective_magnet_range - maxf(edge_distance, 0.0)) * 0.55
		FieldItemHelper.move_item_toward_ship_side_anchor(self, p, pull_speed * delta)

func _collect() -> void:
	_is_collected = true
	
	# 시스템 알림
	print("[Treasure] 보물 상자 획득!")
	
	# 사운드
	if is_instance_valid(AudioManager):
		AudioManager.play_sfx("treasure_collect")
	
	# 레벨 매니저를 통해 업그레이드 메뉴 호출 (보물 상자 전용)
	var lm = LevelManagerRegistry.get_level_manager(get_tree())
	if lm and lm.has_method("_show_upgrade_ui"):
		# 보물 상자는 5개의 선택지 제공 및 특별 보너스
		lm.call_deferred("_show_upgrade_ui", 5)
	
	# 파티클 효과 (필요 시) 생성 후 제거
	queue_free()


func _get_target_player() -> Node3D:
	if is_instance_valid(_target_player) and _target_player.is_inside_tree():
		return _target_player
	_target_player = EntityRegistry.get_first_ship_by_team("player") as Node3D
	return _target_player


func _get_effective_collection_range(player_ship: Node3D) -> float:
	return collection_range if is_instance_valid(player_ship) else INF


func _get_collection_radius_bonus() -> float:
	var bonus: float = 0.0
	var meta_manager = get_node_or_null("/root/MetaManager")
	if is_instance_valid(meta_manager) and meta_manager.has_method("get_collection_radius_bonus"):
		bonus += float(meta_manager.get_collection_radius_bonus())
	var upgrade_manager = get_node_or_null("/root/UpgradeManager")
	if is_instance_valid(upgrade_manager) and upgrade_manager.has_method("get_supply_bonus_stats"):
		var supply_stats: Dictionary = upgrade_manager.get_supply_bonus_stats()
		bonus += float(supply_stats.get("radius_bonus", 0.0))
	return bonus


func _create_collection_hint_visual() -> void:
	_collection_hint_visual = MeshInstance3D.new()
	_collection_hint_visual.name = "CollectionHint"
	var disk := CylinderMesh.new()
	disk.top_radius = 1.0
	disk.bottom_radius = 1.0
	disk.height = 0.025
	_collection_hint_visual.mesh = disk
	_collection_hint_visual.position = Vector3(0.0, 0.03, 0.0)
	_collection_hint_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_collection_hint_visual.extra_cull_margin = 24.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.84, 0.28, 0.12)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.62, 0.18, 1.0)
	mat.emission_energy_multiplier = 0.18
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	_collection_hint_visual.material_override = mat
	add_child(_collection_hint_visual)
	_update_collection_hint_visual(magnet_range)


func _update_collection_hint_visual(radius: float) -> void:
	if not is_instance_valid(_collection_hint_visual):
		return
	var visual_radius: float = clampf(radius, collection_range, 28.0)
	_collection_hint_visual.scale = Vector3(visual_radius, 1.0, visual_radius)


func _env_flag_enabled(name: String) -> bool:
	var value := OS.get_environment(name).strip_edges().to_lower()
	return value == "1" or value == "true" or value == "yes" or value == "on"
