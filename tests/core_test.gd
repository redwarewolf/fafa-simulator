extends TestCase

## PitchSpace conversions, ShotModel calibration, MatchRng reproducibility.

func test_pitch_space_corners_map_to_real_dimensions() -> void:
	var tl := Vector2(PitchSpace.LEFT_TOP_X, PitchSpace.TOP_Y)
	var br := Vector2(PitchSpace.RIGHT_BOTTOM_X, PitchSpace.BOTTOM_Y)
	assert_near(PitchSpace.to_metres(tl).length(), 0.0, 0.001, "top-left")
	var far := PitchSpace.to_metres(br)
	assert_near(far.x, PitchSpace.LENGTH_M, 0.01, "length")
	assert_near(far.y, PitchSpace.WIDTH_M, 0.01, "width")

## The goal lines are slanted in screen space (perspective): their top and
## bottom ends differ in x but must be the same pitch depth.
func test_slanted_goal_line_is_constant_depth() -> void:
	var top := Vector2(PitchSpace.LEFT_TOP_X, PitchSpace.TOP_Y)
	var bottom := Vector2(PitchSpace.LEFT_BOTTOM_X, PitchSpace.BOTTOM_Y)
	assert_near(PitchSpace.absolute_normalised(top).x, 0.0, 0.001, "left line top")
	assert_near(PitchSpace.absolute_normalised(bottom).x, 0.0, 0.001, "left line bottom")
	var mid_right := Vector2(PitchSpace.right_line_x(600.0), 600.0)
	assert_near(PitchSpace.absolute_normalised(mid_right).x, 1.0, 0.001, "right line middle")

func test_normalised_roundtrip_both_sides() -> void:
	var p := Vector2(700, 400)
	for left in [true, false]:
		var n := PitchSpace.normalised(p, left)
		assert_true(PitchSpace.from_normalised(n, left).distance_to(p) < 0.01, "roundtrip left=%s" % left)

func test_normalised_x_is_attacking_direction() -> void:
	var near_left_goal := Vector2(PitchSpace.left_line_x(600.0) + 10, 600.0)
	assert_true(PitchSpace.normalised(near_left_goal, true).x < 0.05, "left team's own goal is x≈0")
	assert_true(PitchSpace.normalised(near_left_goal, false).x > 0.95, "right team attacks the left goal (x≈1)")

## Goal posts ~5m apart centred on the right goal line.
func _right_goal_posts() -> Array:
	var cy := (PitchSpace.TOP_Y + PitchSpace.BOTTOM_Y) * 0.5
	var half_px := 2.5 / PitchSpace.metres_per_px().y
	return [
		Vector2(PitchSpace.right_line_x(cy - half_px), cy - half_px),
		Vector2(PitchSpace.right_line_x(cy + half_px), cy + half_px),
	]

func _xg_from_metres_out(m: float, lateral_m: float = 0.0) -> float:
	var posts := _right_goal_posts()
	var mpp := PitchSpace.metres_per_px()
	var goal_c : Vector2 = (posts[0] + posts[1]) * 0.5
	var origin := goal_c - Vector2(m / mpp.x, -lateral_m / mpp.y)
	return ShotModel.xg_basic(origin, posts[0], posts[1])

func test_xg_monotonic_in_distance() -> void:
	var close := _xg_from_metres_out(6.0)
	var mid := _xg_from_metres_out(12.0)
	var far := _xg_from_metres_out(25.0)
	assert_true(close > mid and mid > far, "xg must fall with distance (%.3f %.3f %.3f)" % [close, mid, far])
	assert_between(far, 0.01, 0.08, "25m central")
	assert_between(close, 0.25, 0.7, "6m central")

func test_xg_falls_with_tighter_angle() -> void:
	assert_true(_xg_from_metres_out(10.0, 0.0) > _xg_from_metres_out(10.0, 12.0), "central beats wide at same depth")

func test_match_rng_reproducible() -> void:
	MatchRng.seed_match(42)
	var a := [MatchRng.randf(), MatchRng.randi_range(0, 100), MatchRng.randfn()]
	MatchRng.seed_match(42)
	var b := [MatchRng.randf(), MatchRng.randi_range(0, 100), MatchRng.randfn()]
	assert_eq(a, b, "same seed same draws")
