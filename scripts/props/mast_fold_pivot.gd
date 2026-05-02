@tool
extends Node3D

## Hinge controller for mast roots authored as MastPivot_* nodes.
## The pivot node's origin is the hinge point; child mast scenes rotate around it.

enum FoldAxis { X, Y, Z }

@export var folded: bool = false:
	set(value):
		folded = bool(value)
		_target_fold_ratio = 1.0 if folded else 0.0
		if Engine.is_editor_hint():
			fold_ratio = _target_fold_ratio
		elif is_inside_tree():
			set_process(true)

@export_range(0.0, 1.0, 0.01) var fold_ratio: float = 0.0:
	set(value):
		fold_ratio = clampf(value, 0.0, 1.0)
		_apply_fold_transform()
		_apply_folded_sail_state()

@export var fold_axis: FoldAxis = FoldAxis.X:
	set(value):
		fold_axis = value
		_apply_fold_transform()

@export_range(-120.0, 120.0, 1.0, "degrees") var fold_angle_degrees: float = 82.0:
	set(value):
		fold_angle_degrees = value
		_apply_fold_transform()

@export_range(0.05, 5.0, 0.05, "suffix:s") var fold_duration: float = 0.85
@export var auto_furl_child_sails: bool = true
@export_node_path("Node3D") var stow_target_path: NodePath:
	set(value):
		stow_target_path = value
		_apply_fold_transform()
@export_range(0.0, 0.95, 0.01) var stow_start_ratio: float = 0.0:
	set(value):
		stow_start_ratio = value
		_apply_fold_transform()

var _rest_transform := Transform3D.IDENTITY
var _has_rest_transform := false
var _target_fold_ratio := 0.0
var _cached_sail_ratios: Dictionary = {}


func _ready() -> void:
	_capture_rest_transform()
	_target_fold_ratio = 1.0 if folded else fold_ratio
	if folded and fold_ratio < 1.0:
		fold_ratio = 1.0
	else:
		_apply_fold_transform()
		_apply_folded_sail_state()
	set_process(not Engine.is_editor_hint() and not is_equal_approx(fold_ratio, _target_fold_ratio))


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if is_equal_approx(fold_ratio, _target_fold_ratio):
		fold_ratio = _target_fold_ratio
		set_process(false)
		return
	var speed := 1.0 / maxf(fold_duration, 0.05)
	fold_ratio = move_toward(fold_ratio, _target_fold_ratio, speed * delta)


func set_folded(value: bool, immediate: bool = false) -> void:
	folded = value
	if immediate:
		fold_ratio = 1.0 if folded else 0.0


func toggle_folded(immediate: bool = false) -> void:
	set_folded(not folded, immediate)


func is_folded() -> bool:
	return folded


func get_fold_ratio() -> float:
	return fold_ratio


func capture_current_as_rest() -> void:
	_rest_transform = transform
	_has_rest_transform = true
	fold_ratio = 0.0
	_target_fold_ratio = 1.0 if folded else 0.0


func _capture_rest_transform() -> void:
	if _has_rest_transform:
		return
	_rest_transform = transform
	_has_rest_transform = true


func _apply_fold_transform() -> void:
	if not _has_rest_transform:
		return
	var eased_ratio := _smooth_fold_ratio(fold_ratio)
	if _has_stow_target():
		transform = _get_stowed_fold_transform(eased_ratio)
		return
	var fold_basis := Basis(_get_fold_axis_vector(), deg_to_rad(fold_angle_degrees) * eased_ratio)
	transform = Transform3D(_rest_transform.basis * fold_basis, _rest_transform.origin)


func _has_stow_target() -> bool:
	if str(stow_target_path).is_empty() or not is_inside_tree():
		return false
	return get_node_or_null(stow_target_path) is Node3D


func _get_stowed_fold_transform(eased_ratio: float) -> Transform3D:
	var hinge_basis := Basis(_get_fold_axis_vector(), deg_to_rad(fold_angle_degrees) * eased_ratio)
	var hinge_transform := Transform3D(_rest_transform.basis * hinge_basis, _rest_transform.origin)
	var stow_target := get_node_or_null(stow_target_path) as Node3D
	if stow_target == null:
		return hinge_transform
	var start_ratio := clampf(stow_start_ratio, 0.0, 0.95)
	var stow_ratio := clampf((eased_ratio - start_ratio) / (1.0 - start_ratio), 0.0, 1.0)
	var stow_eased := _smooth_fold_ratio(stow_ratio)
	return hinge_transform.interpolate_with(_get_target_local_transform(stow_target), stow_eased)


func _smooth_fold_ratio(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


func _get_target_local_transform(target: Node3D) -> Transform3D:
	if target.get_parent() == get_parent():
		return target.transform
	var parent_3d := get_parent() as Node3D
	if parent_3d == null:
		return target.transform
	return parent_3d.global_transform.affine_inverse() * target.global_transform


func _get_fold_axis_vector() -> Vector3:
	match fold_axis:
		FoldAxis.Y:
			return Vector3.UP
		FoldAxis.Z:
			return Vector3.FORWARD
		_:
			return Vector3.RIGHT


func _apply_folded_sail_state() -> void:
	if not auto_furl_child_sails:
		return
	if fold_ratio > 0.001:
		_cache_child_sail_ratios()
		for mast in _get_child_masts():
			if not is_instance_valid(mast) or not mast.has_method("set_sail_deployed_ratio"):
				continue
			var instance_id := mast.get_instance_id()
			var base_ratio := float(_cached_sail_ratios.get(instance_id, 1.0))
			mast.call("set_sail_deployed_ratio", lerpf(base_ratio, 0.0, fold_ratio))
		return
	if _cached_sail_ratios.is_empty():
		return
	for mast in _get_child_masts():
		if not is_instance_valid(mast) or not mast.has_method("set_sail_deployed_ratio"):
			continue
		var instance_id := mast.get_instance_id()
		if _cached_sail_ratios.has(instance_id):
			mast.call("set_sail_deployed_ratio", float(_cached_sail_ratios[instance_id]))
	_cached_sail_ratios.clear()


func _cache_child_sail_ratios() -> void:
	for mast in _get_child_masts():
		if not is_instance_valid(mast) or not mast.has_method("get_sail_deployed_ratio"):
			continue
		var instance_id := mast.get_instance_id()
		if not _cached_sail_ratios.has(instance_id):
			_cached_sail_ratios[instance_id] = float(mast.call("get_sail_deployed_ratio"))


func _get_child_masts() -> Array[Node]:
	var results: Array[Node] = []
	for child in get_children():
		if child.name.begins_with("Mast") or child.has_method("set_sail_deployed_ratio"):
			results.append(child)
	return results
