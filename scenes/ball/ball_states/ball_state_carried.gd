class_name BallStateCarried
extends BallState

const DRIBBLE_FREQUENCY := 10.0
const DRIBBLE_INTENSITY := 3.0
const OFFSET_FROM_PLAYER := Vector2(10, 4)

# ─── Touch dribbling (engine v2, Tuning knob `touch_dribble`) ────────────────
# A running carrier doesn't have the ball glued to his boot: every touch knocks
# it ahead and he runs onto it. While it's out of his reach a defender close
# enough can poke it away without a tackle, a fast touch under pressure can
# run away from him altogether, and a slow carrier with a defender near keeps
# his body between them (shielding). Before this a carrier could only lose the
# ball to a tackle — ~1% of turnovers (docs/match-engine-v2.md, Phase 7).

## Seconds between touches.
const TOUCH_PERIOD := 0.65
## Furthest the ball runs ahead per touch = carrier speed x this many seconds,
## from a poor (0 DRI) to a great (100 DRI) dribbler.
const TOUCH_AHEAD_S_POOR := 0.32
const TOUCH_AHEAD_S_GREAT := 0.14
## Beyond this separation (px) the ball is out of the carrier's reach.
const EXPOSED_PX := 14.0
## A defender within this distance of an exposed ball can poke at it
## (once per touch).
const POKE_REACH_PX := 16.0
## Speed of the poked ball (px/s).
const POKE_SPEED_MIN := 80.0
const POKE_SPEED_MAX := 170.0
## Per-touch chance that a full-speed touch runs away (a poor dribbler, no
## pressure), and the multiplier when a defender is within PRESSURE_PX.
const LOOSE_TOUCH_BASE := 0.03
const LOOSE_TOUCH_PRESSURE := 2.5
const PRESSURE_PX := 60.0
## Extra pace (px/s) the ball has over the carrier on a loose touch.
const LOOSE_TOUCH_EXTRA_MIN := 80.0
const LOOSE_TOUCH_EXTRA_MAX := 150.0
## Below this fraction of top speed the carrier keeps it close and shields.
const SHIELD_SPEED_FRAC := 0.25
const SHIELD_OFFSET_PX := 9.0

var dribble_time := 0.0
var _touch_phase := 0.0
var _touch_sep := 0.0
var _poked_this_touch := {}
var _touch_dir := Vector2.RIGHT

func _enter_tree() -> void:
	assert(carrier != null)

func _touch_dribbling() -> bool:
	return carrier.brain != null and Tuning.b("touch_dribble", true)

func _physics_process(delta: float) -> void:
	if ball.carrier != carrier or not _touch_dribbling():
		return
	var top := maxf(carrier.speed * Locomotion.SPRINT_MULTIPLIER, 1.0)
	var speed := carrier.velocity.length()
	var moving := carrier.current_state is PlayerStateMoving
	if not moving or speed < top * SHIELD_SPEED_FRAC:
		_touch_sep = 0.0
		_touch_phase = 0.0
		ball.position = _ball_at_feet()
		return
	_touch_dir = carrier.velocity / speed
	var prev_phase := _touch_phase
	_touch_phase = fmod(_touch_phase + delta / TOUCH_PERIOD, 1.0)
	var drib := clampf(carrier.dribbling / 100.0, 0.0, 1.0)
	if _touch_phase < prev_phase:
		_poked_this_touch.clear()
		AIProfile.count("td_touch", _nearest_opponent_dist())
		if _roll_loose_touch(speed / top, drib):
			return
	var ahead_s := lerpf(TOUCH_AHEAD_S_POOR, TOUCH_AHEAD_S_GREAT, drib)
	_touch_sep = speed * ahead_s * sin(PI * _touch_phase)
	ball.position = _ball_at_feet()
	if ball.position.distance_to(carrier.position) - OFFSET_FROM_PLAYER.x > EXPOSED_PX:
		_try_pokes()

## A new touch at [param speed_frac] of top speed: sometimes it's too heavy.
func _roll_loose_touch(speed_frac: float, drib: float) -> bool:
	var p := LOOSE_TOUCH_BASE * speed_frac * (1.2 - drib)
	if _nearest_opponent_dist() < PRESSURE_PX:
		p *= LOOSE_TOUCH_PRESSURE
	if MatchRng.randf() >= p:
		return false
	var v := carrier.velocity + _touch_dir * MatchRng.randf_range(LOOSE_TOUCH_EXTRA_MIN, LOOSE_TOUCH_EXTRA_MAX)
	var who := carrier
	_release(v, who)
	GameEvents.dribble_loose_touch.emit(who)
	return true

