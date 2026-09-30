class_name GoalkeeperBrain
extends RefCounted

## Engine-v2 analytic goalkeeper (docs/match-engine-v2.md Phase 8). Four jobs:
##
##  1. POSITIONING — stand on the line from goal centre to the ball, further
##     off the line the further away the ball is (a sweeper-keeper position when
##     it's in the other half), tight to the line for close-range danger.
##  2. SWEEPING / CLAIMING — come for a loose ball or through ball when the
##     ball predictor says the keeper gets there clearly first, inside the box.
##  3. SHOT STOPPING — BallPredictor gives where and when the shot arrives;
##     the keeper's reaction time, dive speed and reach (from his stats) give
##     how far he can get. A save probability comes from that margin (plus
##     handling vs. shot pace), the outcome is rolled ONCE, then the dive is
##     played out to match: a save reaches the ball (caught or parried wide),
##     a miss falls short with the hands disabled. Deciding first and animating
##     second is standard sports-game practice — it makes goals vs. xG
##     calibratable instead of an accident of collider sizes.
##  4. DISTRIBUTION — the same OnBallEvaluator pass valuation as outfielders.

# ─── Positioning ────────────────────────────────────────────────────────────
## Distance off the goal line (px): tight for close-range danger, further out
## as the ball recedes, a sweeper position when it's deep in the other half.
const DEPTH_CLOSE := 12.0
const DEPTH_MID := 42.0
const DEPTH_SWEEPER := 110.0
const CLOSE_RANGE_PX := 260.0
const MID_RANGE_PX := 900.0
## Lateral limit of the positioning line, beyond each post (px).
const POST_MARGIN := 10.0

# ─── Sweeping / claiming ────────────────────────────────────────────────────
## Come for a loose ball only if clearly first to it (s) and it's in the box.
const SWEEP_MARGIN_S := 0.3
const CLAIM_RADIUS := 22.0
## Hands reach well above an outfielder's (Player.MAX_COLLECT_HEIGHT).
const CLAIM_HEIGHT := 32.0

# ─── Shot stopping ──────────────────────────────────────────────────────────
## A moving ball faster than this, heading into the goal mouth, is a shot.
const SHOT_MIN_SPEED := 150.0
## Save probability = logistic(margin_px / SAVE_SCALE_PX) + SAVE_BIAS, where
## margin = how much further than needed the keeper can get in the time.
## Calibrated in the harness so goals ≈ xG and ~70% of on-target shots are
## saved (see the Phase 8 notes).
const SAVE_SCALE_PX := 18.0
## Goal tuning (user's choice: more goals over strict realism): -0.1 takes
## save share from ~70% to ~60-68%. 0.0 = the calibrated keeper.
const SAVE_BIAS := -0.1
## Fast shots are harder to hold/parry cleanly even when reached. Scaled
## ×0.8 with PlayerStateShooting.SHOT_SPEED_MIN/MAX.
const HANDLING_SPEED_START := 240.0
const HANDLING_SPEED_RANGE := 280.0
const HANDLING_PENALTY := 0.35
## Of saves, how many are caught (vs parried) — slower shots and good hands
## are caught.
const CATCH_BASE := 0.75
## A missed dive stops this far short of the ball's line.
const MISS_GAP := 14.0

# ─── Distribution ───────────────────────────────────────────────────────────
const HOLD_DELAY_MIN := 0.6
const HOLD_DELAY_MAX := 1.6

var player : Player = null
## Telemetry (PassTracer): the latest distribution's predicted success and type.
var last_pass_p := -1.0
var last_pass_kind := ""
var team : TeamBrain = null
var ctx : MatchContext = null
var ball : Ball = null
var opponent_area : Area2D = null

var reflexes := 0.5
var handling := 0.5
var reaction_s := 0.2
var dive_speed := 220.0
var reach := 16.0
var decisions := 0.5

## The shot being dealt with: {"t_seen", "decided", "save", "catch"} or empty.
var _shot := {}
var _hold_since := -1.0
var _hands_shape : CapsuleShape2D = null
var _base_hands_radius := 6.0

func _init(p_player: Player, p_team: TeamBrain, p_ctx: MatchContext, p_opponent_area: Area2D) -> void:
	player = p_player
	team = p_team
	ctx = p_ctx
	ball = p_ctx.ball
	opponent_area = p_opponent_area
	reflexes = (0.55 * player.defense + 0.25 * player.pace + 0.2 * player.physicality) / 100.0
	handling = (0.6 * player.defense + 0.4 * player.physicality) / 100.0
	decisions = MentalAttributes.derive(player).decisions / 100.0
	reaction_s = lerpf(0.30, 0.12, reflexes)
	dive_speed = lerpf(170.0, 300.0, reflexes)
	reach = lerpf(14.0, 22.0, player.physicality / 100.0)
	# The hands shape is a shared sub-resource of player.tscn — give this
	# keeper his own copy before resizing it for dives.
	var col := player.goalie_hands_collider
	if col != null and col.shape is CapsuleShape2D:
		_hands_shape = col.shape.duplicate()
		col.shape = _hands_shape
		_base_hands_radius = _hands_shape.radius

