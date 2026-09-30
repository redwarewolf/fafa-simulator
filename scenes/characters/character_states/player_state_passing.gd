class_name PlayerStatePassing
extends PlayerState

## Executes a pass the player's brain chose (PlayerBrain / GoalkeeperBrain set
## the receiver, destination, to-feet/into-space and lofted flags via
## PlayerStateData.set_pass_target).
##
## Below Ball.DISTANCE_HIGH_PASS a pass is a quick, grounded touch — instant.
## Beyond it the ball has to be lofted, so the kicker gets a visible wind-up
## first instead of releasing it in the same single frame as a five-yard tap —
## the delay scales up to MAX_WINDUP_MS at PASS_MAX_DISTANCE.
const MAX_WINDUP_MS := 400.0
## The longest pass anyone plays (OnBallEvaluator.PASS_MAX_PX).
const PASS_MAX_DISTANCE := 880.0

## On top of the lofted-arc wind-up: a pass beyond the kicker's own power-gated
## natural range adds charge time, so a weak-legged player visibly has to wind
## up harder for a ball beyond their natural reach. The weakest passer
## (power 0) reaches this fraction of PASS_MAX_DISTANCE with no charge...
const PASS_MIN_RANGE_FACTOR := 0.5
## ...and pays this many ms per full extra multiple of their natural range.
const CHARGE_MS_PER_EXTRA_RANGE := 1600.0

var _pass_target: Player = null
var _windup_duration_ms := 0.0
var _windup_start_ms := 0
var _winding_up := false

## How far [param p] can pass with no charge at all.
static func effective_pass_range(p: Player) -> float:
	return PASS_MAX_DISTANCE * lerpf(PASS_MIN_RANGE_FACTOR, 1.0, p.power / 100.0)

## 0 within the player's natural range; beyond it, scales with how many
## multiples of that range the target distance needs.
static func charge_ms_for_pass(p: Player, distance: float) -> float:
	var natural_range := effective_pass_range(p)
	if distance <= natural_range:
		return 0.0
	return (distance / natural_range - 1.0) * CHARGE_MS_PER_EXTRA_RANGE

func _enter_tree() -> void:
	player.velocity = Vector2.ZERO
	if not state_data.has_pass_target:
		# Nothing chose a pass — keep the ball.
		transition_state.call_deferred(Player.State.MOVING)
		return
	_pass_target = state_data.pass_receiver
	var distance := player.position.distance_to(state_data.pass_destination)
	var windup_range := PASS_MAX_DISTANCE - Ball.DISTANCE_HIGH_PASS
	var t := clampf((distance - Ball.DISTANCE_HIGH_PASS) / windup_range, 0.0, 1.0)
	_windup_duration_ms = t * MAX_WINDUP_MS + charge_ms_for_pass(player, distance)
	if _windup_duration_ms > 0.0:
		_winding_up = true
		_windup_start_ms = MatchClock.now_ms()
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
	if _winding_up and MatchClock.now_ms() - _windup_start_ms >= _windup_duration_ms:
		_winding_up = false
		player.play_anim("kick")

func on_animation_complete() -> void:
	if _winding_up:
		return  # prep_kick finished a loop early — _process promotes us to "kick" when the wind-up is actually done
	if ball.carrier == player:
		# A pass to feet is re-led from where the receiver is heading now; a
		# pass into space goes exactly where it was aimed.
		var dest := state_data.pass_destination
		if state_data.pass_to_feet and _pass_target != null:
			dest = ball.estimate_pass_lead_destination(player.position, _pass_target.position, _pass_target.velocity, state_data.pass_lofted)
		GameEvents.pass_attempted.emit(player, _pass_target, dest)
		ball.pass_to(dest, state_data.pass_lofted)
	# else: lost the ball during the wind-up — nothing to kick.
	transition_state(Player.State.MOVING)
