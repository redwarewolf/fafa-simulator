class_name PlayerStatePassing
extends PlayerState

func _enter_tree() -> void:
	animation_player.play("kick")
	player.velocity = Vector2.ZERO

func on_animation_complete() -> void:
	var pass_target := get_closest_teammate_in_view()
	print(pass_target)
	var target := Vector2(10,10)
	var pass_direction := ball.position.direction_to(target)
	var pass_distance := ball.position.distance_to(target)
	var pass_velocity := sqrt(2* pass_distance * BallStateFreeform.FRICTION_GROUND)
	ball.pass_to(pass_direction * pass_velocity)
	transition_state(Player.State.MOVING)
	
func get_closest_teammate_in_view() -> Player:
	var players_in_view = teammate_detection_area.get_overlapping_bodies()
	var teammates_in_view = players_in_view.filter(
		func(p: Player): return p != player
	)
	var closest: Player = null
	var closest_dist := INF
	for p in teammates_in_view:
		var d = p.position.distance_squared_to(player.position)
		if d < closest_dist:
			closest_dist = d
			closest = p
	return closest

	
