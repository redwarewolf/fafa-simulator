class_name DefenderAI
extends RoleAI

## Ten playing positions, four behaviours (see AIBehaviorFactory) — LB/CB/RB
## all use this class and differ only by anchor/roam/flank data (Positions
## table), not by code. Defensive shape (holding a line behind the ball) and
## man-marking (TeamTacticalState) both apply to any of them; there's no
## separate "emergency" mode any more — a defender's assigned mark pulls them
## goal-side of a dangerous opponent regardless of which zone they're
## nominally in, and the presser bypass handles the ball itself.

const SHOT_RANGE := 360.0

func depth_offset() -> int:
	return -1

func carrier_pull_radii() -> Array:
	return [150.0, 0.3, 300.0, 0.7]

func support_shape_factor() -> float:
	return 0.6

## Only a flank-holder (LB/RB) overlaps forward when a teammate carries the
## ball with pace — a centre-back has no business bombing on, so this stays
## 0 for them and they hold the mirrored line instead. See
## docs/ai-overhaul.md Phase 3.
const OVERLAP_RUN_WEIGHT := 0.5

func run_support_weight() -> float:
	return OVERLAP_RUN_WEIGHT if _holds_flank else 0.0

func role_weights() -> Dictionary:
	return {"shoot": 0.5, "pass": 1.2, "dribble": 0.6, "shot_range": SHOT_RANGE}

func draw_debug() -> void:
	if DebugDraw.SHOW_ROLE_RANGES:
		DebugDraw.circle(player.position, SHOT_RANGE, Color(0.2, 0.5, 1))
		DebugDraw.circle(player.position, TACKLE_DISTANCE, Color(1, 0.6, 0.1))
