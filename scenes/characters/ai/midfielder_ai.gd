class_name MidfielderAI
extends RoleAI

const SHOT_RANGE := 340.0

func carrier_pull_radii() -> Array:
	return [100.0, 0.5, 200.0, 0.9]

func support_shape_factor() -> float:
	return 0.8

func role_weights() -> Dictionary:
	return {"shoot": 0.9, "pass": 1.1, "dribble": 1.0, "shot_range": SHOT_RANGE}

func draw_debug() -> void:
	if DebugDraw.SHOW_ROLE_RANGES:
		DebugDraw.circle(player.position, SHOT_RANGE, Color(0.2, 1, 0.5))
		DebugDraw.circle(player.position, TACKLE_DISTANCE, Color(1, 0.6, 0.1))