func _try_pokes() -> void:
	for d: Player in carrier.get_opponents():
		if _poked_this_touch.has(d) or not d.can_carry_ball():
			continue
		if d.position.distance_to(ball.position) > POKE_REACH_PX:
			continue
		_poked_this_touch[d] = true
		AIProfile.count("td_poke_attempt")
		if MatchRng.randf() >= Player.tackle_win_chance(d.defense, carrier.dribbling):
			continue
		var away := carrier.position.direction_to(ball.position).lerp(d.position.direction_to(ball.position), 0.5)
		if away == Vector2.ZERO:
			away = _touch_dir
		away = away.normalized().rotated(deg_to_rad(MatchRng.randf_range(-40.0, 40.0)))
		var victim := carrier
		_release(away * MatchRng.randf_range(POKE_SPEED_MIN, POKE_SPEED_MAX), victim)
		ball.last_touch = d
		GameEvents.dribble_poked.emit(d, victim)
		return

## The ball leaves the carrier's control as a loose ball; he can't re-collect
## it for Ball.KICK_COOLDOWN_MS.
func _release(v: Vector2, who: Player) -> void:
	ball.mark_touch(who)
	ball.velocity = v
	ball.height_velocity = 0.0
	ball.carrier = null
	state_transition_requested.emit(Ball.State.FREEFORM)

func _nearest_opponent_dist() -> float:
	var best := INF
	for o: Player in carrier.get_opponents():
		best = minf(best, o.position.distance_to(carrier.position))
	return best

func _ball_at_feet() -> Vector2:
	return _keep_in(_ball_at_feet_raw())

## A carrier near a line takes a shorter touch instead of knocking it out:
## pull the ball back toward his feet until it's inside (a first cut let the
## touch carry it over the line, and carries out of play went 187 -> 876 in
## 64 matches).
## Extra px inside OutOfPlay's detection line.
const LINE_SAFETY_PX := 4.0

## Same geometry as OutOfPlay.crossed (goal mouths treated as closed).
static func _inside(p: Vector2) -> bool:
	var c := p + OutOfPlay.BALL_COLLISION_OFFSET
	var m := OutOfPlay.MARGIN_PX + LINE_SAFETY_PX
	return c.y > PitchSpace.TOP_Y + m and c.y < PitchSpace.BOTTOM_Y - m \
		and c.x > PitchSpace.left_line_x(c.y) + m and c.x < PitchSpace.right_line_x(c.y) - m

func _keep_in(p: Vector2) -> Vector2:
	var feet := carrier.position + Vector2(0.0, OFFSET_FROM_PLAYER.y)
	for i in 6:
		if _inside(p):
			return p
		p = p.lerp(feet, 0.5)
	return feet

func _ball_at_feet_raw() -> Vector2:
	if _touch_sep > 0.0:
		return carrier.position + _touch_dir * (OFFSET_FROM_PLAYER.x + _touch_sep) + Vector2(0.0, OFFSET_FROM_PLAYER.y)
	# Shielding: keep the ball on the far side from the nearest opponent.
	var nearest : Player = null
	var best := PRESSURE_PX
	for o: Player in carrier.get_opponents():
		var dd := o.position.distance_to(carrier.position)
		if dd < best:
			best = dd
			nearest = o
	if nearest != null:
		return carrier.position + nearest.position.direction_to(carrier.position) * SHIELD_OFFSET_PX + Vector2(0.0, OFFSET_FROM_PLAYER.y)
	return carrier.position + Vector2(carrier.heading.x * OFFSET_FROM_PLAYER.x, OFFSET_FROM_PLAYER.y)

func _process(delta: float) -> void:
	if ball.carrier != carrier:
		return
	var vx := 0.0
	dribble_time += delta

	if carrier.velocity != Vector2.ZERO:
		if carrier.velocity.x != 0:
			vx = cos(dribble_time * DRIBBLE_FREQUENCY) * DRIBBLE_INTENSITY
		if carrier.heading.x >= 0:
			animation_player.play("roll")
			animation_player.advance(0)
		else:
			animation_player.play_backwards("roll")
			animation_player.advance(0)
	else:
		animation_player.play("idle")
	process_gravity(delta)
	if _touch_dribbling():
		ball.position = _ball_at_feet()
		return
	ball.position = carrier.position + Vector2(vx + carrier.heading.x * OFFSET_FROM_PLAYER.x, OFFSET_FROM_PLAYER.y)
