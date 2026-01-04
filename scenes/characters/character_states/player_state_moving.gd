class_name PlayerStateMoving
extends PlayerState

const WALK_ANIM_THRESHOLD := 0.6

func _process(_delta: float) -> void:
	set_movement_animation()
	player.set_heading()
	ai_behavior.process_ai()
	if player.velocity != Vector2.ZERO:
		teammate_detection_area.rotation = player.velocity.angle()


func set_movement_animation() -> void: #Configurar velocidad de animacion segun velocidad?
	var vel_length := player.velocity.length()
	if vel_length < 1:
		animation_player.play("idle")
	elif vel_length < player.speed * WALK_ANIM_THRESHOLD:
		animation_player.play("walk")
	else:
		animation_player.play("run")
