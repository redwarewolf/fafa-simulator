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

## A grounded pass_to() arrives at the target still rolling at
## Ball.GROUND_PASS_ARRIVAL_SPEED, at the time estimate_pass_flight_time says.
func test_ground_pass_arrives_with_pace() -> void:
	var from := Vector2(600, 600)
	for dist in [120.0, 250.0, 480.0]:
		var to := from + Vector2(dist, 0)
		var path := BallPredictor.for_pass(from, to, 6.0)
		var t := (sqrt(Ball.GROUND_PASS_ARRIVAL_SPEED ** 2 + 2.0 * dist * Ball.FRICTION_GROUND) - Ball.GROUND_PASS_ARRIVAL_SPEED) / Ball.FRICTION_GROUND
		assert_near(path.position_at(t).x, to.x, dist * 0.04, "ground pass %d reaches the target on time" % dist)
		assert_true(path.end_position().x > to.x, "ground pass %d rolls on past the target" % dist)

## Ball.pass_launch solves a lofted pass so its FIRST LANDING is on the target
## (it used to land at ~26-30% of the distance — Findings #2). Samples are
## Samples are 0.1s apart and the landing tick bounces straight back up, so
## check where the ball is at the solved landing time rather than hunting for
## a zero-height sample (tools/ball_probe.tscn measures the real ball per tick:
## 97-98% of the distance).
func test_lofted_pass_first_landing_near_target() -> void:
	var from := Vector2(400, 600)
	for dist in [600.0, 900.0]:
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

## Kinematics: standing start vs flying start vs running the wrong way.
func test_kinematic_time_to_reach() -> void:
	var vmax := 180.0
	var a := 100.0
	var standing := PitchControl.kinematic_time(300.0, 0.0, vmax, a)
	var flying := PitchControl.kinematic_time(300.0, vmax, vmax, a)
	var reversing := PitchControl.kinematic_time(300.0, -vmax, vmax, a)
	assert_near(flying, 300.0 / vmax, 0.001, "already at top speed")
	# Standing: 1.8s to reach vmax covering 162px, then 138px at 180 → 2.567s.
	assert_near(standing, 1.8 + 138.0 / 180.0, 0.01, "standing start")
	assert_true(reversing > standing, "having to stop first is slower")

## Movement limits: a v2 player can't reverse instantly.
func test_steer_velocity_limits_turning() -> void:
	var p := _player(Vector2.ZERO, 100.0, Vector2(150, 0))
	p.max_accel = 100.0
	p.steer_velocity(Vector2(-150, 0), 0.1)
	# Reversing: speed drops at the braking rate (the running direction also
	# starts rotating — Player._turn_and_run — so check the true speed).
	assert_near(PitchSpace.iso_len(p.velocity), 150.0 - 100.0 * Player.BRAKE_FACTOR * 0.1, 0.01, "braking limited per frame")
	var q := _player(Vector2.ZERO, 100.0, Vector2(150, 0))
	q.steer_velocity(Vector2(-150, 0), 0.1)
	assert_near(q.velocity.x, -150.0, 0.01, "v1 (max_accel 0) snaps as before")
	_free_players()

## First touch: a slow ground ball is trivial, a fast dropping one is not, and
## skill helps with the hard ones.
func test_first_touch_difficulty() -> void:
	assert_near(Player.control_chance_for(50, 50, 40.0, 0.0), 1.0, 0.001, "slow ground ball")
	var hard_avg := Player.control_chance_for(50, 50, 480.0, 15.0)
	var hard_good := Player.control_chance_for(95, 90, 480.0, 15.0)
	assert_between(hard_avg, 0.4, 0.75, "fast dropping ball, average player")
	assert_true(hard_good > hard_avg + 0.15, "skilled player controls it better (%.2f vs %.2f)" % [hard_good, hard_avg])

