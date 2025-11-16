class_name PlayerStateMoving
extends PlayerState

func _process(_delta: float) -> void:
	player.set_movement_animation()
	player.set_heading()
	ai_behavior.process_ai()
	if player.velocity != Vector2.ZERO:
		teammate_detection_area.rotation = player.velocity.angle()

	
