class_name PlayerStateShooting
extends PlayerState

func _enter_tree() -> void:
	animation_player.play("kick")
	
func on_animation_complete() -> void:
	transition_state(Player.State.MOVING)
	shoot_ball()
	
func shoot_ball() -> void:
	ball.shoot(state_data.shot_direction * state_data.shot_power)
