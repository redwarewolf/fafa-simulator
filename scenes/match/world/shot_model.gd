class_name ShotModel
extends RefCounted

## Expected-goals (xG) model. A logistic in shot distance and the angle the
## goal mouth subtends from the shooter, in metres (PitchSpace), the two
## dominant features of every public xG model (Caley, Pollard & Reep,
## StatsBomb). Phase 1 uses it purely as an analytics metric for the batch
## harness; Phase 3 adds pressure/blocker/keeper terms and the AI starts
## deciding with it.
##
## Coefficients give roughly 0.55 from 5m central, 0.25 from the penalty spot
## and 0.05 from 25m central, in line with published open-play curves.
const B0 := -1.1
const B_ANGLE := 1.6   # per radian of goal-mouth angle
const B_DIST := -0.09  # per metre from the goal centre

static func xg_basic(origin: Vector2, goal_top: Vector2, goal_bottom: Vector2) -> float:
	var o := PitchSpace.to_metres(origin)
	var t := PitchSpace.to_metres(goal_top)
	var b := PitchSpace.to_metres(goal_bottom)
	var angle := absf((t - o).angle_to(b - o))
	var dist := o.distance_to((t + b) * 0.5)
	var z := B0 + B_ANGLE * angle + B_DIST * dist
	return 1.0 / (1.0 + exp(-z))

static func xg_for_goal(origin: Vector2, goal: Goal) -> float:
	return xg_basic(origin, goal.get_top_target_position(), goal.get_bottom_target_position())

## Outfield opponents inside the shooting triangle (origin → both posts) block
## part of the goal: each multiplies xG down by up to BLOCK_MAX, most when
## standing right on the shot line close to the shooter.
const BLOCK_MAX := 0.45
## An opponent within PRESSURE_RADIUS_M of the shooter rushes the shot.
const PRESSURE_RADIUS_M := 2.0
const PRESSURE_FACTOR := 0.75

## Contextual xG: xg_basic discounted for blockers and pressure (the two
## biggest non-geometric terms in public xG models). The keeper is excluded
## from blocking — the base model already assumes one.
static func xg(origin: Vector2, goal: Goal, opponents: Array) -> float:
	var top := goal.get_top_target_position()
	var bottom := goal.get_bottom_target_position()
	var value := xg_basic(origin, top, bottom)
	var tri := PackedVector2Array([origin, top, bottom])
	var centre := (top + bottom) * 0.5
	var shot_len := maxf(origin.distance_to(centre), 1.0)
	for o in opponents:
		if o.role == Positions.Role.GK:
			continue
		if PitchSpace.distance_m(o.position, origin) < PRESSURE_RADIUS_M:
			value *= PRESSURE_FACTOR
		if Geometry2D.is_point_in_polygon(o.position, tri):
			var along := clampf(origin.distance_to(o.position) / shot_len, 0.0, 1.0)
			value *= 1.0 - BLOCK_MAX * (1.0 - along)
	return value
