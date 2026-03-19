class_name GoalieBehavior
extends RoleBehavior

const GOAL_LINE_DISTANCE := 30.0 # How far from goal line to position
const MAX_ROAM_DISTANCE := 80.0 # Maximum distance from goal to chase ball

func get_positioning_force() -> Vector2:
	var goal_center := own_goal.get_center_target_position()
	
	# If ball is very close and no one has it, consider coming out
	if ball.carrier == null:
		var ball_distance := player.position.distance_to(ball.position)
		if ball_distance < MAX_ROAM_DISTANCE:
			# Move towards ball but stay near goal
			var to_ball := player.position.direction_to(ball.position)
			return to_ball * 0.5
	
	# Default: Stay near goal line, position based on ball angle
	var ball_to_goal := ball.position.direction_to(goal_center)
	var ideal_position := goal_center - ball_to_goal * GOAL_LINE_DISTANCE
	
	var to_ideal := player.position.direction_to(ideal_position)
	var weight := get_bicircular_weight(player.position, ideal_position, 20, 0.1, 40, 1.0)
	
	return to_ideal * weight

func make_decisions() -> void:
	# Goalies don't make offensive decisions
	# They can't shoot or pass in this simple implementation
	# Future: Could add clearing passes or goal kicks
	pass
