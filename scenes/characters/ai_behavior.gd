class_name AIBehavior
extends Node

const DURATION_AI_TICK_FREQUENCY := 200
const SPREAD_ASSIST_FACTOR := 0.8
const SHOT_DISTANCE := 200

var ball : Ball = null
var player : Player = null
var time_since_last_ai_tick := Time.get_ticks_msec()

func _ready() -> void:
	time_since_last_ai_tick = Time.get_ticks_msec() + randi_range(0, DURATION_AI_TICK_FREQUENCY)

func setup(context_player: Player, context_ball: Ball) -> void:
	player = context_player
	ball = context_ball

func process_ai() -> void:
	if Time.get_ticks_msec() - time_since_last_ai_tick > DURATION_AI_TICK_FREQUENCY:
		time_since_last_ai_tick = Time.get_ticks_msec()
		perform_ai_movement()
		perform_ai_decisions()
	
func perform_ai_movement() -> void:
	var total_steering_force := Vector2.ZERO

	if player.has_ball():
		total_steering_force += get_carrier_steering_force()
	elif player.role != Player.Role.GOALIE:
		total_steering_force += get_onduty_steering_force()
		if is_ball_carried_by_teammate():
			total_steering_force += get_assist_formation_steering()

	total_steering_force += get_teammate_repulsion_force()

	total_steering_force = total_steering_force.limit_length(1.0)

	player.velocity = total_steering_force * player.speed

func get_teammate_repulsion_force() -> Vector2:
	var repulsion := Vector2.ZERO

	for other in player.get_teammates():
		if other == player:
			continue

		var dist := player.position.distance_to(other.position)

		if dist < 40:  # Minimum desired spacing
			var push := (player.position - other.position).normalized() * (40 - dist)
			repulsion += push

	return repulsion

	
func perform_ai_decisions() -> void:
	if player_has_ball():
		
		var target := player.target_goal.get_center_target_position()
		if player.position.distance_to(target) < SHOT_DISTANCE: # Agregar logica para hacer pases o ver si conviene disparar
			face_towards_target_goal() # No creo que esto sea necesario.
			var shot_direction := player.position.direction_to(player.target_goal.get_random_target_position())
			var data := PlayerStateData.build().set_shot_power(player.power).set_shot_direction(shot_direction)
			player.switch_state(Player.State.SHOOTING, data)
			
			
func face_towards_target_goal() -> void:
	if not player.is_facing_target_goal():
		player.heading = player.heading * -1
	

func get_onduty_steering_force() -> Vector2:
	return player.weight_on_duty_steering * player.position.direction_to(ball.position)
	
func get_carrier_steering_force() -> Vector2:
	var target := player.target_goal.get_center_target_position()
	var direction := player.position.direction_to(target)
	var weight := get_bicircular_weight(player.position, target, 100, 0 , 200, 0.9) #En vez de poner 0.9 como peso cuando lleva la pelota, debería limitar la velocidad de los jugadores cuando llevan la pelota segun stats
	return weight * direction
	
func get_assist_formation_steering() -> Vector2:
	var spawn_difference := ball.carrier.spawn_position - player.spawn_position
	var assist_destination := ball.carrier.position - spawn_difference * SPREAD_ASSIST_FACTOR
	var direction := player.position.direction_to(assist_destination)
	var weight := get_bicircular_weight(player.position, assist_destination, 60, 0.2, 90, 1)
	return weight*direction

func get_bicircular_weight(position: Vector2, center_target: Vector2, inner_circle_radius: float, inner_circle_weight: float, outer_circle_radius: float, outer_circle_weight: float) -> float:
	var distance_to_center := position.distance_to(center_target)
	if distance_to_center > outer_circle_radius:
		return outer_circle_weight
	elif distance_to_center < inner_circle_radius:
		return inner_circle_weight
	else: 
		var distance_to_inner_radius := distance_to_center - inner_circle_radius
		var close_range_distance := outer_circle_radius - inner_circle_radius
		return lerpf(inner_circle_weight, outer_circle_weight, distance_to_inner_radius / close_range_distance)

func is_ball_carried_by_teammate() -> bool:
	return ball.carrier != null and ball.carrier != player and ball.carrier.team == player.team

func player_has_ball() -> bool:
	return ball.carrier == player
