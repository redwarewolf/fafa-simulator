class_name PlayerStatePassing
extends PlayerState

## Below Ball.DISTANCE_HIGH_PASS a pass is a quick, grounded touch — instant,
## same as before. Beyond it the ball has to be lofted, so the kicker gets a
## visible wind-up first instead of releasing it in the same single frame as
## a five-yard tap — the delay scales up to MAX_WINDUP_MS at
## OnBallUtility.PASS_MAX_DISTANCE (the longest pass the scoring will ever pick).
const MAX_WINDUP_MS := 400.0
## On top of the lofted-arc wind-up above: a pass beyond the kicker's own
## power-gated OnBallUtility.effective_pass_range() adds charge time from
## OnBallUtility.charge_ms_for_pass() — same prep_kick loop, just held longer,
## so a weak-legged player visibly has to wind up harder for a ball beyond
## their natural reach instead of firing it identically to a full-power kick.

var _pass_target: Player = null
var _windup_duration_ms := 0.0
var _windup_start_ms := 0
var _winding_up := false

func _enter_tree() -> void:
	# Goal-aware, whole-team scoring — not limited to the movement-facing
	# detection cone, so a player facing sideways/backward under pressure can
	# still find a forward outlet instead of being stuck with whoever's ahead
	# of their current heading. Picked once here (not at release) so the
	# wind-up duration matches the pass actually being wound up for.
	_pass_target = ai_behavior.role_ai.get_best_pass_target()
	player.velocity = Vector2.ZERO

	if player.role == Positions.Role.GK and GoalieAI.DEBUG_LOG_DISTRIBUTION:
		print("[GK %s] PASSING._enter_tree: target=%s @ %s (re-resolved via get_best_pass_target — compare against the DECISION log above; a mismatch here means positions shifted between deciding to pass and actually entering PASSING)" % [
			player.full_name,
			_pass_target.full_name if _pass_target != null else "NONE",
			_pass_target.position if _pass_target != null else Vector2.ZERO
		])

	var distance := 0.0
	var charge_ms := 0.0
	if _pass_target != null:
		distance = player.position.distance_to(_pass_target.position)
		charge_ms = OnBallUtility.charge_ms_for_pass(player, distance)
	var windup_range := OnBallUtility.PASS_MAX_DISTANCE - Ball.DISTANCE_HIGH_PASS
	var t := clampf((distance - Ball.DISTANCE_HIGH_PASS) / windup_range, 0.0, 1.0)
	_windup_duration_ms = t * MAX_WINDUP_MS + charge_ms

	if _windup_duration_ms > 0.0:
		_winding_up = true
		_windup_start_ms = Time.get_ticks_msec()
		player.play_anim("prep_kick")
	else:
		player.play_anim("kick")

## prep_kick loops, and animation_finished isn't a reliable way to time a
## loop's end (see PlayerStatePreppingShot, which uses this same
## _process-based elapsed-time check rather than the animation signal) — an
## earlier version gated the wind-up on on_animation_complete instead, which
## never fired again after the first loop, leaving the player stuck in
## prep_kick forever with the ball never released.
func _process(_delta: float) -> void:
	if _winding_up and Time.get_ticks_msec() - _windup_start_ms >= _windup_duration_ms:
		_winding_up = false
		player.play_anim("kick")

func on_animation_complete() -> void:
	if _winding_up:
		return  # prep_kick finished a loop early — _process promotes us to "kick" when the wind-up is actually done

	if _pass_target != null:
		if DebugDraw.SHOW_PASS_LINES:
			DebugDraw.line(player.position, _pass_target.position, Color.GREEN, 2.0)
			DebugDraw.cross(_pass_target.position, Color.GREEN, 5.0, 2.0)
		# Lead the pass to where the teammate will be, not where they currently
		# are — see Ball.estimate_pass_lead_destination for why this needs to
		# converge rather than just multiply velocity by one flight-time guess.
		var destination := ball.estimate_pass_lead_destination(player.position, _pass_target.position, _pass_target.velocity)
		if player.role == Positions.Role.GK and GoalieAI.DEBUG_LOG_DISTRIBUTION:
			var opponents := player.get_opponents()
			print("[GK %s] PASSING.kick: from=%s target=%s target_pos_now=%s target_vel=%s → led_destination=%s | nearest_opp_to_destination=%.1f" % [
				player.full_name, player.position, _pass_target.full_name, _pass_target.position,
				_pass_target.velocity, destination,
				CandidatePointScorer.nearest_opponent_distance(destination, opponents)
			])
		ball.pass_to(destination)
		if player.role == Positions.Role.GK and GoalieAI.DEBUG_LOG_DISTRIBUTION:
			print("[GK %s] PASSING.kick: ball released — vel=%s speed=%.1f" % [player.full_name, ball.velocity, ball.velocity.length()])
	else:
		# Truly nobody available — keep the ball and dribble
		print("[%s] ⚽ PASS — no target anywhere, keeping ball" % player.full_name)
		# ball.carrier remains set, ball stays in CARRIED — player will resume dribbling

	transition_state(Player.State.MOVING)
