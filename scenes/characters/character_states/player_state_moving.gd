class_name PlayerStateMoving
extends PlayerState

func _process(_delta: float) -> void:
	player.set_movement_animation()
	player.set_heading()
	if player.velocity != Vector2.ZERO:
		teammate_detection_area.rotation = player.velocity.angle()

	# if player.has_ball():
		# If decided to shoot: 
		# transition_state(Player.State.PREPPING_SHOT)
	
		# If decided to pass:
		# transition_state(Player.State.PASSING)	
	# elif ball.can_air_interact():
		# if player.velocity == Vector2.ZERO:
			# if is_facing_target_goal():
				# transition_state(Player.State.VOLLEY_KICK)
			# else: 
				# transition_state(Player.State.BICYCLE_KICK)
		# if decided to shoot:
			# transition_state(Player.State.HEADER)
		
func is_facing_target_goal() -> bool:
	var direction_to_target_goal := player.position.direction_to(target_goal.position)
	return player.heading.dot(direction_to_target_goal) > 0
