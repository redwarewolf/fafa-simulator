class_name RoleBehavior
extends Node

# References set during setup
var player: Player = null
var ball: Ball = null
var teammate_detection_area: Area2D = null
var ball_detection_area: Area2D = null
var opponent_detection_area: Area2D = null
var own_goal: Goal = null
var target_goal: Goal = null

func setup(context_player: Player, context_ball: Ball, context_teammate_detection: Area2D, context_ball_detection: Area2D, context_opponent_detection: Area2D, context_own_goal: Goal, context_target_goal: Goal) -> void:
	player = context_player
	ball = context_ball
	teammate_detection_area = context_teammate_detection
	ball_detection_area = context_ball_detection
	opponent_detection_area = context_opponent_detection
	own_goal = context_own_goal
	target_goal = context_target_goal

# Override in subclasses: Returns steering force for role-specific positioning
func get_positioning_force() -> Vector2:
	return Vector2.ZERO

# Override in subclasses: Makes role-specific decisions (shoot, pass, tackle, etc.)
func make_decisions() -> void:
	pass

# ===== UTILITY FUNCTIONS (available to all role behaviors) =====

func player_has_ball() -> bool:
	return ball.carrier == player

func is_ball_carried() -> bool:
	return ball.carrier != null and ball.carrier != player

func is_ball_carried_by_teammate() -> bool:
	return is_ball_carried() and ball.carrier.team == player.team

func is_ball_carried_by_opponent() -> bool:
	return is_ball_carried() and ball.carrier.team != player.team

func player_is_on_tackle_distance(distance: float = 15.0) -> bool:
	return player.position.distance_to(ball.position) < distance

func has_opponents_nearby() -> bool:
	var players := opponent_detection_area.get_overlapping_bodies()
	return players.any(func(p: Player): return p.team != player.team)

func get_closest_teammate_in_view() -> Player:
	var players_in_view := teammate_detection_area.get_overlapping_bodies()
	var teammates_in_view := players_in_view.filter(
		func(p: Player): return p != player and p.team == player.team
	)
	teammates_in_view.sort_custom(
		func(p1: Player, p2: Player): return p1.position.distance_squared_to(player.position) < p2.position.distance_squared_to(player.position)
	)
	if teammates_in_view.size() > 0:
		return teammates_in_view[0]
	return null

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
