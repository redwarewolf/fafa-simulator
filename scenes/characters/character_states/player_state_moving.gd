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
		# if decided to shoot:
			# transition_state(Player.State.HEADER)
		
