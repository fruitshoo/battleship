extends Node3D
const PhysicsFrameProfiler = preload("res://scripts/debug/physics_frame_profiler.gd")
const DEBUG_COMBAT_LOGS := false
const JANGGUN_SHIP_AIM_VERTICAL_OFFSET := 0.05

## 장군전 발사 컨트롤러
## 배 중앙에서 전방위로 쏘지 않고, 활성 대포 포문 중 하나를 빌려 느리게 추가 발사한다.

@export var missile_scene: PackedScene = preload("res://scenes/projectiles/janggun_missile.tscn")
@export var muzzle_smoke_scene: PackedScene = preload("res://scenes/effects/cannon_muzzle_smoke.tscn")
@export var fire_cooldown: float = 12.0
@export var min_fire_cooldown: float = 9.0
@export var cooldown_reduce_per_level: float = 0.6
@export var detection_range: float = 28.0
@export var damage: float = 10.0
@export var projectile_speed: float = 19.0
@export_range(0.05, 0.5) var target_scan_interval: float = 0.2
@export_range(0.0, 0.5, 0.01) var muzzle_smoke_follow_muzzle_time: float = 0.22
@export_range(0.0, 1.5, 0.05) var cannon_post_fire_delay: float = 0.45
@export var team: String = "player"
@export_range(1.0, 6.0) var target_tracking_scan_multiplier: float = 3.0

var cooldown_timer: float = 0.0
var _owner_ship: Node = null
var _target_scan_left: float = 0.0
var _cached_target: Node3D = null
var _cached_cannon: Node3D = null


func _ready() -> void:
	_owner_ship = _resolve_owner_ship()
	_target_scan_left = randf_range(0.0, target_scan_interval)


func _process(delta: float) -> void:
	var profile_start := PhysicsFrameProfiler.begin()
	_profiled_process(delta)
	PhysicsFrameProfiler.end("launcher_janggun_process", profile_start)


func _profiled_process(delta: float) -> void:
	if not _is_owner_combat_ready():
		_cached_target = null
		_cached_cannon = null
		return

	if cooldown_timer > 0.0:
		cooldown_timer -= delta
		return

	_target_scan_left -= delta
	if _target_scan_left <= 0.0 or not _is_cannon_target_pair_valid(_cached_cannon, _cached_target):
		var pair := _find_best_cannon_target_pair()
		_cached_cannon = pair.get("cannon", null) as Node3D
		_cached_target = pair.get("target", null) as Node3D
		_target_scan_left = _get_target_scan_interval(_is_cannon_target_pair_valid(_cached_cannon, _cached_target))

	if _is_cannon_target_pair_valid(_cached_cannon, _cached_target):
		fire(_cached_target)


func _get_target_scan_interval(has_valid_target: bool) -> float:
	return LauncherCombatHelper.get_target_scan_interval(target_scan_interval, target_tracking_scan_multiplier, has_valid_target)


func _resolve_owner_ship() -> Node:
	return LauncherCombatHelper.resolve_owner_ship(self)


func _is_owner_combat_ready() -> bool:
	if not is_instance_valid(_owner_ship):
		_owner_ship = _resolve_owner_ship()
	return LauncherCombatHelper.is_owner_combat_ready(_owner_ship)


func _is_target_valid(target: Variant) -> bool:
	var target_node := LauncherCombatHelper.get_enemy_combat_target(target, team)
	if target_node == null:
		return false
	return is_instance_valid(_find_best_cannon_for_target(target_node))


func _find_nearest_enemy() -> Node3D:
	var pair := _find_best_cannon_target_pair()
	return pair.get("target", null) as Node3D


func _find_best_cannon_target_pair() -> Dictionary:
	var best_pair := {}
	var best_score_sq: float = INF
	var enemies := EntityRegistry.get_ships_by_team(LauncherCombatHelper.enemy_team_tag(team))
	for cannon in _get_active_cannons():
		for enemy in enemies:
			var enemy_ship := LauncherCombatHelper.get_enemy_combat_target(enemy, team)
			if enemy_ship == null:
				continue
			if not _is_cannon_target_pair_valid(cannon, enemy_ship):
				continue
			var score_sq: float = cannon.global_position.distance_squared_to(enemy_ship.global_position)
			if score_sq < best_score_sq:
				best_score_sq = score_sq
				best_pair = {
					"cannon": cannon,
					"target": enemy_ship,
				}
	return best_pair


