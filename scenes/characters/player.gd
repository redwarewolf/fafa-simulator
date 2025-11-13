class_name Player
extends CharacterBody2D

const DURATION_TACKLE := 200
const GRAVITY := 8.0
const BALL_CONTROL_HEIGHT_MAX := 10.0

enum State { MOVING , TACKLING, RECOVERING, PREPPING_SHOT, SHOOTING, 
	PASSING , HEADER, VOLLEY_KICK, BICYCLE_KICK, CHEST_CONTROL}

enum Role { GOALIE, DEFENSE, MIDFIELD, OFFENSE }
enum SkinColor { LIGHT, MEDIUM, DARK, GREEN, RED }

@export var own_goal : Goal
@export var target_goal : Goal

# STATS
var full_name : String = ""
var role : Player.Role
var skin : Player.SkinColor
@export var speed : float = 80
@export var power : float = 70

var current_state: PlayerState = null
var state_factory := PlayerStateFactory.new()

var heading := Vector2.RIGHT
var height := 0.0
var height_velocity := 0.0
var ball : Ball

@onready var animation_player : AnimationPlayer = %AnimationPlayer
@onready var player_sprite : Sprite2D = %PlayerSprite
@onready var teammate_detection_area : Area2D = %TeammateDetectionArea
@onready var ball_detection_area : Area2D = %BallDetectionArea

func initialize(context_position : Vector2, context_ball : Ball, context_own_goal: Goal, context_target_goal: Goal, context_player_data : PlayerResource) -> Player:
		position = context_position
		ball = context_ball
		own_goal = context_own_goal
		target_goal = context_target_goal
		power = context_player_data.power
		speed = context_player_data.speed
		full_name = context_player_data.full_name
		role = context_player_data.role
		skin = context_player_data.skin_color
		heading = Vector2.LEFT if target_goal.position.x < position.x else Vector2.RIGHT
		return self

func _ready() -> void:
	switch_state(State.MOVING)
	ball = get_node("/root/World/Ball")

func _process(delta: float) -> void:
	set_movement_animation()
	set_heading()
	flip_sprites()
	process_gravity(delta)
	move_and_slide()
	
func process_gravity(delta: float) -> void:
	if height > 0:
		height_velocity -= GRAVITY * delta
		height += height_velocity
		height = max(0, height)
	player_sprite.position = Vector2.UP * height

func switch_state(state: State, state_data: PlayerStateData = PlayerStateData.new()) -> void:
	if current_state != null:
		current_state.queue_free()
	current_state = state_factory.get_fresh_state(state)
	current_state.setup(self, state_data)
	current_state.state_transition_requested.connect(switch_state.bind())
	current_state.name = "PlayerStateMachine: " + str(state)
	call_deferred("add child", current_state)
		
func set_movement_animation() -> void:
	if velocity.length() > 0:
		animation_player.play("run")
	else:
		animation_player.play("idle")

func set_heading() -> void:
	if velocity.x > 0:
		heading = Vector2.RIGHT
	elif velocity.x < 0:
		heading = Vector2.LEFT

func flip_sprites() -> void:
	if heading == Vector2.RIGHT:
		player_sprite.flip_h = false
	elif heading == Vector2.LEFT:
		player_sprite.flip_h = true
		
		
func has_ball() -> bool:
	return ball.carrier == self
	
func on_animation_complete() -> void:
	if current_state != null:
		current_state.on_animation_complete()
		
func control_ball() -> void:
	if ball.height > BALL_CONTROL_HEIGHT_MAX:
		switch_state(Player.State.CHEST_CONTROL)
