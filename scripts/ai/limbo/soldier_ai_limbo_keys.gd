extends RefCounted


const VAR_TARGET := &"soldier_target"
const VAR_TARGET_DISTANCE := &"soldier_target_distance"
const VAR_MODE := &"soldier_mode"
const VAR_POINT := &"soldier_point"
const VAR_REASON := &"soldier_reason"

const META_FRAME := "soldier_limbo_ai_frame"
const META_TARGET_ID := "soldier_limbo_ai_target_id"
const META_TARGET_DISTANCE := "soldier_limbo_ai_target_distance"
const META_MODE := "soldier_limbo_ai_mode"
const META_POINT := "soldier_limbo_ai_point"
const META_REASON := "soldier_limbo_ai_reason"

const META_STALE_FRAMES := 8

const MODE_ATTACK_TARGET := "attack_target"
const MODE_MOVE_TO_TARGET := "move_to_target"
const MODE_SHIP_DUTY := "ship_duty"
const MODE_MUSTER_CROSS_SHIP := "muster_cross_ship"
const MODE_WANDER := "wander"
