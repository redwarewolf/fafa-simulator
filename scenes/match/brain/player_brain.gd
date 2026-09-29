class_name PlayerBrain
extends RefCounted

## The per-player layer of the v2 hierarchy (Phase 6). The TeamBrain hands it
## a Job; this turns that into a target and velocity EVERY frame (targets that
## track a moving subject — a marked runner, the carrier — are recomputed per
## frame, so tracking is smooth), refreshes its own positional choice at
## THINK_OFF_BALL_S, and makes on-ball decisions (OnBallEvaluator) at
## THINK_ON_BALL_S after a first-touch delay.
##
## Brains think at staggered, non-frame-aligned moments (a per-player random
## phase from MatchRng), the video's CPU-budgeting trick — 20 brains don't all
## think on the same frame.
##
## The goalkeeper stays on v1's GoalieAI until Phase 8, so keepers never get a
## PlayerBrain.

const THINK_OFF_BALL_S := 0.2
const THINK_ON_BALL_S := 0.12
## Contain distance (goal-side of the carrier) for a presser told not to engage.
const CONTAIN_DIST := 70.0
## A defender this close to the ball tackles whatever their job.
const REFLEX_TACKLE_PX := 18.0

var player : Player = null
var team : TeamBrain = null
var ctx : MatchContext = null
var mental : MentalAttributes = null
var job : Job = null
var opponent_area : Area2D = null

## The success probability PassModel predicted for this player's latest pass
## (telemetry: PassTracer checks predictions against outcomes).
var last_pass_p := -1.0
## When this player decided on that pass and the pressure band then
## (telemetry: wind-up time, pressure closing in before the kick).
var last_pass_decided_t := -1.0
var last_pass_band := ""
var last_pass_kind := ""

var _target := Vector2.ZERO
var _next_think := 0.0
var _had_ball := false
var _carry_target := Vector2.ZERO
var _position_error := Vector2.ZERO

func _init(p_player: Player, p_team: TeamBrain, p_ctx: MatchContext, p_opponent_area: Area2D) -> void:
	player = p_player
	team = p_team
	ctx = p_ctx
	opponent_area = p_opponent_area
	mental = MentalAttributes.derive(player)
	_target = player.position
	_next_think = MatchClock.now() + MatchRng.randf() * THINK_OFF_BALL_S
	_roll_position_error()

## Called every frame while the player is in a controllable state (MOVING).
## The logic below sets the DESIRED velocity; it's then reached within the
## player's acceleration/braking limits (Player.steer_velocity), unless the
## player switched state (pass/shot/tackle set their own velocity).
func process() -> void:
	var prev := player.velocity
	var state_before := player.current_state
	_process_logic()
	if player.current_state == state_before:
		var desired := player.velocity
		player.velocity = prev
		player.steer_velocity(desired, player.get_process_delta_time())

func _process_logic() -> void:
	if not SpecialPlayerTypes.movable(player.special_type):
		return
	var ball := ctx.ball
	var now := MatchClock.now()
	if player.is_restart_taker:
		# Set piece: hold behind the ball while both sides organise, then
		# step onto it (the ball's restart lock releases at the same moment).
		if ctx.restart_active() and now < ctx.world.restart_ready_at:
			player.velocity = Vector2.ZERO
			return
		player.velocity = player.position.direction_to(ball.position) * _sprint_speed()
		return
	if ball.carrier == player:
		_process_on_ball(now)
		return
	_had_ball = false
	if now >= _next_think:
		_next_think = now + THINK_OFF_BALL_S
		var t0 := AIProfile.begin()
		_think_off_ball()
		AIProfile.end("think_off_ball", t0)
	var t1 := AIProfile.begin()
	_move_off_ball()
	_maybe_tackle()
	AIProfile.end("move_off_ball", t1)

# ─── On the ball ────────────────────────────────────────────────────────────

func _process_on_ball(now: float) -> void:
	if not _had_ball:
		_had_ball = true
		_carry_target = player.position
		_next_think = now + mental.first_touch_delay()
	if now >= _next_think:
		_next_think = now + THINK_ON_BALL_S
		if _act_on_ball():
			return  # switched state (pass/shot)
	player.velocity = Locomotion.compute_velocity(player, _carry_target, ctx.ball, opponent_area)

