class_name Ball
extends AnimatableBody2D

enum State { CARRIED , FREEFORM, SHOT }

@onready var animation_player : AnimationPlayer = %AnimationPlayer
@onready var player_detection_area : Area2D = %PlayerDetectionArea
@onready var ball_sprite : Sprite2D = %BallSprite

const FRICTION_AIR := 35.0
## Lowered from 200: at 200 a grounded ball launched at the speed pass_to()
## computes for its target distance decelerated to a stop in ~1.7s for a
## 300px pass, reading as a hard, sudden brake right at the end. 150 keeps
## the same exact-arrival math (pass_to sizes launch speed off this constant,
## so passes still land on target) but spends longer easing down from a
## lower peak speed instead. Shots don't self-size off this constant — see
## PlayerStateShooting.SHOT_SPEED_MIN/MAX, which were retuned to compensate
## so shot distances didn't change when this dropped.
const FRICTION_GROUND := 150.0
const BOUNCINESS := 0.8
## Passes past this distance loft into the air instead of staying grounded.
## Raised from 130: most real exchanges (100-300px) should stay fast, direct,
## grounded balls — lofting was previously the common case, not the exception.
const DISTANCE_HIGH_PASS := 300
## A lofted pass's launch speed spends most of its flight airborne, where
## BallStateFreeform applies FRICTION_AIR, not FRICTION_GROUND — sizing that
## speed off ground friction (like a grounded pass does) badly undershoots
## real friction and the ball overshoots its target, sometimes drastically,
## on anything long enough to loft. This factor nudges the air-friction-based
## speed (see pass_to) back up to land close to target. Tuned against a
## step-by-step replay of BallStateFreeform's actual physics (friction
## switch + the landing bounce, which also steals horizontal speed) across
## 320-650px, landing within ~2% of the intended distance at 1.08.
const HIGH_PASS_SPEED_CORRECTION := 1.08
const TUMBLE_HEIGHT_VELOCITY := 3.0
const LONG_KICK_ARC_MULTIPLIER := 3.0

## BallState.process_gravity() adds height_velocity to height every physics
## tick without scaling it by delta (height += height_velocity, not
## height_velocity * delta) — a quirk shared with Player's own gravity, and
## the reason every other height_velocity in the game (header ~1.5, jump 2.0,
## hurt 3.0) stays tiny. pass_to()/long_kick() instead derive height_velocity
## from real projectile-motion math (v_y0 = g*T/2), which assumes height DOES
## integrate with a delta-scaled dt each tick. Multiplying that result by
## sqrt(physics delta) converts it into this engine's un-scaled convention —
## without this, a 400px pass arced roughly 450px into the air.
var _height_velocity_scale := sqrt(1.0 / Engine.physics_ticks_per_second)

var current_state : BallState = null
var state_factory := BallStateFactory.new()

var _carrier: Player = null
## Writing this property emits ball_possessed / ball_released on GameEvents.
var carrier: Player:
	get: return _carrier
	set(value):
		if _carrier == value:
			return
		_carrier = value
		if not is_node_ready():
			return
		if value != null:
			GameEvents.ball_possessed.emit(value.full_name)
		else:
			GameEvents.ball_released.emit()
var velocity := Vector2.ZERO
var height_velocity := 0.0
var heading := Vector2.RIGHT
var height := 0.0
var spawn_position := Vector2.ZERO

## RayCast2D that rotates with ball velocity — used to detect goal-mouth shots.
var _scoring_raycast: RayCast2D = null
const RAYCAST_LENGTH := 3000.0

func _ready() -> void:
	spawn_position = position
	switch_state(State.FREEFORM)
	GameEvents.team_reset.connect(_on_team_reset)
	_scoring_raycast = RayCast2D.new()
	_scoring_raycast.collision_mask = Goal.SCORING_COLLISION_LAYER
	_scoring_raycast.target_position = Vector2(RAYCAST_LENGTH, 0.0)
	_scoring_raycast.enabled = true
	add_child(_scoring_raycast)
	
func _process(_delta: float) -> void:
	ball_sprite.position = Vector2.UP * height
	# Keep raycast aimed along velocity so it physically traces where the ball is going.
	if _scoring_raycast != null:
		_scoring_raycast.target_position = (
			velocity.normalized() * RAYCAST_LENGTH if velocity.length_squared() > 0.0
			else Vector2.ZERO
		)

func switch_state(state: Ball.State) -> void:
	if current_state != null:
		current_state.queue_free()
	current_state = state_factory.get_fresh_state(state)
	current_state.setup(self)
	current_state.state_transition_requested.connect(switch_state.bind())
	current_state.name = "BallStateMachine"
	call_deferred("add_child",current_state)
	
	
func set_heading() -> void:
	if(carrier != null):
		heading = carrier.heading
	elif(velocity.x >= 0):
		heading = Vector2.RIGHT
	else:
		heading = Vector2.LEFT
		

func flip_sprites() -> void:
	if heading == Vector2.RIGHT:
		ball_sprite.flip_h = false
	elif heading == Vector2.LEFT:
		ball_sprite.flip_h = true
		
func shoot(shot_velocity : Vector2) -> void:
	velocity = shot_velocity
	carrier = null
	switch_state(Ball.State.SHOT)
	
func tumble(tumble_velocity: Vector2) -> void:
	carrier = null
	velocity = tumble_velocity
	height_velocity = TUMBLE_HEIGHT_VELOCITY
	switch_state(Ball.State.FREEFORM)
	