## Called every frame from AIBehavior.process_ai (MOVING and HOLDING_BALL).
## Movement goes through the keeper's acceleration limits like outfielders'
## (dives set their own velocity in PlayerStateDiving).
func process() -> void:
	var prev := player.velocity
	var state_before := player.current_state
	_process_logic()
	if player.current_state == state_before:
		var desired := player.velocity
		player.velocity = prev
		player.steer_velocity(desired, player.get_process_delta_time())

func _process_logic() -> void:
	if player.current_state != null and player.current_state.is_holding_ball():
		_process_holding()
		return
	_hold_since = -1.0
	var shot := _incoming_shot()
	if not shot.is_empty():
		_process_shot(shot)
		return
	_shot = {}
	if _try_claim():
		return
	if _process_sweep():
		return
	var target := _position_target()
	player.velocity = Locomotion.compute_velocity(player, target, ball, opponent_area)

# ─── 1. Positioning ─────────────────────────────────────────────────────────

func _goal_centre() -> Vector2:
	return player.own_goal.get_center_target_position()

func _position_target() -> Vector2:
	var g := _goal_centre()
	var ref := ball.carrier.position if ball.carrier != null else ball.position
	var dist := ref.distance_to(g)
	var depth : float
	if dist < CLOSE_RANGE_PX:
		depth = lerpf(DEPTH_CLOSE, DEPTH_MID, dist / CLOSE_RANGE_PX)
	elif dist < MID_RANGE_PX:
		depth = DEPTH_MID
	else:
		depth = lerpf(DEPTH_MID, DEPTH_SWEEPER, clampf((dist - MID_RANGE_PX) / 600.0, 0.0, 1.0))
	var target := g + g.direction_to(ref) * depth
	var top := player.own_goal.get_top_target_position().y - POST_MARGIN
	var bottom := player.own_goal.get_bottom_target_position().y + POST_MARGIN
	target.y = clampf(target.y, top, bottom)
	return target

# ─── 2. Sweeping and claiming ───────────────────────────────────────────────

static func _in_own_box(p: Vector2, left: bool) -> bool:
	var n := PitchSpace.normalised(p, left)
	return n.x < 0.16 and absf(n.y - 0.5) < 0.3

func _try_claim() -> bool:
	if ball.carrier != null or ball.is_kick_cooldown(player) or ball.restart_locked_for(player):
		return false
	if player.position.distance_to(ball.position) > CLAIM_RADIUS or ball.height > CLAIM_HEIGHT:
		return false
	if not _in_own_box(ball.position, player.is_left_team):
		return false
	player.switch_state(Player.State.HOLDING_BALL)
	return true

func _process_sweep() -> bool:
	if ball.carrier != null or ctx.ball_path == null:
		return false
	var mine := BallPredictor.earliest_intercept(ctx.ball_path, player)
	if mine == INF:
		return false
	var theirs : float = ctx.first_to_ball(not player.is_left_team)["time"]
	if mine + SWEEP_MARGIN_S > theirs:
		return false
	var meet := ctx.ball_path.position_at(mine)
	if not _in_own_box(meet, player.is_left_team):
		return false
	player.velocity = player.position.direction_to(meet) * player.speed * Locomotion.SPRINT_MULTIPLIER \
		if player.position.distance_to(meet) > 4.0 else Vector2.ZERO
	return true

# ─── 3. Shot stopping ───────────────────────────────────────────────────────

## {"t": seconds until the ball crosses the goal line, "cross": crossing point,
##  "path": the predicted path} for a ball heading into our goal mouth, else {}.
func _incoming_shot() -> Dictionary:
	if ball.carrier != null or ball.velocity.length() < SHOT_MIN_SPEED or ctx.ball_path == null:
		return {}
	var left := player.is_left_team
	var path := BallPredictor.for_ball(ball, 2.0)
	var top := player.own_goal.get_top_target_position().y - POST_MARGIN
	var bottom := player.own_goal.get_bottom_target_position().y + POST_MARGIN
	for i in range(1, path.size()):
		if PitchSpace.normalised(path.positions[i], left).x <= 0.0:
			var p := path.positions[i]
			if p.y < top or p.y > bottom:
				return {}
			return {"t": path.times[i], "cross": p, "path": path}
	return {}

