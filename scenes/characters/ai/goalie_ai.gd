class_name GoalieAI
extends RoleAI

## The keeper's hold/catch/dive timers are a legitimate commitment state
## machine (discrete "am I holding, waiting, reacting to a shot" states), not
## a continuous per-frame choice — kept structurally as-is from the old
## GoalieBehavior. Target selection (_find_long_kick_target / get_best_pass_target)
## is rebased onto OnBallUtility's pass scoring (lane + receiver-openness
## penalties) plus a hard CONTESTED_RADIUS reject (see there), so the
## multi-retry ladder below rarely runs out — and when it does, it hoofs the
## ball clear (_clear_ball) instead of forcing a pass into a covered teammate.

const PROXIMITY_CONCERN := 30.0
const CATCH_DISTANCE := 22.0
const SCOOP_DISTANCE := 80.0
const MAX_CATCHABLE_SPEED := 200.0
const HOLD_DECISION_DELAY := 2500
const QUICK_RELEASE_DELAY := 500
const CATCH_COOLDOWN := 1500
const INTERCEPT_DISTANCE := 80.0
const LONG_KICK_MIN_DISTANCE := 150.0
const MAX_HOLD_RETRIES := 3
const REACTION_DELAY := 150
const MAX_ANGLE_CUT := 40.0
const ANGLE_CUT_RANGE := 900.0
## An opponent standing this close to a candidate landing spot makes it a bad
## spot to put the ball, full stop — tighter than OnBallUtility's own
## RECEIVER_OPENNESS_RADIUS (80px, a soft score penalty scaled down by passer
## skill), because a turnover this close to our own goal is far more costly
## than one at midfield, so it's worth a hard reject here rather than "still
## technically the highest-scoring option available."
const CONTESTED_RADIUS := 45.0
const CLEAR_MIN_DISTANCE := 500.0
const CLEAR_MAX_DISTANCE := 900.0
const CLEAR_ANGLE_JITTER_DEG := 35.0

## Verbose print() trace of every distribution decision — full player/ball
## snapshot, every candidate considered and why it was accepted/rejected, and
## the final choice. Was left hardcoded true since before this AI overhaul
## (see docs/ai-overhaul.md Phase 6 cleanup) — flip back to true locally
## when diagnosing a specific distribution complaint.
const DEBUG_LOG_DISTRIBUTION := false

var _hold_start_time := 0
var _hold_has_quick_outlet := false
var _catch_cooldown_end := 0
var _hold_retry_count := 0
var _dive_reaction_start := 0  # 0 = no shot tracked; >0 = timestamp shot was first detected

func draw_debug() -> void:
	if not DebugDraw.SHOW_ROLE_RANGES:
		return
	DebugDraw.circle(player.position, CATCH_DISTANCE, Color(1, 1, 0))
	DebugDraw.circle(player.position, INTERCEPT_DISTANCE, Color(1, 0.5, 0))

func get_target_position() -> Vector2:
	# Stay still while holding — ball.position follows us, tracking it causes oscillation.
	if player.current_state != null and player.current_state.is_holding_ball():
		return player.position

	var top := own_goal.get_top_target_position()
	var bottom := own_goal.get_bottom_target_position()

	if ball.carrier == null and ball.is_headed_for_scoring_area(own_goal):
		if player.position.distance_to(ball.position) < INTERCEPT_DISTANCE:
			return ball.position

	if ball.carrier == null and Time.get_ticks_msec() > _catch_cooldown_end:
		if player.position.distance_to(ball.position) < SCOOP_DISTANCE and ball.velocity.length() < MAX_CATCHABLE_SPEED:
			return ball.position

	# Angle-cut positioning: step toward the ball/carrier to narrow the
	# shooting cone. Far away, fall back to simple goal-line Y-tracking.
	var goal_center := (top + bottom) * 0.5
	var reference := ball.carrier.position if ball.carrier != null else ball.position
	var dist_to_goal := reference.distance_to(goal_center)

	if dist_to_goal < ANGLE_CUT_RANGE:
		var dir_to_ball := goal_center.direction_to(reference)
		var step := clampf(MAX_ANGLE_CUT * (1.0 - dist_to_goal / ANGLE_CUT_RANGE), 0.0, MAX_ANGLE_CUT)
		var optimal := goal_center + dir_to_ball * step
		optimal.y = clampf(optimal.y, top.y, bottom.y)
		optimal.x = clampf(optimal.x, player.spawn_position.x - MAX_ANGLE_CUT, player.spawn_position.x + MAX_ANGLE_CUT)
		return optimal
	else:
		var target_y := clampf(reference.y, top.y, bottom.y)
		return Vector2(player.spawn_position.x, target_y)

