class_name OutOfPlay
extends RefCounted

## Ball-out-of-play detection and the resulting restart decision (Laws 9,
## 15, 16, 17). The side and end walls in world.tscn still physically stop the
## ball — they're a backstop — so "out" means the ball reached a line just
## inside them (MARGIN_PX) rather than truly crossing it. Pure functions so
## they can be unit-tested without a scene (tests/rules_test.gd).

enum Line { NONE, TOP, BOTTOM, LEFT_GOAL_LINE, RIGHT_GOAL_LINE }

## The ball's collision circle (ball.tscn) sits 5px above its origin with a
## 5px radius; the walls stop that circle. MARGIN_PX past the circle's edge is
## what reliably registers before the bounce.
const BALL_COLLISION_OFFSET := Vector2(0, -5)
const MARGIN_PX := 11.0

## Restart spots are placed this far inside the line — well past MARGIN_PX
## so a freshly placed ball doesn't immediately read as out again.
const THROW_IN_INSET_PX := 26.0
const CORNER_INSET := Vector2(0.012, 0.03)  # absolute-normalised
## Goal kick: edge of the six-yard box (~5.5m / 105m).
const GOAL_KICK_DEPTH := 0.052

## Which line (if any) the ball at [param ball_pos] has reached.
## [param left_mouth]/[param right_mouth] = (min_y, max_y) of each goal mouth —
## the goal line is open there (the scoring area handles it, not a restart).
static func crossed(ball_pos: Vector2, left_mouth: Vector2, right_mouth: Vector2) -> int:
	var c := ball_pos + BALL_COLLISION_OFFSET
	var width_px := PitchSpace.right_line_x(c.y) - PitchSpace.left_line_x(c.y)
	var n := PitchSpace.absolute_normalised(c)
	# Penetration past each out-line, in px; the deepest one is the line crossed
	# (matters in the corners, where two lines are close).
	var pen := {
		Line.TOP: (PitchSpace.TOP_Y + MARGIN_PX) - c.y,
		Line.BOTTOM: c.y - (PitchSpace.BOTTOM_Y - MARGIN_PX),
		Line.LEFT_GOAL_LINE: MARGIN_PX - n.x * width_px,
		Line.RIGHT_GOAL_LINE: MARGIN_PX - (1.0 - n.x) * width_px,
	}
	if c.y >= left_mouth.x and c.y <= left_mouth.y:
		pen[Line.LEFT_GOAL_LINE] = -INF
	if c.y >= right_mouth.x and c.y <= right_mouth.y:
		pen[Line.RIGHT_GOAL_LINE] = -INF
	var best := Line.NONE
	var best_pen := 0.0
	for line in pen:
		if pen[line] > best_pen:
			best_pen = pen[line]
			best = line
	return best

## The restart the Laws award when the ball crosses [param line], last touched
## by the left team if [param last_touch_left]. Returns
## {"kind": Restart.Kind, "award_left": bool, "spot": Vector2}.
static func decide(line: int, ball_pos: Vector2, last_touch_left: bool) -> Dictionary:
	var c := ball_pos + BALL_COLLISION_OFFSET
	match line:
		Line.TOP, Line.BOTTOM:
			var y := PitchSpace.TOP_Y + THROW_IN_INSET_PX if line == Line.TOP else PitchSpace.BOTTOM_Y - THROW_IN_INSET_PX
			var nx := clampf(PitchSpace.absolute_normalised(Vector2(c.x, y)).x, 0.02, 0.98)
			var spot := PitchSpace.from_absolute_normalised(Vector2(nx, PitchSpace.absolute_normalised(Vector2(c.x, y)).y))
			return {"kind": Restart.Kind.THROW_IN, "award_left": not last_touch_left, "spot": spot}
		Line.LEFT_GOAL_LINE, Line.RIGHT_GOAL_LINE:
			var defending_left := line == Line.LEFT_GOAL_LINE
			var top_half := PitchSpace.absolute_normalised(c).y < 0.5
			if last_touch_left == defending_left:
				# Defending side put it behind their own goal line → corner.
				var cx := CORNER_INSET.x if defending_left else 1.0 - CORNER_INSET.x
				var cy := CORNER_INSET.y if top_half else 1.0 - CORNER_INSET.y
				return {"kind": Restart.Kind.CORNER, "award_left": not defending_left,
					"spot": PitchSpace.from_absolute_normalised(Vector2(cx, cy))}
			var gx := GOAL_KICK_DEPTH if defending_left else 1.0 - GOAL_KICK_DEPTH
			return {"kind": Restart.Kind.GOAL_KICK, "award_left": defending_left,
				"spot": PitchSpace.from_absolute_normalised(Vector2(gx, 0.5))}
	return {}
