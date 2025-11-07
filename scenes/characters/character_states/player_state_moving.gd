class_name PlayerStateMoving
extends PlayerState

func _process(_delta: float) -> void:
	player.set_movement_animation()
	player.set_heading()
