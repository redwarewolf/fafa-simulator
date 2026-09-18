class_name ForwardAI
extends RoleAI

const SHOT_RANGE := 420.0

## How far ahead of the mirrored-shape point a run stretches once triggered
## (see _off_ball_base_position), and how much of that run to actually take
## (0 = stay on the shape point, 1 = go all the way to the run point).
const RUN_AHEAD_DISTANCE := 200.0
const RUN_AHEAD_WEIGHT := 0.7
## Carrier speed below which this reads as build-up play, not a break — no
## point sending a runner in behind a teammate who is barely moving.
const RUN_TRIGGER_SPEED := 20.0

func carrier_pull_radii() -> Array:
	return [80.0, 0.7, 180.0, 1.0]

func support_shape_factor() -> float:
	return 0.9

func role_weights() -> Dictionary:
	return {"shoot": 1.3, "pass": 0.9, "dribble": 1.1, "shot_range": SHOT_RANGE}

## Mirroring the formation shape onto wherever the carrier currently is keeps
## the front line's relative spacing but never actually gets ahead of a
## teammate breaking forward with the ball — every forward just trails at a
## fixed offset, which reads as everyone clumping around the carrier. When a
## teammate is actually moving with the ball, pull the base point toward goal
## (a run in behind) and, for wide forwards, back out toward their own flank
## so the run threatens down the side instead of drifting infield with it.
func _off_ball_base_position() -> Vector2:
	var mirrored := super._off_ball_base_position()
	if not is_ball_carried_by_teammate():
		return mirrored
	var carrier := ball.carrier
	if carrier.velocity.length() < RUN_TRIGGER_SPEED:
		return mirrored
	var run_point := mirrored + carrier.position.direction_to(target_goal.get_center_target_position()) * RUN_AHEAD_DISTANCE
	if _holds_flank:
		run_point.y = lerpf(run_point.y, _anchor_y, 0.5)
	return mirrored.lerp(run_point, RUN_AHEAD_WEIGHT)

func draw_debug() -> void:
	if DebugDraw.SHOW_ROLE_RANGES:
		DebugDraw.circle(player.position, SHOT_RANGE, Color(1, 0.2, 0.2))
		DebugDraw.circle(player.position, TACKLE_DISTANCE, Color(1, 0.6, 0.1))
