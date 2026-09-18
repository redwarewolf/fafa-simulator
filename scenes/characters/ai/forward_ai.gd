class_name ForwardAI
extends RoleAI

const SHOT_RANGE := 420.0

## How far ahead of the mirrored-shape point a run stretches once triggered,
## and how much of that run to actually take (0 = stay on the shape point,
## 1 = go all the way to the run point) — see RoleAI._apply_run_support().
const RUN_AHEAD_DISTANCE := 200.0
const RUN_AHEAD_WEIGHT := 0.7

func carrier_pull_radii() -> Array:
	return [80.0, 0.7, 180.0, 1.0]

func support_shape_factor() -> float:
	return 0.9

func role_weights() -> Dictionary:
	return {"shoot": 1.3, "pass": 0.9, "dribble": 1.1, "shot_range": SHOT_RANGE}

func run_support_weight() -> float:
	return RUN_AHEAD_WEIGHT

func run_support_distance() -> float:
	return RUN_AHEAD_DISTANCE

func draw_debug() -> void:
	if DebugDraw.SHOW_ROLE_RANGES:
		DebugDraw.circle(player.position, SHOT_RANGE, Color(1, 0.2, 0.2))
		DebugDraw.circle(player.position, TACKLE_DISTANCE, Color(1, 0.6, 0.1))
