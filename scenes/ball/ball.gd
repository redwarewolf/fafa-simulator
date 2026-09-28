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
## Lofted-pass airtime (seconds) as a function of distance: LOFT_TIME_BASE +
## distance × LOFT_TIME_PER_PX, clamped. The launch is solved so the ball's
## FIRST LANDING is on the target (see pass_launch).
##
## Replaced an older launch (air-friction-sized speed × 1.08, height velocity
## scaled by sqrt(dt)) that looked right on paper but, measured against the
## real engine (tools/ball_probe.tscn), gave only ~0.3s of airtime: the ball
## landed almost immediately, then rolled to a stop under ground friction at
## ~26-30% of the intended distance (350px → 90px, 900px → 264px). Every long
## pass, switch and through ball fell short. See docs/match-engine-v2.md
## Findings #2.
const LOFT_TIME_BASE := 0.4
const LOFT_TIME_PER_PX := 1.0 / 900.0
const LOFT_TIME_MIN := 0.7
const LOFT_TIME_MAX := 1.6
const TUMBLE_HEIGHT_VELOCITY := 3.0
const LONG_KICK_ARC_MULTIPLIER := 3.0

@onready var _kick_sound : AudioStreamPlayer = %KickSound

@export_group("Kick sound")
@export var kick_sound_volume_db : float = 0.0
## Random pitch jitter (+/-) applied each time the ball is launched — shots,
## passes, long kicks, and balls won off a tackle (see Player.on_tackle_player)
## all go through play_kick_sound(), so without this every one of those would
## play back the exact same clip. Same trick as DialogueBox's talk sound.
@export var kick_sound_pitch_variance : float = 0.15
@export var kick_sound_volume_variance_db : float = 3.0

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
			last_touch = value
			GameEvents.ball_possessed.emit(value.full_name)
			GameEvents.possession_gained.emit(value)
		else:
			GameEvents.ball_released.emit()
## Last player to touch the ball — gaining possession, winning a tackle, or a
## physical deflection (see BallState.move_and_bounce). Decides who gets a
## throw-in / corner / goal kick when the ball goes out (RestartManager).
var last_touch: Player = null
## The player who just kicked/lost the ball can't instantly re-collect it
## while it's still leaving their feet (the overlap poll in
## BallStateFreeform would otherwise hand a pass straight back to the passer).
const KICK_COOLDOWN_MS := 300
var _kicker: Player = null
var _kick_time_ms := -100000
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
		
## Randomizes pitch/volume around their exported base values and (re)plays
## the kick sound. A single shared player means a kick that lands while the
## previous one is still tailing off cuts it short — fine here since there's
## only ever one ball, so only one kick can ever be "in flight" at a time.
func play_kick_sound() -> void:
	_kick_sound.pitch_scale = 1.0 + randf_range(-kick_sound_pitch_variance, kick_sound_pitch_variance)
	_kick_sound.volume_db = kick_sound_volume_db + randf_range(-kick_sound_volume_variance_db, kick_sound_volume_variance_db)
	_kick_sound.play()

## Remembers who's releasing the ball (see KICK_COOLDOWN_MS). Call before
## clearing carrier.
func _mark_kick() -> void:
	if carrier != null:
		_kicker = carrier
		_kick_time_ms = MatchClock.now_ms()

func is_kick_cooldown(p: Player) -> bool:
	return p == _kicker and MatchClock.now_ms() - _kick_time_ms < KICK_COOLDOWN_MS

func shoot(shot_velocity : Vector2) -> void:
	_mark_kick()
	velocity = shot_velocity
	carrier = null
	switch_state(Ball.State.SHOT)
	play_kick_sound()
	
func tumble(tumble_velocity: Vector2) -> void:
	_mark_kick()
	carrier = null
	velocity = tumble_velocity
	height_velocity = TUMBLE_HEIGHT_VELOCITY
	switch_state(Ball.State.FREEFORM)
	
func pass_to(destination: Vector2) -> void:
	var launch := pass_launch(position, destination)
	_mark_kick()
	velocity = launch["velocity"]
	height_velocity = launch["height_velocity"]
	carrier = null
	switch_state(Ball.State.FREEFORM)
	play_kick_sound()

## The launch pass_to() gives a ball kicked from [param from] to
## [param destination]: {"velocity": Vector2, "height_velocity": float}.
## Static so BallPredictor/PassModel evaluate exactly the kick the engine
## would actually perform.
static func pass_launch(from: Vector2, destination: Vector2) -> Dictionary:
	var direction := from.direction_to(destination)
	var distance := from.distance_to(destination)
	if distance > DISTANCE_HIGH_PASS:
		# Lofted. BallState.process_gravity() adds height_velocity to height
		# once per physics TICK (not scaled by delta) and subtracts
		# GRAVITY*delta from height_velocity per tick, so a launch of
		# height_velocity h is airborne for 2h/(GRAVITY*dt) ticks = 2h/GRAVITY
		# seconds. Pick the airtime T, then h = GRAVITY*T/2; horizontally the
		# ball decelerates at FRICTION_AIR for those T seconds, so the launch
		# speed covering `distance` by the landing is (d + ½·a·T²)/T.
		var t := loft_time(distance)
		var speed := (distance + 0.5 * FRICTION_AIR * t * t) / t
		return {"velocity": speed * direction, "height_velocity": BallState.GRAVITY * t * 0.5}
	# Grounded: height stays 0 the whole flight, so sizing off
	# FRICTION_GROUND is exact — this is the friction it'll actually see.
	return {"velocity": sqrt(2 * distance * FRICTION_GROUND) * direction, "height_velocity": 0.0}

static func loft_time(distance: float) -> float:
	return clampf(LOFT_TIME_BASE + distance * LOFT_TIME_PER_PX, LOFT_TIME_MIN, LOFT_TIME_MAX)


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
	_mark_kick()
	velocity = intensity * direction
	carrier = null
	switch_state(Ball.State.FREEFORM)
	play_kick_sound()

## Predicts how long (seconds) a pass_to() kick over `distance` takes to
## arrive, using the same speed-sizing math pass_to() itself uses. A grounded
## kick is sized to decelerate to exactly zero at the target, so its flight
## time is just launch-speed / FRICTION_GROUND; a lofted kick is approximated
## the same way against FRICTION_AIR.
func estimate_pass_flight_time(distance: float) -> float:
	if distance > DISTANCE_HIGH_PASS:
		return loft_time(distance)  # the launch is solved to land on target at exactly this time
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
	last_touch = null
	position = spawn_position
	velocity = Vector2.ZERO
	height = 0.0
	height_velocity = 0.0
	switch_state(State.FREEFORM)