func make_decisions() -> void:
	if player.current_state != null and player.current_state.is_holding_ball():
		_make_holding_decisions()
		_dive_reaction_start = 0
		return

	if ball.carrier == null and Time.get_ticks_msec() > _catch_cooldown_end:
		var dist := player.position.distance_to(ball.position)
		if dist < CATCH_DISTANCE and ball.velocity.length() < MAX_CATCHABLE_SPEED:
			player.switch_state(Player.State.HOLDING_BALL)
			_dive_reaction_start = 0
			return

	# Shot on target: raycast confirms the ball is aimed at the goal mouth.
	# Read for REACTION_DELAY ms before committing to a dive, to look human.
	var is_shot_on_target := ball.carrier == null and ball.is_headed_for_scoring_area(own_goal)
	if is_shot_on_target:
		if player.position.distance_to(ball.position) < INTERCEPT_DISTANCE:
			_dive_reaction_start = 0  # close enough to run — cancel any pending dive
		else:
			if _dive_reaction_start == 0:
				_dive_reaction_start = Time.get_ticks_msec()
			elif Time.get_ticks_msec() - _dive_reaction_start >= REACTION_DELAY:
				_dive_reaction_start = 0
				player.switch_state(Player.State.DIVING)
	else:
		_dive_reaction_start = 0

func _make_holding_decisions() -> void:
	# Start the decision timer on first tick. A clear long-kick outlet
	# already sitting there means there's no reason to make the keeper stand
	# still for the full cautious delay — release quickly instead.
	if _hold_start_time == 0:
		_hold_start_time = Time.get_ticks_msec()
		_hold_has_quick_outlet = _find_long_kick_target() != null
		return

	var decision_delay := QUICK_RELEASE_DELAY if _hold_has_quick_outlet else HOLD_DECISION_DELAY
	if Time.get_ticks_msec() - _hold_start_time < decision_delay:
		return

	_hold_start_time = 0  # Reset — either we release, or we restart the wait

	if DEBUG_LOG_DISTRIBUTION:
		_log_snapshot("_make_holding_decisions retry=%d" % _hold_retry_count)

	var long_target := _find_long_kick_target()
	if long_target != null:
		if DebugDraw.SHOW_GK_DISTRIBUTION:
			DebugDraw.line(player.position, long_target.position, Color.YELLOW, 2.0)
			DebugDraw.cross(long_target.position, Color.YELLOW, 5.0, 2.0)
		if DEBUG_LOG_DISTRIBUTION:
			print("[GK %s] DECISION: LONG KICK → %s at %s" % [player.full_name, long_target.full_name, long_target.position])
		_release_long_kick(long_target.position)
		return

	# Must match what PlayerStatePassing will actually kick to (it calls this
	# same get_best_pass_target()) — using get_closest_teammate_in_view() here
	# instead let the keeper face/telegraph one player while the ball was
	# kicked to whatever OnBallUtility separately picked, i.e. a pass to
	# "no one in particular" that got stolen instantly.
	var short_target := get_best_pass_target()
	if short_target != null:
		if DebugDraw.SHOW_GK_DISTRIBUTION:
			DebugDraw.line(player.position, short_target.position, Color.CYAN, 2.0)
			DebugDraw.cross(short_target.position, Color.CYAN, 5.0, 2.0)
		if DEBUG_LOG_DISTRIBUTION:
			var lead := ball.estimate_pass_lead_destination(player.position, short_target.position, short_target.velocity)
			print("[GK %s] DECISION: SHORT PASS → %s | receiver_now=%s receiver_vel=%s led_landing≈%s (this is what PlayerStatePassing will actually kick toward)" % [
				player.full_name, short_target.full_name, short_target.position, short_target.velocity, lead
			])
		_face_toward(short_target.position)
		_catch_cooldown_end = Time.get_ticks_msec() + CATCH_COOLDOWN
		_hold_retry_count = 0
		player.switch_state(Player.State.PASSING)
		return

	_hold_retry_count += 1
	if DEBUG_LOG_DISTRIBUTION:
		print("[GK %s] DECISION: no viable target this pass (retry %d/%d)" % [player.full_name, _hold_retry_count, MAX_HOLD_RETRIES])
	if _hold_retry_count < MAX_HOLD_RETRIES:
		return  # restart the countdown — don't release yet

	# All retries exhausted and every teammate we can see is marked tight
	# enough to reject: stop looking for a placed option and just hoof it
	# clear instead of forcing a pass into a covered teammate.
	_hold_retry_count = 0
	_clear_ball()

func _release_long_kick(destination: Vector2) -> void:
	_face_toward(destination)
	_catch_cooldown_end = Time.get_ticks_msec() + CATCH_COOLDOWN
	ball.long_kick(destination)
	player.switch_state(Player.State.MOVING)