## Returns true when the decision switched the player's state.
func _act_on_ball() -> bool:
	var restart := player.restart_pass_pending
	player.restart_pass_pending = false
	var t0 := AIProfile.begin()
	var o := OnBallEvaluator.decide(player, ctx, team, mental, restart)
	AIProfile.end("on_ball_decide", t0)
	match o.kind:
		OnBallEvaluator.Kind.SHOOT:
			var dir := player.position.direction_to(_shot_aim())
			var err := MatchRng.randfn(0.0, deg_to_rad(_shot_error_deg()))
			player.face_towards_target_goal()
			player.switch_state(Player.State.SHOOTING,
				PlayerStateData.build().set_shot_power(player.power).set_shot_direction(dir.rotated(err)))
			return true
		OnBallEvaluator.Kind.PASS:
			last_pass_p = o.p_success
			last_pass_decided_t = MatchClock.now()
			last_pass_band = OnBallEvaluator.pressure_band(player)
			last_pass_kind = "cross" if o.lofted else ("feet" if o.to_feet else "space")
			player.switch_state(Player.State.PASSING,
				PlayerStateData.build().set_pass_target(o.receiver, o.destination, o.to_feet, o.lofted))
			return true
		OnBallEvaluator.Kind.CARRY:
			_carry_target = o.destination
		_:
			_carry_target = _shield_point()
	return false

## Shot placement. Real shooters go for the corners — just inside a post, where
## a keeper can't reach — and miss the frame roughly half the time doing so
## (~33% of real shots are on target once blocks are included). The first cut
## aimed at the goal's inner shot targets with 1.5-7° of error, which put
## 60-66% of shots on target and goals at ~1.5x xG in the harness.
## Error: POWER-scaled base, plus extra under pressure.
const AIM_INSIDE_POST_PX := 5.0
const SHOT_ERROR_BEST_DEG := 3.0
const SHOT_ERROR_WORST_DEG := 8.0
const SHOT_ERROR_PRESSURE_DEG := 3.0
const SHOT_PRESSURE_PX := 35.0

func _shot_error_deg() -> float:
	var e := lerpf(SHOT_ERROR_WORST_DEG, SHOT_ERROR_BEST_DEG, player.power / 100.0)
	for o in player.get_opponents():
		if o.position.distance_to(player.position) < SHOT_PRESSURE_PX:
			e += SHOT_ERROR_PRESSURE_DEG
			break
	return e * Tuning.f("shot_error_scale", 1.0)

## Aim just inside whichever post is farther (angularly) from the keeper.
func _shot_aim() -> Vector2:
	var goal := player.target_goal
	var mouth := MatchWorld._goal_mouth(goal)
	var cx := goal.get_center_target_position().x
	var posts := [Vector2(cx, mouth.x + AIM_INSIDE_POST_PX), Vector2(cx, mouth.y - AIM_INSIDE_POST_PX)]
	var keeper : Player = null
	for o in player.get_opponents():
		if o.role == Positions.Role.GK:
			keeper = o
	if keeper == null:
		return goal.get_center_target_position()
	var best : Vector2 = posts[0]
	var best_a := -1.0
	for t: Vector2 in posts:
		var a := absf((t - player.position).angle_to(keeper.position - player.position))
		if a > best_a:
			best_a = a
			best = t
	return best

## Step away from the nearest opponent to protect the ball.
func _shield_point() -> Vector2:
	var nearest : Player = null
	var nd := INF
	for o in player.get_opponents():
		var d := o.position.distance_squared_to(player.position)
		if d < nd:
			nd = d
			nearest = o
	if nearest == null:
		return player.position
	return player.position + nearest.position.direction_to(player.position) * 25.0

# ─── Off the ball ───────────────────────────────────────────────────────────

func _think_off_ball() -> void:
	if job == null:
		_target = player.anchor_position
		return
	match job.kind:
		Job.Kind.ZONE, Job.Kind.REST_DEFENCE, Job.Kind.SUPPORT, Job.Kind.RUN:
			if team.tactical.in_possession() or team.tactical.owner == TacticalBrain.US:
				_target = OffBallPositioner.best_point(player, job, ctx, mental, _target)
			else:
				_target = job.point + _position_error
		Job.Kind.RECEIVE:
			var t := BallPredictor.earliest_intercept(ctx.ball_path, player, Tuning.f("receive_slack", RECEIVE_SLACK_S)) if ctx.ball_path != null else INF
			_target = TeamBrain.clamp_to_pitch(ctx.ball_path.position_at(t)) if t != INF else job.point
		_:
			_target = job.point
	if MatchRng.randf() < 0.05:
		_roll_position_error()
	_respect_restart_distance()

