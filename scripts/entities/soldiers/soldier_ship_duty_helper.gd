extends RefCounted
class_name SoldierShipDutyHelper


static func find_ship_duty_target(soldier) -> Vector3:
	return SoldierShipWorkPriorityHelper.find_ship_work_target(soldier)


static func get_active_ship_duty_target(soldier) -> Vector3:
	return SoldierShipWorkPriorityHelper.get_active_ship_work_target(soldier)