## A lofted pass flies over a defender standing under its apex (the recurring
## long-pass bug: pickup used to ignore height), but not over one standing
## where it comes down.
func test_lofted_pass_flies_over_midway_defender() -> void:
	var passer := _player(Vector2(500, 600))
	var receiver := _player(Vector2(1100, 600))
	var under_apex := _player(Vector2(800, 600))
	var over := PassModel.evaluate(passer.position, receiver.position, passer, receiver, [passer, receiver], [under_apex])
	assert_true(over.p_intercept < 0.2, "defender under the apex can't reach it (p_intercept %.2f)" % over.p_intercept)
	var at_landing := _player(Vector2(1085, 600))
	var met := PassModel.evaluate(passer.position, receiver.position, passer, receiver, [passer, receiver], [at_landing])
	assert_true(met.p_success < over.p_success - 0.3, "defender at the landing spot contests it (%.2f vs %.2f)" % [met.p_success, over.p_success])
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

## The pitch is drawn squashed vertically (PitchSpace.ISO_Y ≈ 1.62): 20m
## across the pitch must take as long as 20m along it, and steering must give
## the same real speed in either direction.
func test_movement_is_true_distance_in_every_direction() -> void:
	var mpp := PitchSpace.metres_per_px()
	var p := _player(Vector2(1100, 600), 150.0)
	p.max_accel = 90.0
	var along := PitchControl.time_to_reach(p.position + Vector2(20.0 / mpp.x, 0), p)
	var across := PitchControl.time_to_reach(p.position + Vector2(0, 20.0 / mpp.y), p)
	assert_near(along, across, 0.01, "20m along (%.2fs) vs across (%.2fs)" % [along, across])
	for dir in [Vector2.RIGHT, Vector2.DOWN]:
		p.velocity = Vector2.ZERO
		for i in 300:
			p.steer_velocity(dir * 150.0, 1.0 / 60.0)
		var ms := Vector2(p.velocity.x * mpp.x, p.velocity.y * mpp.y).length()
		assert_near(ms, 150.0 * mpp.x, 0.05, "top speed %s = %.2f m/s" % [str(dir), ms])
	_free_players()

## Turning like a runner, not a puck: reversing at full speed brakes and
## turns within a few metres instead of sliding on; a slow player pivots.
func test_turning_brakes_then_turns() -> void:
	var p := _player(Vector2(1100, 600), 150.0)
	p.max_accel = 90.0
	var top := 150.0 * Locomotion.SPRINT_MULTIPLIER
	p.velocity = Vector2.RIGHT * top
	var start_x := p.position.x
	var furthest := start_x
	for i in 180:
		p.steer_velocity(Vector2.LEFT * top, 1.0 / 60.0)
		p.position += p.velocity / 60.0
		furthest = maxf(furthest, p.position.x)
	assert_true(p.velocity.x < -0.5 * top, "heading back left at speed (vx %.0f)" % p.velocity.x)
	var overrun_m := (furthest - start_x) * PitchSpace.metres_per_px().x
	assert_true(overrun_m < 6.0, "overran %.1fm before turning (sliding on would be more)" % overrun_m)
	# Slow: turns on the spot.
	p.velocity = Vector2.RIGHT * 10.0
	p.steer_velocity(Vector2.DOWN * top, 1.0 / 60.0)
	assert_true(p.velocity.normalized().dot(Vector2.DOWN) > 0.99, "a slow player pivots at once")
	_free_players()

## A pass arrives with pace and rolls on: a runner who only gets there late
## meets it further on, and a ball played toward a line can run out first.
func test_pass_that_runs_out_before_the_runner_rates_low() -> void:
	var passer := _player(Vector2(1000, 700))
	var runner := _player(Vector2(1200, 820), 60.0)
	var target := Vector2(1200, 1015)  # ~20px inside the bottom detection line
	Tuning.set_from_string("pass_rolling_race=0")
	var old := PassModel.evaluate(passer.position, target, passer, runner, [passer, runner], [])
	Tuning.set_from_string("")
	var rolling := PassModel.evaluate(passer.position, target, passer, runner, [passer, runner], [])
	assert_true(rolling.p_success < old.p_success - 0.2,
		"ball runs out before the runner (rolling %.2f vs waiting-ball %.2f)" % [rolling.p_success, old.p_success])
	# To feet, unchallenged: unchanged.
	var mate := _player(Vector2(1200, 700))
	var feet := PassModel.evaluate(passer.position, mate.position, passer, mate, [passer, mate], [])
	assert_true(feet.p_success > 0.9, "simple pass to feet still safe (got %.2f)" % feet.p_success)
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
