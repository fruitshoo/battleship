extends RefCounted
class_name SoldierShipDutyHelper

const SoldierShipWorkPriorityHelper = preload("res://scripts/entities/soldiers/soldier_ship_work_priority_helper.gd")

static func find_ship_duty_target(soldier) -> Vector3:
	return SoldierShipWorkPriorityHelper.find_ship_work_target(soldier)
