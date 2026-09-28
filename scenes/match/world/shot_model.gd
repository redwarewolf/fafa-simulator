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
