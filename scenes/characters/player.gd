class_name Player
extends CharacterBody2D

const DURATION_TACKLE := 200
const GRAVITY := 8.0
const BALL_CONTROL_HEIGHT_MAX := 10.0
const WALK_ANIM_THRESHOLD := 0.6

enum State { MOVING, TACKLING, RECOVERING, PREPPING_SHOT, SHOOTING,
	PASSING, HEADER, VOLLEY_KICK, BICYCLE_KICK, CHEST_CONTROL, HURT, DIVING }

enum Role { GOALIE, DEFENSE, MIDFIELD, OFFENSE }
enum SkinColor { LIGHT, MEDIUM, DARK, RADIOACTIVE, DEMONIC, ALIEN, ROBOT }
const TEAMS := [ "DEFAULT", "SACA CHISPAS", "LOS FULBOS FC", "CLUB ATLETICO PIÑATA", "DEPORTIVO LADRILLO", "UNION PATADURAS", "ATLÉTICO GAMBETA", "SAN LORENZO DE NADA", "RACING DE LA ESQUINA" ]

var ai_behavior : AIBehavior = AIBehavior.new()

@export var own_goal : Goal
@export var target_goal : Goal

# STATS
var full_name : String = ""
var role : Player.Role
var skin : Player.SkinColor
var team : String = ""
@export var speed : float = 80
@export var power : float = 70

var current_state: PlayerState = null
var state_factory := PlayerStateFactory.new()

var spawn_position := Vector2.ZERO
var weight_on_duty_steering := 0.0
var heading := Vector2.RIGHT
var height := 0.0
var height_velocity := 0.0
var ball : Ball

var teammates : Array[Player] = []

@onready var animation_player : AnimationPlayer = %AnimationPlayer
@onready var player_sprite : Sprite2D = %PlayerSprite
@onready var teammate_detection_area : Area2D = %TeammateDetectionArea
@onready var ball_detection_area : Area2D = %BallDetectionArea
@onready var tackle_damage_emitter_area : Area2D = %TackleDamageEmitterArea
@onready var opponent_detection_area : Area2D = %OpponentDetectionArea

func initialize(context_position : Vector2, context_ball : Ball, context_own_goal: Goal, context_target_goal: Goal, context_player_data : PlayerResource, context_team: String) -> Player:
		position = context_position
		ball = context_ball
		own_goal = context_own_goal
		target_goal = context_target_goal
		power = context_player_data.sho
		speed = context_player_data.pac
		full_name = context_player_data.full_name
		role = context_player_data.role
		skin = context_player_data.skin_color
		heading = Vector2.LEFT if target_goal.position.x < position.x else Vector2.RIGHT
		team = context_team
		return self

func _ready() -> void:
	spawn_position = position
	setup_ai_behavior()
	set_shader_properties()
	switch_state(State.MOVING)
	tackle_damage_emitter_area.body_entered.connect(on_tackle_player.bind())

func _process(delta: float) -> void:
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
	current_state.setup(self, state_data, animation_player, ball, teammate_detection_area, ball_detection_area, own_goal, target_goal, tackle_damage_emitter_area,ai_behavior)
	current_state.state_transition_requested.connect(switch_state.bind())
	current_state.name = "PlayerStateMachine: " + str(state)
	call_deferred("add_child", current_state)


func set_heading() -> void:
	if velocity.x > 0:
		heading = Vector2.RIGHT
	elif velocity.x < 0:
		heading = Vector2.LEFT

func flip_sprites() -> void:
	if heading == Vector2.RIGHT:
		player_sprite.flip_h = false
		tackle_damage_emitter_area.scale.x = 1
		opponent_detection_area.scale.x = 1
	elif heading == Vector2.LEFT:
		player_sprite.flip_h = true
		tackle_damage_emitter_area.scale.x = -1
		opponent_detection_area.scale.x = -1
		
func has_ball() -> bool:
	return ball.carrier == self

func can_carry_ball() -> bool:
	return current_state != null and current_state.can_carry_ball()
	
func on_animation_complete() -> void:
	if current_state != null:
		current_state.on_animation_complete()
		
func control_ball() -> void:
	if ball.height > BALL_CONTROL_HEIGHT_MAX:
		switch_state(Player.State.CHEST_CONTROL)

func set_shader_properties() -> void:
	player_sprite.material.set_shader_parameter("skin_color", skin)
	var team_color := TEAMS.find(team)
	team_color = clampi(team_color,0, TEAMS.size()-1)
	player_sprite.material.set_shader_parameter("team_color", team_color)

func setup_ai_behavior() -> void:
	ai_behavior.setup(self, ball, opponent_detection_area)
	ai_behavior.name = 'AI Behavior'
	add_child(ai_behavior)
	
func is_facing_target_goal() -> bool:
	var direction_to_target_goal := position.direction_to(target_goal.position)
	return heading.dot(direction_to_target_goal) > 0

func get_teammates() -> Array[Player]:
	return teammates
	
func get_hurt(hurt_origin : Vector2) -> void:
	switch_state(Player.State.HURT, PlayerStateData.build().set_hurt_direction(hurt_origin))
	
func on_tackle_player(player_hit : Player) -> void:
	if player_hit != self and player_hit.team != team and player_hit == ball.carrier:
		player_hit.get_hurt(position.direction_to(player_hit.position))
	
