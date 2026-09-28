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
func process() -> void:
	if not SpecialPlayerTypes.movable(player.special_type):
		return
	var ball := ctx.ball
	var now := MatchClock.now()
	if player.is_restart_taker:
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
			var err := MatchRng.randfn(0.0, deg_to_rad(lerpf(7.0, 1.5, player.power / 100.0)))
			player.face_towards_target_goal()
			player.switch_state(Player.State.SHOOTING,
				PlayerStateData.build().set_shot_power(player.power).set_shot_direction(dir.rotated(err)))
			return true
		OnBallEvaluator.Kind.PASS:
			player.switch_state(Player.State.PASSING,
				PlayerStateData.build().set_pass_target(o.receiver, o.destination, o.to_feet))
			return true
		OnBallEvaluator.Kind.CARRY:
			_carry_target = o.destination
		_:
			_carry_target = _shield_point()
	return false

## Aim at whichever shot target (top/middle/bottom of the goal) is farthest,
## angularly, from the keeper.
func _shot_aim() -> Vector2:
	var goal := player.target_goal
	var keeper : Player = null
	for o in player.get_opponents():
		if o.role == Positions.Role.GK:
			keeper = o
	var targets := [goal.get_top_target_position(), goal.get_center_target_position(), goal.get_bottom_target_position()]
	if keeper == null:
		return targets[1]
	var best : Vector2 = targets[1]
	var best_a := -1.0
	for t: Vector2 in targets:
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
			var t := BallPredictor.earliest_intercept(ctx.ball_path, player) if ctx.ball_path != null else INF
			_target = TeamBrain.clamp_to_pitch(ctx.ball_path.position_at(t)) if t != INF else job.point
		_:
			_target = job.point
	if MatchRng.randf() < 0.05:
		_roll_position_error()

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
					var lead := clampf(player.position.distance_to(carrier.position) / maxf(player.speed, 1.0), 0.0, 1.0)
					var aim := carrier.position + carrier.velocity * lead
					player.velocity = player.position.direction_to(aim) * _sprint_speed()
					return
				_target = carrier.position + carrier.position.direction_to(own_goal) * CONTAIN_DIST
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
			player.velocity = player.position.direction_to(_target) * _sprint_speed() \
				if player.position.distance_to(_target) > 6.0 else Vector2.ZERO
			return
	player.velocity = Locomotion.compute_velocity(player, _target, ctx.ball, opponent_area)

func _sprint_speed() -> float:
	return player.speed * Locomotion.SPRINT_MULTIPLIER * player.get_stamina_factor()

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
	if committed or d < REFLEX_TACKLE_PX:
		# The slide carries the tackler's current velocity — point it at the ball.
		player.velocity = player.position.direction_to(ctx.ball.position) * maxf(player.velocity.length(), player.speed)
		player.switch_state(Player.State.TACKLING)
