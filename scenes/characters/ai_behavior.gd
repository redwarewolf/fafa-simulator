class_name AIBehavior
extends Node

const DURATION_AI_TICK_FREQUENCY := 200

var ball: Ball = null
var player: Player = null
var time_since_last_ai_tick := Time.get_ticks_msec()
var opponent_detection_area: Area2D = null

var role_behavior: RoleBehavior = null

func _ready() -> void:
	time_since_last_ai_tick = Time.get_ticks_msec() + randi_range(0, DURATION_AI_TICK_FREQUENCY)

func setup(context_player: Player, context_ball: Ball, context_opponent_detection_area: Area2D) -> void:
	player = context_player
	ball = context_ball
	opponent_detection_area = context_opponent_detection_area
	
	setup_role_behavior()

func setup_role_behavior() -> void:
	match player.role:
		Player.Role.GOALIE:
			role_behavior = GoalieBehavior.new()
		Player.Role.DEFENSE:
			role_behavior = DefenderBehavior.new()
		Player.Role.MIDFIELD:
			role_behavior = MidfielderBehavior.new()
		Player.Role.OFFENSE:
			role_behavior = ForwardBehavior.new()
		_:
			role_behavior = MidfielderBehavior.new() # Default fallback
	
	role_behavior.name = "RoleBehavior"
	add_child(role_behavior)
	
	# Pass all necessary context to the role behavior
	role_behavior.setup(
		player,
		ball,
		player.teammate_detection_area,
		player.ball_detection_area,
		opponent_detection_area,
		player.own_goal,
		player.target_goal
	)

func process_ai() -> void:
	if Time.get_ticks_msec() - time_since_last_ai_tick > DURATION_AI_TICK_FREQUENCY:
		time_since_last_ai_tick = Time.get_ticks_msec()
		perform_ai_movement()
		perform_ai_decisions()
	
func perform_ai_movement() -> void:
	var total_steering_force := Vector2.ZERO

	# 1. Role-specific positioning (Delegated)
	if role_behavior:
		total_steering_force += role_behavior.get_positioning_force()

	# 2. Universal behaviors (Applies to all roles)
	total_steering_force += get_teammate_repulsion_force()

	total_steering_force = total_steering_force.limit_length(1.0)

	player.velocity = total_steering_force * player.speed

func get_teammate_repulsion_force() -> Vector2:
	var repulsion := Vector2.ZERO

	for other in player.get_teammates():
		if other == player:
			continue

		var dist := player.position.distance_to(other.position)

		if dist < 40: # Minimum desired spacing
			var push := (player.position - other.position).normalized() * (40 - dist)
			repulsion += push

	return repulsion

	
func perform_ai_decisions() -> void:
	# Delegate decision making to role behavior
	if role_behavior:
		role_behavior.make_decisions()