func _find_best_cannon_for_target(target: Node3D) -> Node3D:
	if not is_instance_valid(target):
		return null
	var best_cannon: Node3D = null
	var best_score_sq: float = INF
	for cannon in _get_active_cannons():
		if not _is_cannon_target_pair_valid(cannon, target):
			continue
		var score_sq: float = cannon.global_position.distance_squared_to(target.global_position)
		if score_sq < best_score_sq:
			best_score_sq = score_sq
			best_cannon = cannon
	return best_cannon


func _is_cannon_target_pair_valid(cannon: Variant, target: Variant) -> bool:
	if not is_instance_valid(cannon) or not (cannon is Node3D):
		return false
	if not _is_active_cannon(cannon):
		return false
	var target_node := LauncherCombatHelper.get_enemy_combat_target(target, team)
	if target_node == null:
		return false
	if is_instance_valid(_owner_ship) and target_node == _owner_ship:
		return false
	if target_node.has_method("get_hull_hp_value") and float(target_node.get_hull_hp_value()) <= 0.0:
		return false
	if target_node.get("is_derelict") == true:
		return false
	if not LauncherCombatHelper.is_target_in_range(cannon as Node3D, target_node, detection_range):
		return false
	if cannon.has_method("can_cover_reload_allocation_target"):
		return bool(cannon.call("can_cover_reload_allocation_target", target_node))
	return _is_target_in_cannon_forward_arc(cannon as Node3D, target_node)


func _get_active_cannons() -> Array[Node3D]:
	var cannons: Array[Node3D] = []
	if not is_instance_valid(_owner_ship):
		_owner_ship = _resolve_owner_ship()
	if not is_instance_valid(_owner_ship):
		return cannons
	var container := NodeContractHelper.get_cannons_container(_owner_ship)
	if not is_instance_valid(container):
		return cannons
	_collect_active_cannons(container, cannons)
	return cannons


func _collect_active_cannons(node: Node, out: Array[Node3D]) -> void:
	for child in node.get_children():
		if child is Node3D and _is_active_cannon(child):
			out.append(child as Node3D)
		_collect_active_cannons(child, out)


func _is_active_cannon(node: Variant) -> bool:
	if not is_instance_valid(node) or not (node is Node3D):
		return false
	var cannon := node as Node3D
	if cannon == self:
		return false
	if cannon.is_queued_for_deletion():
		return false
	if cannon.has_method("is_visible_in_tree") and not cannon.is_visible_in_tree():
		return false
	if cannon.has_method("is_processing") and not cannon.is_processing():
		return false
	if "is_preparing" in cannon and bool(cannon.get("is_preparing")):
		return false
	return cannon.has_method("can_cover_reload_allocation_target") or "cannonball_scene" in cannon


func _is_target_in_cannon_forward_arc(cannon: Node3D, target: Node3D) -> bool:
	var aim_point: Vector3 = NodeContractHelper.get_projectile_aim_point(target, 0.55)
	var to_target := aim_point - cannon.global_position
	to_target.y = 0.0
	if to_target.length_squared() <= 0.0001:
		return true
	var forward := -cannon.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() <= 0.0001:
		return false
	var detection_arc_value: float = float(cannon.get("detection_arc")) if "detection_arc" in cannon else 25.0
	var angle := rad_to_deg(acos(clampf(forward.normalized().dot(to_target.normalized()), -1.0, 1.0)))
	return angle < detection_arc_value