func _process_shot(shot: Dictionary) -> void:
	var now := MatchClock.now()
	if _shot.is_empty():
		_shot = {"t_seen": now, "decided": false}
	if _shot["decided"]:
		return
	# Reaction time: the keeper holds his position until he's read the shot.
	if now - float(_shot["t_seen"]) < reaction_s:
		player.velocity = Vector2.ZERO
		return
	_shot["decided"] = true
	var path : BallPredictor.BallPath = shot["path"]
	# Best point to meet the ball: the earliest path point he can reach in time.
	var best := shot["cross"] as Vector2
	var best_margin := -INF
	var best_t := float(shot["t"])
	for i in path.size():
		var t := path.times[i]
		if t <= 0.02 or t > float(shot["t"]):
			continue
		var d := player.position.distance_to(path.positions[i])
		var margin := dive_speed * t + reach - d
		if margin > best_margin:
			best_margin = margin
			best = path.positions[i]
			best_t = t
	var p_save := _save_probability(best_margin, ball.velocity.length())
	var save := MatchRng.randf() < p_save
	GameEvents.keeper_decision.emit(player, p_save, save)
	AIProfile.count("gk_p_save", p_save)
	AIProfile.count("gk_margin_px", best_margin)
	AIProfile.count("gk_time_to_ball_s", best_t)
	AIProfile.count("gk_save_rolled", 1.0 if save else 0.0)
	var dir := player.position.direction_to(best)
	var dist := player.position.distance_to(best)
	var target : Vector2
	if save:
		target = best
		_set_hands(true, reach)
	else:
		target = player.position + dir * maxf(0.0, dist - reach - MISS_GAP)
		_set_hands(false, _base_hands_radius)
	_shot["save"] = save
	_shot["catch"] = MatchRng.randf() < _catch_probability(ball.velocity.length())
	var speed := clampf(dist / maxf(best_t, 0.05), 60.0, dive_speed * 1.2)
	var duration := int((best_t + 0.35) * 1000.0)
	player.switch_state(Player.State.DIVING, PlayerStateData.build().set_dive(target, speed, duration))

func _save_probability(margin_px: float, shot_speed: float) -> float:
	var p := 1.0 / (1.0 + exp(-margin_px / SAVE_SCALE_PX)) + Tuning.f("gk_save_bias", SAVE_BIAS)
	var fast := clampf((shot_speed - HANDLING_SPEED_START) / HANDLING_SPEED_RANGE, 0.0, 1.0)
	p *= 1.0 - fast * HANDLING_PENALTY * (1.0 - handling)
	return clampf(p, 0.02, 0.98)

func _catch_probability(shot_speed: float) -> float:
	var fast := clampf((shot_speed - 150.0) / 400.0, 0.0, 1.0)
	return clampf(CATCH_BASE * (0.5 + handling) * (1.0 - 0.7 * fast), 0.05, 0.95)

## Hands collider on/off and sized to the dive's reach.
func _set_hands(enabled: bool, radius: float) -> void:
	var col := player.goalie_hands_collider
	if col == null:
		return
	col.set_deferred("disabled", not enabled)
	if _hands_shape != null:
		_hands_shape.radius = radius

func on_dive_finished() -> void:
	_set_hands(true, _base_hands_radius)

## Called by BallState.move_and_bounce when the ball hits this keeper's hands.
## Returns true if the keeper caught it (the ball is now his).
func on_ball_contact() -> bool:
	if not _shot.is_empty() and _shot.get("catch", false) and _in_own_box(ball.position, player.is_left_team):
		_shot = {}
		player.call_deferred("switch_state", Player.State.HOLDING_BALL)
		return true
	# Parry: push it away from goal and wide of the post nearest the ball.
	var g := _goal_centre()
	var away := g.direction_to(ball.position)
	var wide := Vector2(0.0, signf(ball.position.y - g.y) if ball.position.y != g.y else 1.0)
	ball.velocity = (away * 0.6 + wide * 0.8).normalized() * ball.velocity.length() * 0.45
	return false

# ─── 4. Distribution ────────────────────────────────────────────────────────

func _process_holding() -> void:
	player.velocity = Vector2.ZERO
	var now := MatchClock.now()
	if _hold_since < 0.0:
		_hold_since = now
		return
	if now - _hold_since < lerpf(HOLD_DELAY_MAX, HOLD_DELAY_MIN, decisions):
		return
	var options := OnBallEvaluator.enumerate(player, ctx, team, true).filter(
		func(o): return o.kind == OnBallEvaluator.Kind.PASS)
	if options.is_empty():
		_hold_since = now  # nobody on — look again shortly
		return
	var best : OnBallEvaluator.Option = options[0]
	for o in options:
		if o.value > best.value:
			best = o
	_hold_since = -1.0
	last_pass_p = best.p_success
	last_pass_kind = "cross" if best.lofted else ("feet" if best.to_feet else "space")
	player.switch_state(Player.State.PASSING,
		PlayerStateData.build().set_pass_target(best.receiver, best.destination, best.to_feet, best.lofted))
