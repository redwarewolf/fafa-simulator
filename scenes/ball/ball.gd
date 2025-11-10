class_name Ball
extends AnimatableBody2D

enum State { CARRIED , FREEFORM, SHOT }

@onready var animation_player : AnimationPlayer = %AnimationPlayer
@onready var player_detection_area : Area2D = %PlayerDetectionArea
@onready var ball_sprite : Sprite2D = %BallSprite



var current_state : BallState = null
var state_factory := BallStateFactory.new()

var carrier : Player = null
var velocity := Vector2.ZERO
var height_velocity := 0.0
var heading := Vector2.RIGHT
var height := 0.0

func _ready() -> void:
	switch_state(State.FREEFORM)
	
func _process(_delta: float) -> void:
	ball_sprite.position = Vector2.UP * height

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
	
func pass_to(pass_velocity: Vector2) -> void:
	velocity = pass_velocity
	carrier = null
	switch_state(Ball.State.FREEFORM)
	