## No specific receiver — a hurried clearance downfield to relieve pressure,
## not a placed pass. Randomized direction/distance (rather than always the
## same "aim at target_goal center" point) is what makes this read as an
## imprecise hoof instead of just another long_kick with no target.
func _clear_ball() -> void:
	var forward := player.position.direction_to(target_goal.get_center_target_position())
	var aim := forward.rotated(deg_to_rad(randf_range(-CLEAR_ANGLE_JITTER_DEG, CLEAR_ANGLE_JITTER_DEG)))
	var destination := player.position + aim * randf_range(CLEAR_MIN_DISTANCE, CLEAR_MAX_DISTANCE)
	if DebugDraw.SHOW_GK_DISTRIBUTION:
		DebugDraw.line(player.position, destination, Color.RED, 2.0)
		DebugDraw.cross(destination, Color.RED, 5.0, 2.0)
	if DEBUG_LOG_DISTRIBUTION:
		print("[GK %s] DECISION: CLEAR (no target) → %s" % [player.full_name, destination])
	_release_long_kick(destination)

func _find_long_kick_target() -> Player:
	var candidates: Array[Player] = []
	for t in player.get_teammates():
		if t != player and t.role != Positions.Role.GK and player.position.distance_to(t.position) >= LONG_KICK_MIN_DISTANCE:
			candidates.append(t)
	var picked := OnBallUtility.find_best_pass_target(player, candidates, player.get_opponents(), target_goal)
	if DEBUG_LOG_DISTRIBUTION:
		_log_candidates("long-kick", candidates, picked)
	return _reject_if_contested(picked, "long-kick")

## Override of RoleAI.get_best_pass_target() — called both by
## _make_holding_decisions() below and by PlayerStatePassing when the pass
## actually fires, so a target rejected here never gets picked for one call
## and kicked to on the other.
func get_best_pass_target() -> Player:
	var candidates: Array[Player] = []
	for t in player.get_teammates():
		if t != player:
			candidates.append(t)
	var picked := OnBallUtility.find_best_pass_target(player, candidates, player.get_opponents(), target_goal)
	if DEBUG_LOG_DISTRIBUTION:
		_log_candidates("short-pass", candidates, picked)
	return _reject_if_contested(picked, "short-pass")

## An opponent sitting right on top of the landing spot means this isn't a
## real outlet, no matter how it scored against the alternatives.
func _reject_if_contested(target: Player, context: String = "") -> Player:
	if target == null:
		return null
	var nearest := CandidatePointScorer.nearest_opponent_distance(target.position, player.get_opponents())
	if nearest < CONTESTED_RADIUS:
		if DEBUG_LOG_DISTRIBUTION:
			print("[GK %s] [%s] REJECTED %s — nearest opponent %.1fpx < CONTESTED_RADIUS %.1fpx (target's current pos=%s)" % [
				player.full_name, context, target.full_name, nearest, CONTESTED_RADIUS, target.position
			])
		return null
	return target

func _face_toward(destination: Vector2) -> void:
	player.heading = Vector2.LEFT if destination.x < player.position.x else Vector2.RIGHT

## Dumps every candidate OnBallUtility.find_best_pass_target() considered for
## this search, with its raw pass_score and how far the nearest opponent sits
## from that candidate's CURRENT position (the contested check runs on the
## same number, in _reject_if_contested).
func _log_candidates(context: String, candidates: Array[Player], picked: Player) -> void:
	print("[GK %s] [%s] %d candidate(s):" % [player.full_name, context, candidates.size()])
	if candidates.is_empty():
		return
	var opponents := player.get_opponents()
	for c in candidates:
		var score := OnBallUtility.pass_score(player, c, opponents, target_goal)
		var nearest_opp := CandidatePointScorer.nearest_opponent_distance(c.position, opponents)
		var dist := player.position.distance_to(c.position)
		print("    %-16s pos=%-24s dist_from_gk=%6.1f score=%7.1f nearest_opp=%6.1f%s" % [
			c.full_name, c.position, dist, score, nearest_opp, "  <== BEST" if c == picked else ""
		])

## Full player/ball snapshot — coordinates, velocities, everything needed to
## reconstruct what the field looked like at the moment a distribution
## decision was made.
func _log_snapshot(context: String) -> void:
	print("──── GK %s DISTRIBUTION SNAPSHOT [%s] ────" % [player.full_name, context])
	print("  ball: pos=%s vel=%s speed=%.1f height=%.1f carrier=%s" % [
		ball.position, ball.velocity, ball.velocity.length(), ball.height,
		ball.carrier.full_name if ball.carrier != null else "none"
	])
	print("  GK:   pos=%s heading=%s" % [player.position, player.heading])
	var opponents := player.get_opponents()
	print("  Teammates:")
	for t in player.get_teammates():
		if t == player:
			continue
		print("    %-16s role=%-4s pos=%-24s vel=%-20s dist_to_gk=%6.1f nearest_opp=%6.1f" % [
			t.full_name, Positions.label(t.role), t.position, t.velocity,
			player.position.distance_to(t.position),
			CandidatePointScorer.nearest_opponent_distance(t.position, opponents)
		])
	print("  Opponents:")
	for o in opponents:
		print("    %-16s role=%-4s pos=%-24s vel=%-20s dist_to_gk=%6.1f dist_to_ball=%6.1f" % [
			o.full_name, Positions.label(o.role), o.position, o.velocity,
			player.position.distance_to(o.position), ball.position.distance_to(o.position)
		])
