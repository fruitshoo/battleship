@tool
extends BTAction
class_name BTShipSetPressurePhase


@export var phase_var: StringName = ShipAILimboKeys.VAR_PRESSURE_PHASE
@export var pressure_var: StringName = ShipAILimboKeys.VAR_PRESSURE
@export_range(0.0, 1.0, 0.01) var damaged_ratio: float = 0.6
@export_range(0.0, 1.0, 0.01) var desperate_ratio: float = 0.3
@export_range(0.0, 1.0, 0.01) var damaged_pressure: float = 0.45
@export_range(0.0, 1.0, 0.01) var desperate_pressure: float = 1.0


func _generate_name() -> String:
	return "ShipSetPressurePhase -> %s" % LimboUtility.decorate_var(phase_var)


func _tick(_delta: float) -> Status:
	if not is_instance_valid(agent):
		return FAILURE

	var hull_ratio := _get_hull_ratio(agent)
	var phase := ShipAILimboKeys.PHASE_STABLE
	var pressure := 0.0
	if hull_ratio <= desperate_ratio:
		phase = ShipAILimboKeys.PHASE_DESPERATE
		pressure = desperate_pressure
	elif hull_ratio <= damaged_ratio:
		phase = ShipAILimboKeys.PHASE_DAMAGED
		pressure = damaged_pressure

	pressure = clampf(pressure, 0.0, 1.0)
	blackboard.set_var(phase_var, phase)
	blackboard.set_var(pressure_var, pressure)
	agent.set_meta(ShipAILimboKeys.META_PRESSURE_PHASE, phase)
	agent.set_meta(ShipAILimboKeys.META_PRESSURE, pressure)
	return SUCCESS


func _get_hull_ratio(ship: Node) -> float:
	if ship.has_method("get_hull_ratio"):
		return clampf(float(ship.call("get_hull_ratio")), 0.0, 1.0)

	var max_hull := 0.0
	var hull := 0.0
	if ship.get("max_hull_hp") != null:
		max_hull = float(ship.get("max_hull_hp"))
	if ship.get("hull_hp") != null:
		hull = float(ship.get("hull_hp"))
	if max_hull <= 0.0:
		return 1.0
	return clampf(hull / max_hull, 0.0, 1.0)