func pass_to(destination: Vector2) -> void:
	var direction := position.direction_to(destination)
	var distance := position.distance_to(destination)
	if distance > DISTANCE_HIGH_PASS:
		# Lofted: size speed off FRICTION_AIR since the ball spends most of
		# this flight airborne (see HIGH_PASS_SPEED_CORRECTION above).
		var intensity := sqrt(2 * distance * FRICTION_AIR) * HIGH_PASS_SPEED_CORRECTION
		velocity = intensity * direction
		height_velocity = BallState.GRAVITY * distance / (1.8 * intensity) * _height_velocity_scale
	else:
		# Grounded: height stays 0 the whole flight, so sizing off
		# FRICTION_GROUND is exact — this is the friction it'll actually see.
		var intensity := sqrt(2 * distance * FRICTION_GROUND)
		velocity = intensity * direction
		height_velocity = 0.0  # Short pass stays on the ground — clear any residual velocity
	carrier = null
	switch_state(Ball.State.FREEFORM)

## Goalkeeper long distribution — a high-arc inverted parabola.
## Uses air friction for the horizontal component so the ball carries far,
## and sets a large height_velocity for the visible arc.
func long_kick(destination: Vector2) -> void:
	var direction := position.direction_to(destination)
	var distance := position.distance_to(destination)
	# Arc height only — sized off a friction-based reference speed purely to
	# pick a height_velocity that looks like "~3x a regular high pass" (this
	# part was already tuned and correct). This reference speed is NOT used
	# for the actual launch below.
	var arc_reference_speed := sqrt(2.0 * distance * FRICTION_AIR)
	height_velocity = BallState.GRAVITY * distance / (1.8 * arc_reference_speed) * LONG_KICK_ARC_MULTIPLIER * _height_velocity_scale
	# process_gravity() decrements height_velocity by GRAVITY*delta per tick
	# and adds it straight to height (no *delta) — so ticks-to-apex is
	# height_velocity/(GRAVITY*delta), and real hang time to first landing is
	# double that in seconds: 2*height_velocity/GRAVITY. That's *much*
	# shorter than continuous projectile math would suggest (that's what
	# _height_velocity_scale above already corrects for, for apex height).
	# Sizing horizontal speed off friction-deceleration-to-zero (the old
	# `sqrt(2*distance*FRICTION_AIR)`) assumed the ball stays airborne long
	# enough to actually decelerate to a stop — it doesn't; it lands while
	# still going ~80% of launch speed, hits FRICTION_GROUND (4.3x harsher)
	# plus bounce restitution loss, and stalls at ~40-65% of the intended
	# distance. Solve directly for the speed that covers `distance` in the
	# real hang time this arc produces, net of FRICTION_AIR's decel along
	# the way, so the kick actually reaches its target.
	var hang_time := 2.0 * height_velocity / BallState.GRAVITY
	var intensity := distance / hang_time + 0.5 * FRICTION_AIR * hang_time
	velocity = intensity * direction
	carrier = null
	switch_state(Ball.State.FREEFORM)

## Predicts how long (seconds) a pass_to() kick over `distance` takes to
## arrive, using the same speed-sizing math pass_to() itself uses. A grounded
## kick is sized to decelerate to exactly zero at the target, so its flight
## time is just launch-speed / FRICTION_GROUND; a lofted kick is approximated
## the same way against FRICTION_AIR.
func estimate_pass_flight_time(distance: float) -> float:
	if distance > DISTANCE_HIGH_PASS:
		return sqrt(2.0 * distance / FRICTION_AIR) * HIGH_PASS_SPEED_CORRECTION
	return sqrt(2.0 * distance / FRICTION_GROUND)

## Where to actually aim a pass so it meets a moving receiver instead of
## where they are right now. Leading by target_velocity * flight_time(current
## distance) is self-defeating for a receiver running AWAY: that lead pushes
## the destination farther out, which means a longer flight time, which needs
## a longer lead still — a single pass at the calculation undershoots by as
## much as 100+px for a forward sprinting onto a through ball, since it only
## ever accounts for how far they'd move during the flight time of the
## SHORTER, un-led distance. Iterating a few times converges on the
## destination whose own flight time actually matches the lead used to reach
## it (a fixed point — each pass shrinks the gap since the receiver is always
## slower than the ball, so it settles in a handful of steps).
func estimate_pass_lead_destination(from_position: Vector2, target_position: Vector2, target_velocity: Vector2) -> Vector2:
	var destination := target_position
	for i in 4:
		var flight_time := estimate_pass_flight_time(from_position.distance_to(destination))
		destination = target_position + target_velocity * flight_time
	return destination

func stop() -> void:
	velocity = Vector2.ZERO

func can_air_interact() -> bool:
	return current_state != null and current_state.can_air_interact()
	
func can_air_connect(air_connect_min_height: float, air_connect_max_height: float) -> bool:
	return height >= air_connect_min_height and height <= air_connect_max_height

## Returns true if the ball's trajectory (via RayCast2D) will hit the goal mouth.
## The raycast uses Goal.SCORING_COLLISION_LAYER so only scoring bodies are detected.
func is_headed_for_scoring_area(goal: Goal) -> bool:
	if _scoring_raycast == null or not _scoring_raycast.is_colliding():
		return false
	return _scoring_raycast.get_collider() == goal.scoring_body

## Reset ball to center after a goal is scored.
func _on_team_reset() -> void:
	carrier = null
	position = spawn_position
	velocity = Vector2.ZERO
	height = 0.0
	height_velocity = 0.0
	switch_state(State.FREEFORM)
