extends TestCase

## BallPredictor, PassModel, PitchControlGrid, XtGrid, ShotModel.xg (Phase 3).

var _made : Array[Player] = []

func _player(pos: Vector2, speed: float = 70.0, vel: Vector2 = Vector2.ZERO) -> Player:
	var p := Player.new()
	p.position = pos
	p.speed = speed
	p.velocity = vel
	_made.append(p)
	return p

func _free_players() -> void:
	for p in _made:
		p.free()
	_made.clear()

# ─── BallPredictor ──────────────────────────────────────────────────────────

## A grounded pass_to() is sized to decelerate to a stop exactly at the target.
func test_ground_pass_stops_at_target() -> void:
	var from := Vector2(600, 600)
	for dist in [120.0, 250.0]:
		var to := from + Vector2(dist, 0)
		var path := BallPredictor.for_pass(from, to, 6.0)
		assert_true(path.stop_time != INF, "ground pass %d stops" % dist)
		assert_near(path.end_position().distance_to(to), 0.0, dist * 0.03, "ground pass %d lands within 3%%" % dist)

## Ball.pass_launch solves a lofted pass so its FIRST LANDING is on the target
## (it used to land at ~26-30% of the distance — Findings #2). Samples are
## Samples are 0.1s apart and the landing tick bounces straight back up, so
## check where the ball is at the solved landing time rather than hunting for
## a zero-height sample (tools/ball_probe.tscn measures the real ball per tick:
## 97-98% of the distance).
func test_lofted_pass_first_landing_near_target() -> void:
	var from := Vector2(400, 600)
	for dist in [350.0, 600.0, 900.0]:
		var to := from + Vector2(dist, 0)
		var path := BallPredictor.for_pass(from, to, 6.0)
		var at_landing := path.position_at(Ball.loft_time(dist))
		var err : float = absf(at_landing.x - to.x) / dist
		assert_true(err < 0.05, "lofted %d at landing time within 5%% of target (got %.3f)" % [dist, err])

func test_shot_hot_phase_is_frictionless() -> void:
	var path := BallPredictor.simulate(Vector2.ZERO, Vector2(200, 0), 5.0, 0.0, 1.0, 1.0)
	assert_near(path.position_at(1.0).x, 200.0, 4.0, "1s of hot flight at 200px/s")

func test_earliest_intercept_prefers_player_on_the_line() -> void:
	var path := BallPredictor.for_pass(Vector2(500, 600), Vector2(800, 600))
	var on_line := _player(Vector2(650, 610))
	var far := _player(Vector2(650, 900))
	var r := BallPredictor.first_to_ball(path, [far, on_line])
	assert_true(r["player"] == on_line, "player next to the path gets there first")
	_free_players()

# ─── PassModel ──────────────────────────────────────────────────────────────

func test_open_pass_is_likely_blocked_pass_is_not() -> void:
	var passer := _player(Vector2(600, 600))
	var receiver := _player(Vector2(800, 600))
	var far_defender := _player(Vector2(700, 950))
	var open := PassModel.evaluate(passer.position, receiver.position, passer, receiver, [passer, receiver], [far_defender])
	assert_true(open.p_success > 0.8, "open 200px pass (got %.2f)" % open.p_success)
	var in_lane := _player(Vector2(700, 602))
	var blocked := PassModel.evaluate(passer.position, receiver.position, passer, receiver, [passer, receiver], [in_lane])
	assert_true(blocked.p_success < 0.35, "defender standing in the lane (got %.2f)" % blocked.p_success)
	var marked := _player(Vector2(812, 600))
	var tight := PassModel.evaluate(passer.position, receiver.position, passer, receiver, [passer, receiver], [marked])
	assert_true(tight.p_success < open.p_success - 0.2, "tightly marked receiver scores lower (%.2f vs %.2f)" % [tight.p_success, open.p_success])
	_free_players()

func test_through_ball_into_space_needs_the_runner_to_win_the_race() -> void:
	var passer := _player(Vector2(900, 600))
	var runner := _player(Vector2(1300, 600), 90.0, Vector2(100, 0))
	var slow_defender := _player(Vector2(1250, 700), 50.0)
	var target := Vector2(1500, 600)
	var good := PassModel.evaluate(passer.position, target, passer, null, [passer, runner], [slow_defender])
	var quick_defender := _player(Vector2(1480, 620), 90.0)
	var bad := PassModel.evaluate(passer.position, target, passer, null, [passer, runner], [quick_defender])
	assert_true(good.p_success > bad.p_success + 0.3, "space pass: runner ahead (%.2f) vs defender already there (%.2f)" % [good.p_success, bad.p_success])
	_free_players()

# ─── PitchControlGrid ───────────────────────────────────────────────────────

func test_pitch_control_follows_the_players() -> void:
	var left_p := _player(PitchSpace.from_absolute_normalised(Vector2(0.25, 0.5)))
	var right_p := _player(PitchSpace.from_absolute_normalised(Vector2(0.75, 0.5)))
	var grid := PitchControlGrid.new()
	grid.update_all([left_p], [right_p])
	var near_left := PitchSpace.from_absolute_normalised(Vector2(0.2, 0.5))
	var near_right := PitchSpace.from_absolute_normalised(Vector2(0.8, 0.5))
	var middle := PitchSpace.from_absolute_normalised(Vector2(0.5, 0.5))
	assert_true(grid.left_control_at(near_left) > 0.9, "left owns its side")
	assert_true(grid.left_control_at(near_right) < 0.1, "right owns its side")
	assert_near(grid.left_control_at(middle), 0.5, 0.1, "contested midpoint")
	assert_near(grid.control_at(near_right, false), 1.0 - grid.left_control_at(near_right), 0.0001, "sides complement")
	_free_players()

# ─── XtGrid / ShotModel ─────────────────────────────────────────────────────

func test_xt_landmarks() -> void:
	var halfway := XtGrid.at_normalised(Vector2(0.5, 0.5))
	var edge_of_box := XtGrid.at_normalised(Vector2(0.84, 0.5))
	var penalty_spot := XtGrid.at_normalised(Vector2(0.895, 0.5))
	var own_box := XtGrid.at_normalised(Vector2(0.08, 0.5))
	var wide_byline := XtGrid.at_normalised(Vector2(0.97, 0.05))
	assert_between(halfway, 0.005, 0.025, "halfway")
	assert_between(edge_of_box, 0.05, 0.16, "edge of box")
	assert_between(penalty_spot, 0.12, 0.35, "penalty spot")
	assert_between(own_box, 0.0, 0.01, "own box")
	assert_between(wide_byline, 0.005, 0.08, "wide on the byline")
	assert_true(own_box < halfway and halfway < edge_of_box and edge_of_box < penalty_spot, "monotonic toward goal")

func test_xt_mirrors_between_teams() -> void:
	var p := PitchSpace.from_absolute_normalised(Vector2(0.8, 0.4))
	var q := PitchSpace.from_absolute_normalised(Vector2(0.2, 0.4))
	assert_near(XtGrid.at(p, true), XtGrid.at(q, false), 0.002, "same threat attacking either way")
