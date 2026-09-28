extends TestCase

## Offside geometry and out-of-play detection/decisions (Phase 2).

const NO_MOUTH := Vector2(-1.0, -1.0)  # goal mouths disabled for a test

func _mouths() -> Array:
	var cy := (PitchSpace.TOP_Y + PitchSpace.BOTTOM_Y) * 0.5
	var m := Vector2(cy - 40.0, cy + 40.0)
	return [m, m]

## A ball whose collision centre (origin + OutOfPlay.BALL_COLLISION_OFFSET)
## sits at [param centre].
func _ball_at(centre: Vector2) -> Vector2:
	return centre - OutOfPlay.BALL_COLLISION_OFFSET

# ─── Offside ────────────────────────────────────────────────────────────────

func test_offside_line_is_second_last_defender() -> void:
	# Keeper at 0.98, last outfielder at 0.80, others further up.
	var line := OffsideJudge.offside_line([0.98, 0.80, 0.60, 0.55], 0.40)
	assert_near(line, 0.80, 0.0001)

func test_offside_line_is_ball_when_ball_is_deeper() -> void:
	assert_near(OffsideJudge.offside_line([0.98, 0.70], 0.85), 0.85, 0.0001)

func test_offside_line_with_one_defender_is_goal_line() -> void:
	assert_near(OffsideJudge.offside_line([0.9], 0.4), 1.0, 0.0001)

func test_offside_position_rules() -> void:
	assert_true(OffsideJudge.is_offside_position(0.85, 0.80), "clearly beyond the line")
	assert_true(not OffsideJudge.is_offside_position(0.801, 0.80), "level (within tolerance) is onside")
	assert_true(not OffsideJudge.is_offside_position(0.45, 0.30), "own half is never offside")
	assert_true(not OffsideJudge.is_offside_position(0.70, 0.80), "behind the line")

# ─── Out of play ────────────────────────────────────────────────────────────

func test_ball_in_middle_is_in_play() -> void:
	var m := _mouths()
	var centre := PitchSpace.from_absolute_normalised(Vector2(0.5, 0.5))
	assert_eq(OutOfPlay.crossed(_ball_at(centre), m[0], m[1]), OutOfPlay.Line.NONE)

func test_touchlines_detected() -> void:
	var m := _mouths()
	var top := Vector2(1100, PitchSpace.TOP_Y + 3.0)
	var bottom := Vector2(1100, PitchSpace.BOTTOM_Y - 3.0)
	assert_eq(OutOfPlay.crossed(_ball_at(top), m[0], m[1]), OutOfPlay.Line.TOP, "top")
	assert_eq(OutOfPlay.crossed(_ball_at(bottom), m[0], m[1]), OutOfPlay.Line.BOTTOM, "bottom")

## The goal lines are slanted: a point just inside the line near the bottom
## has a much smaller x than one near the top, and both must read correctly.
func test_slanted_goal_lines_detected() -> void:
	var m := [NO_MOUTH, NO_MOUTH]
	for y in [250.0, 900.0]:
		var just_out := Vector2(PitchSpace.left_line_x(y) + 3.0, y)
		var just_in := Vector2(PitchSpace.left_line_x(y) + 40.0, y)
		assert_eq(OutOfPlay.crossed(_ball_at(just_out), m[0], m[1]), OutOfPlay.Line.LEFT_GOAL_LINE, "left y=%d" % y)
		assert_eq(OutOfPlay.crossed(_ball_at(just_in), m[0], m[1]), OutOfPlay.Line.NONE, "left inside y=%d" % y)
		var right_out := Vector2(PitchSpace.right_line_x(y) - 3.0, y)
		assert_eq(OutOfPlay.crossed(_ball_at(right_out), m[0], m[1]), OutOfPlay.Line.RIGHT_GOAL_LINE, "right y=%d" % y)

func test_goal_mouth_is_not_out() -> void:
	var m := _mouths()
	var cy := (PitchSpace.TOP_Y + PitchSpace.BOTTOM_Y) * 0.5
	var in_mouth := Vector2(PitchSpace.left_line_x(cy) + 2.0, cy)
	assert_eq(OutOfPlay.crossed(_ball_at(in_mouth), m[0], m[1]), OutOfPlay.Line.NONE)

func test_decisions_follow_last_touch() -> void:
	var y := 300.0
	var ball := _ball_at(Vector2(PitchSpace.left_line_x(y) + 2.0, y))
	var by_defender := OutOfPlay.decide(OutOfPlay.Line.LEFT_GOAL_LINE, ball, true)
	assert_eq(by_defender["kind"], Restart.Kind.CORNER, "defender last touch → corner")
	assert_eq(by_defender["award_left"], false, "corner to the attacking (right) side")
	assert_true(PitchSpace.absolute_normalised(by_defender["spot"]).y < 0.5, "top corner")
	var by_attacker := OutOfPlay.decide(OutOfPlay.Line.LEFT_GOAL_LINE, ball, false)
	assert_eq(by_attacker["kind"], Restart.Kind.GOAL_KICK, "attacker last touch → goal kick")
	assert_eq(by_attacker["award_left"], true)
	var throw := OutOfPlay.decide(OutOfPlay.Line.TOP, _ball_at(Vector2(900, PitchSpace.TOP_Y)), true)
	assert_eq(throw["kind"], Restart.Kind.THROW_IN)
	assert_eq(throw["award_left"], false, "throw-in to the side that didn't touch it")

func test_restart_spots_are_in_play() -> void:
	var m := _mouths()
	var cases := [
		OutOfPlay.decide(OutOfPlay.Line.TOP, _ball_at(Vector2(900, PitchSpace.TOP_Y)), true),
		OutOfPlay.decide(OutOfPlay.Line.BOTTOM, _ball_at(Vector2(900, PitchSpace.BOTTOM_Y)), true),
		OutOfPlay.decide(OutOfPlay.Line.LEFT_GOAL_LINE, _ball_at(Vector2(PitchSpace.left_line_x(900), 900)), true),
		OutOfPlay.decide(OutOfPlay.Line.RIGHT_GOAL_LINE, _ball_at(Vector2(PitchSpace.right_line_x(250), 250)), false),
		OutOfPlay.decide(OutOfPlay.Line.RIGHT_GOAL_LINE, _ball_at(Vector2(PitchSpace.right_line_x(250), 250)), true),
	]
	for d in cases:
		# A ball placed with its origin on the spot must not read as out.
		assert_eq(OutOfPlay.crossed(d["spot"], m[0], m[1]), OutOfPlay.Line.NONE, "spot %s kind %d" % [d["spot"], d["kind"]])