func fire(target: Variant) -> void:
	if not missile_scene:
		return
	if not _is_owner_combat_ready():
		return
	var target_node := LauncherCombatHelper.get_enemy_combat_target(target, team)
	if target_node == null:
		return
	if target_node.has_method("get_hull_hp_value") and float(target_node.get_hull_hp_value()) <= 0.0:
		return

	var janggun_lv := _get_janggun_level()
	if janggun_lv <= 0:
		return

	var firing_cannon := _cached_cannon
	if not _is_cannon_target_pair_valid(firing_cannon, target_node):
		firing_cannon = _find_best_cannon_for_target(target_node)
	if not _is_cannon_target_pair_valid(firing_cannon, target_node):
		return

	cooldown_timer = _get_janggun_cooldown(janggun_lv)
	var spawn_pos: Vector3 = _get_cannon_muzzle_position(firing_cannon)

	var target_aim_pos: Vector3 = NodeContractHelper.get_projectile_aim_point(target_node, JANGGUN_SHIP_AIM_VERTICAL_OFFSET)
	var dist := spawn_pos.distance_to(target_aim_pos)
	var stats := _get_janggun_stats()
	var current_projectile_speed := float(stats.get("projectile_speed", projectile_speed))
	var travel_time := dist / maxf(current_projectile_speed, 0.01)

	var target_speed: float = NodeContractHelper.get_current_speed_value(target_node)
	var target_dir: Vector3 = target_node.get_move_direction_value() if target_node.has_method("get_move_direction_value") else -target_node.global_transform.basis.z
	target_dir.y = 0.0
	if target_dir.length_squared() > 0.001:
		target_dir = target_dir.normalized()
	else:
		target_dir = Vector3.FORWARD

	var lead_offset: Vector3 = target_dir * target_speed * travel_time * 0.62
	var max_lead: float = clampf(dist * 0.24, 1.2, 5.5)
	if lead_offset.length() > max_lead:
		lead_offset = lead_offset.normalized() * max_lead
	var predicted_pos: Vector3 = target_aim_pos + lead_offset
	var fire_direction := (predicted_pos - spawn_pos).normalized()
	if fire_direction.is_zero_approx():
		fire_direction = -firing_cannon.global_transform.basis.z
	var missile_damage := float(stats.get("base_damage", damage)) + float(maxi(0, janggun_lv - 1)) * float(stats.get("damage_per_lv", 5.0))

	var missile = ScenePool.acquire(get_tree(), missile_scene)
	get_tree().root.add_child(missile)
	if missile.has_method("launch"):
		missile.launch(spawn_pos, predicted_pos, team, missile_damage, current_projectile_speed, janggun_lv)
	else:
		missile.start_pos = spawn_pos
		missile.target_pos = predicted_pos
		missile.damage = missile_damage
		missile.speed = current_projectile_speed
		if "team" in missile:
			missile.team = team
		if "janggun_lv" in missile:
			missile.janggun_lv = janggun_lv
		missile.global_position = spawn_pos

	_spawn_muzzle_smoke(firing_cannon, fire_direction, clampf(missile_damage / maxf(damage, 0.01), 0.85, 1.45))
	_apply_cannon_post_fire_delay(firing_cannon)

	if DEBUG_COMBAT_LOGS:
		print("[Janggun] 포문 발사 cannon=%s target=%s travel=%.1fs" % [firing_cannon.name, target_node.name, travel_time])


func _get_janggun_level() -> int:
	var um = get_node_or_null("/root/UpgradeManager")
	if is_instance_valid(um) and "current_levels" in um:
		return int(um.current_levels.get("janggun", 0))
	return 0


func _get_janggun_cooldown(level: int) -> float:
	var stats := _get_janggun_stats()
	var base_cooldown := float(stats.get("base_cooldown", fire_cooldown))
	var cooldown_reduce := float(stats.get("cooldown_reduce_per_lv", cooldown_reduce_per_level))
	var cooldown_floor := float(stats.get("min_cooldown", min_fire_cooldown))
	return maxf(cooldown_floor, base_cooldown - max(0, level - 1) * cooldown_reduce)


func _get_janggun_stats() -> Dictionary:
	var um = get_node_or_null("/root/UpgradeManager")
	if is_instance_valid(um) and "UPGRADES" in um:
		return um.UPGRADES.get("janggun", {}).get("stats", {})
	return {}


func _get_cannon_muzzle_position(cannon: Node3D) -> Vector3:
	if is_instance_valid(cannon):
		var muzzle := cannon.get_node_or_null("Muzzle") as Node3D
		if is_instance_valid(muzzle):
			return muzzle.global_position
		return cannon.global_position + Vector3(0.0, 0.9, 0.0)
	return global_position + Vector3(0.0, 1.0, 0.0)


