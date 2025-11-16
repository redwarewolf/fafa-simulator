class_name PlayerStateShooting
extends PlayerState

func _enter_tree() -> void:
	animation_player.play("kick")
	print("Play Kick")
	
func on_animation_complete() -> void:
	shoot_ball()
	transition_state(Player.State.MOVING)
	
func shoot_ball() -> void:
	ball.shoot(state_data.shot_direction * state_data.shot_power)