## Opponents of the side taking a set piece must stay the Law's distance from
## the ball (Restart.retreat_distance) — push any target inside it back out,
## toward our own goal.
func _respect_restart_distance() -> void:
	if not ctx.restart_active() or ctx.world.restart_team_left == player.is_left_team:
		return
	var spot := ctx.world.restart_spot
	var radius := Restart.retreat_distance(ctx.world.restart_kind)
	if _target.distance_to(spot) >= radius:
		return
	var away := spot.direction_to(_target)
	if away == Vector2.ZERO:
		away = spot.direction_to(player.own_goal.get_center_target_position())
	_target = spot + away * radius

func _roll_position_error() -> void:
	var s := mental.position_noise_px()
	_position_error = Vector2(MatchRng.randfn(0.0, s), MatchRng.randfn(0.0, s))

func _move_off_ball() -> void:
	player.mark_target = job.subject if job != null and job.kind == Job.Kind.MARK else null
	if job == null:
		player.velocity = Locomotion.compute_velocity(player, _target, ctx.ball, opponent_area)
		return
	var carrier := ctx.ball.carrier
	var own_goal := player.own_goal.get_center_target_position()
	match job.kind:
		Job.Kind.PRESS:
			if carrier != null and carrier.is_left_team != player.is_left_team:
				if job.engage:
					var close := player.position.distance_to(carrier.position) < RoleAI.TACKLE_DISTANCE * 2.0
					if close and not _should_commit_tackle(carrier):
						# Jockey: goal-side, matching the carrier's run, waiting
						# for better odds instead of diving in.
						_target = carrier.position + carrier.velocity * 0.2 \
							+ carrier.position.direction_to(own_goal) * JOCKEY_DIST
						player.velocity = Locomotion.compute_velocity(player, _target, ctx.ball, opponent_area)
						return
					var lead := clampf(player.position.distance_to(carrier.position) / maxf(player.speed, 1.0), 0.0, 1.0)
					var aim := carrier.position + carrier.velocity * lead
					player.velocity = player.position.direction_to(aim) * _sprint_speed()
					return
				_target = carrier.position + carrier.position.direction_to(own_goal) * CONTAIN_DIST
			elif carrier == null:
				# Pressing on the pass (TeamBrain._press_on_pass): sprint to
				# the goal-side spot by the reception point.
				_target = job.point
				player.velocity = player.position.direction_to(_target) * _sprint_speed() \
					if player.position.distance_to(_target) > 6.0 else Vector2.ZERO
				return
		Job.Kind.COVER:
			if carrier != null:
				_target = carrier.position + carrier.position.direction_to(own_goal) * TeamBrain.COVER_DIST
		Job.Kind.MARK:
			var m := job.subject
			if m != null:
				var lead_pos := m.position + m.velocity * 0.25
				var dist := job.point.distance_to(m.position + m.velocity * 0.25)
				_target = lead_pos + lead_pos.direction_to(own_goal) * clampf(dist, TeamBrain.TIGHT_MARK_PX, TeamBrain.LOOSE_MARK_PX)
		Job.Kind.LANE_CUT:
			if carrier != null and job.subject != null:
				_target = carrier.position.lerp(job.subject.position, 0.42)
		Job.Kind.CHASE, Job.Kind.INTERCEPT, Job.Kind.RECEIVE:
			if _attack_ball():
				return
			var dt := player.position.distance_to(_target)
			player.velocity = player.position.direction_to(_target) * minf(_sprint_speed(), _arrival_cap(dt - 6.0)) \
				if dt > 6.0 else Vector2.ZERO
			return
	player.velocity = Locomotion.compute_velocity(player, _target, ctx.ball, opponent_area)

## Final approach to a loose ball: within this distance, stop running to the
## predicted meeting point and go at the ball itself. The pickup reach is only
## ~8-13px (ball.tscn PlayerDetectionArea vs the body capsule), and PassTracer
## showed "safe" passes (pred >= 0.9) failing ~10% of the time with the
## receiver passing 11-17px from the ball — parked at a meeting point a
## fraction off-line or late, or standing next to a stopped ball — until an
## opponent collected it seconds later.
const ATTACK_BALL_PX := 45.0
## Lead on the ball's motion during the final approach (s, max).
const ATTACK_BALL_LEAD_S := 0.25

func _attack_ball() -> bool:
	if not Tuning.b("attack_ball", true):
		return false
	var b := ctx.ball
	if b.carrier != null or b.is_kick_cooldown(player) or b.restart_locked_for(player):
		return false
	var d := player.position.distance_to(b.position)
	if d > ATTACK_BALL_PX:
		return false
	var sprint := _sprint_speed()
	var lead := clampf(d / maxf(sprint, 1.0), 0.0, ATTACK_BALL_LEAD_S)
	# The pickup circle sits 2px above the body capsule's centre line.
	var aim := b.position + b.velocity * lead + Vector2(0.0, -2.0)
	# Match the ball's motion and close the gap at a speed we can still stop
	# from — sprinting straight at it overran it by a stride.
	var v := b.velocity + player.position.direction_to(aim) * _arrival_cap(player.position.distance_to(aim))
	player.velocity = v.limit_length(sprint)
	return true

