class_name BallStateFreeform
extends BallState


func _enter_tree() -> void:
	player_detection_area.body_entered.connect(on_player_enter.bind())

func on_player_enter(body: Player) -> void:
	_try_collect(body)

func _try_collect(body: Player) -> bool:
	if ball.carrier != null or not body.can_carry_ball() or ball.is_kick_cooldown(body):
		return false
	# Out of reach overhead — it'll be collectable once it comes down (the
	# overlap poll below re-checks every frame).
	if ball.height > Player.MAX_COLLECT_HEIGHT:
		return false
	# First touch: a fast or dropping ball can squirm away (Player.control_chance).
	if MatchRng.randf() > body.control_chance(ball.velocity.length(), ball.height):
		_heavy_touch(body)
		return false
	ball.carrier = body
	body.control_ball()
	state_transition_requested.emit(Ball.State.CARRIED)
	return true

## Speed kept, and max deflection, when a touch fails.
const HEAVY_TOUCH_SPEED_KEEP := 0.35
const HEAVY_TOUCH_MAX_DEFLECT_DEG := 70.0

## The ball bounces off the player instead of being controlled: slowed, knocked
## off-line, and briefly un-collectable by that same player (kick cooldown),
## so it's a genuine loose ball others can contest.
func _heavy_touch(body: Player) -> void:
	var deflect := deg_to_rad(MatchRng.randf_range(-HEAVY_TOUCH_MAX_DEFLECT_DEG, HEAVY_TOUCH_MAX_DEFLECT_DEG))
	ball.velocity = ball.velocity.rotated(deflect) * HEAVY_TOUCH_SPEED_KEEP
	ball.height_velocity = minf(ball.height_velocity, 0.0)
	ball.last_touch = body
	ball.mark_touch(body)
	GameEvents.heavy_touch.emit(body)

func _physics_process(delta: float) -> void:
	set_ball_animation_from_velocity()
	var friction = ball.FRICTION_AIR if ball.height > 0 else ball.FRICTION_GROUND
	ball.velocity = ball.velocity.move_toward(Vector2.ZERO, friction*delta)
	process_gravity(delta, Ball.GROUND_BOUNCE_VERTICAL)
	move_and_bounce(delta)
	# body_entered only fires on ENTERING the pickup area. A player already
	# overlapping the ball when they become able to carry it (getting up from
	# a tackle/recovery, or a chaser who stopped right on top of it) never
	# re-enters, so the ball used to sit loose at their feet indefinitely —
	# seen in the harness as 50+ second stretches of a dead, untouched ball.
	# Poll the overlaps too. See docs/match-engine-v2.md Findings #3.
	for body in player_detection_area.get_overlapping_bodies():
		if body is Player and _try_collect(body):
			return

func can_air_interact() -> bool:
	return true