func _spawn_muzzle_smoke(cannon: Node3D, fire_direction: Vector3, muzzle_intensity: float) -> void:
	if muzzle_smoke_scene == null:
		return
	var tree := get_tree()
	if not is_instance_valid(tree):
		return
	var smoke := ScenePool.acquire(tree, muzzle_smoke_scene)
	if not is_instance_valid(smoke):
		return
	if smoke.has_method("configure_as_muzzle"):
		smoke.configure_as_muzzle()
	if smoke.has_method("set_intensity"):
		smoke.set_intensity(muzzle_intensity)
	var muzzle := _get_cannon_muzzle_node(cannon)
	var smoke_dir := fire_direction if not fire_direction.is_zero_approx() else Vector3.FORWARD
	var smoke_position := muzzle.global_position if is_instance_valid(muzzle) else _get_cannon_muzzle_position(cannon)
	var smoke_parent: Node = muzzle if muzzle_smoke_follow_muzzle_time > 0.0 and is_instance_valid(muzzle) else tree.root
	smoke_parent.add_child(smoke)
	if smoke is Node3D:
		(smoke as Node3D).global_transform = Transform3D(_get_muzzle_smoke_basis(smoke_dir), smoke_position)
	if smoke_parent == muzzle:
		_schedule_muzzle_smoke_detach(smoke, muzzle, muzzle_smoke_follow_muzzle_time)
	if smoke.has_method("pool_activate"):
		smoke.pool_activate()
	else:
		_activate_plain_muzzle_smoke(smoke)


func _get_cannon_muzzle_node(cannon: Node3D) -> Node3D:
	if not is_instance_valid(cannon):
		return null
	return cannon.get_node_or_null("Muzzle") as Node3D


func _get_muzzle_smoke_basis(smoke_dir: Vector3) -> Basis:
	var dir := smoke_dir.normalized()
	if dir.is_zero_approx():
		dir = Vector3.FORWARD
	return Basis.looking_at(dir, Vector3.UP)


func _schedule_muzzle_smoke_detach(smoke: Node, muzzle: Node3D, delay: float) -> void:
	var tree := get_tree()
	if not is_instance_valid(tree) or not is_instance_valid(muzzle) or delay <= 0.0:
		return
	var smoke_id := smoke.get_instance_id()
	var muzzle_id := muzzle.get_instance_id()
	tree.create_timer(delay).timeout.connect(func() -> void:
		_detach_muzzle_smoke_to_world(smoke_id, muzzle_id)
	)


func _detach_muzzle_smoke_to_world(smoke_id: int, muzzle_id: int) -> void:
	var smoke := NodeContractHelper.get_instance_node(smoke_id)
	var muzzle_node := NodeContractHelper.get_instance_node(muzzle_id)
	var tree := get_tree()
	if not is_instance_valid(smoke) or not is_instance_valid(muzzle_node) or not is_instance_valid(tree):
		return
	if smoke.get_parent() != muzzle_node:
		return
	var saved_transform := Transform3D.IDENTITY
	if smoke is Node3D:
		saved_transform = (smoke as Node3D).global_transform
	muzzle_node.remove_child(smoke)
	tree.root.add_child(smoke)
	if smoke is Node3D:
		(smoke as Node3D).global_transform = saved_transform


func _activate_plain_muzzle_smoke(smoke: Node) -> void:
	var max_lifetime := _restart_plain_muzzle_particles(smoke)
	if max_lifetime <= 0.0:
		ScenePool.release(smoke)
		return
	var tree := get_tree()
	if not is_instance_valid(tree):
		ScenePool.release(smoke)
		return
	tree.create_timer(max_lifetime + 0.35).timeout.connect(func() -> void:
		ScenePool.release(smoke)
	)


func _restart_plain_muzzle_particles(node: Node) -> float:
	var max_lifetime := 0.0
	if node is GPUParticles3D:
		var particles := node as GPUParticles3D
		particles.visible = true
		particles.restart()
		particles.emitting = true
		max_lifetime = maxf(max_lifetime, particles.lifetime)
	for child in node.get_children():
		max_lifetime = maxf(max_lifetime, _restart_plain_muzzle_particles(child))
	return max_lifetime


func _apply_cannon_post_fire_delay(cannon: Node3D) -> void:
	if not is_instance_valid(cannon) or cannon_post_fire_delay <= 0.0:
		return
	if "cooldown_timer" in cannon:
		cannon.set("cooldown_timer", maxf(float(cannon.get("cooldown_timer")), cannon_post_fire_delay))