## Receivers settle before the ball arrives instead of arriving at full tilt:
## the RECEIVE meeting point is the earliest one reachable this many seconds
## before the ball (BallPredictor.earliest_intercept slack). Knob `receive_slack`.
const RECEIVE_SLACK_S := 0.5

## Highest speed from which the player can still stop within [param dist] px
## (v2 braking); unlimited for v1-style movement.
func _arrival_cap(dist: float) -> float:
	if player.max_accel <= 0.0 or not Tuning.b("arrival_braking", true):
		return INF
	return sqrt(2.0 * player.max_accel * Player.BRAKE_FACTOR * 0.8 * maxf(dist, 0.0)) + 20.0

func _sprint_speed() -> float:
	return player.speed * Locomotion.SPRINT_MULTIPLIER * player.get_stamina_factor()

## Minimum duel odds (Player.tackle_win_chance) to commit to a tackle, by
## where the ball is. A failed tackle leaves the defender recovering on the
## floor, so near our own goal it pays to jockey and wait for better odds —
## unless the carrier is about to shoot. The first cut tackled whenever in
## range: 16.7 tackles per 180s at 53% success against v1, whose dribblers
## then walked through the gaps (shots from 10.6m at 0.23 xG).
const TACKLE_ODDS_OWN_THIRD := 0.58
const TACKLE_ODDS_ELSEWHERE := 0.42
const TACKLE_ODDS_MUST_STOP := 0.3
## Carrier xG above which we're in "stop the shot at all costs" territory.
const MUST_STOP_XG := 0.06
## Jockeying: stay this far goal-side of the carrier, matching their run.
const JOCKEY_DIST := 24.0

func _should_commit_tackle(carrier: Player) -> bool:
	var p_win := Player.tackle_win_chance(player.defense, carrier.dribbling)
	var own_depth := PitchSpace.normalised(carrier.position, player.is_left_team).x
	var threshold := TACKLE_ODDS_OWN_THIRD if own_depth < 1.0 / 3.0 else TACKLE_ODDS_ELSEWHERE
	# Geometry-only xG: the contextual ShotModel.xg counts this very defender
	# as a blocker, so a jockeying defender suppressed his own danger signal
	# and kept backing off to the penalty spot (v1 carried 13m before
	# shooting, 0.21 xG/shot against v2).
	var danger := ShotModel.xg_for_goal(carrier.position, carrier.target_goal) \
		if Tuning.b("tackle_must_stop_geo", true) \
		else ShotModel.xg(carrier.position, carrier.target_goal, player.get_teammates())
	if danger > MUST_STOP_XG:
		threshold = TACKLE_ODDS_MUST_STOP
	# Aggressive players commit on slightly worse odds, cautious ones wait.
	threshold -= (mental.tackle_eagerness() - 0.85) * 0.2
	# DISABLED by default: a 64-match A/B against v1 showed committing on
	# every chance in range concedes LESS (v1 xG 0.117 vs 0.19-0.27 with
	# judgement on; v2-v1 xG diff +0.027±0.034, best of 4 variants). Kept
	# behind the `tackle_judgement` knob for re-testing after Phase 7's
	# tackle/movement rework.
	if not Tuning.b("tackle_judgement", false):
		return true
	return p_win >= threshold

func _maybe_tackle() -> void:
	var carrier := ctx.ball.carrier
	if carrier == null or carrier.is_left_team == player.is_left_team:
		return
	if carrier.current_state != null and carrier.current_state.is_holding_ball():
		return
	var d := player.position.distance_to(ctx.ball.position)
	if d >= RoleAI.TACKLE_DISTANCE:
		return
	var committed := job != null and (
		(job.kind == Job.Kind.PRESS and job.engage) or job.kind == Job.Kind.COVER
		or (job.kind == Job.Kind.MARK and job.subject == carrier))
	if (committed or d < REFLEX_TACKLE_PX) and _should_commit_tackle(carrier):
		# The slide carries the tackler's current velocity — point it at the ball.
		player.velocity = player.position.direction_to(ctx.ball.position) * maxf(player.velocity.length(), player.speed)
		player.switch_state(Player.State.TACKLING)
