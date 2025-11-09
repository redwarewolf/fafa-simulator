class_name BallStateCarried
extends BallState

const OFFSET_FROM_PLAYER := Vector2(9,3)

const BASE_DRIBBLE_FREQ : float = 8.0         # Base wiggle frequency
const BASE_DRIBBLE_INTENSITY : float = 1.5    # Base horizontal wiggle amount
const BASE_BOUNCE_HEIGHT : float = 3.0        # Base vertical bounce height
var MAX_SPEED : float = 80.0                # Exact player speed for scaling

var dribble_time := 0.0                       # Tracks time for sine/cosine wave


func _enter_tree() -> void:
	assert(carrier != null)
	if(carrier.max_speed):
		MAX_SPEED = carrier.max_speed
	
func _process(delta: float) -> void:
	var base_x = carrier.face_dir.x * OFFSET_FROM_PLAYER.x
	var vx = 0.0
	var vertical_offset = 0.0
	
	ball.set_heading()
	ball.flip_sprites()
	
	if carrier.velocity != Vector2.ZERO:
		dribble_time += delta
		
		# Scale dribble effects based on movement speed
		var speed_factor = clamp(carrier.velocity.length() / MAX_SPEED, 0.5, 1.2)
		var freq = BASE_DRIBBLE_FREQ * speed_factor
		var intensity = BASE_DRIBBLE_INTENSITY * speed_factor
		var bounce_height = BASE_BOUNCE_HEIGHT * speed_factor
		
		 # Horizontal wiggle and vertical bounce
		vx = cos(dribble_time * freq) * intensity
		vertical_offset = abs(sin(dribble_time * freq * 0.5)) * bounce_height
	
		 # Play rolling animation with speed scaling
		animation_player.play("roll")
		animation_player.speed_scale = 1.0 + speed_factor * 0.5
	
	else :
		dribble_time = 0.0                     # Reset timer when idle
		animation_player.play("idle")
		animation_player.speed_scale = 1.0
	
	# Update ball position relative to carrier
	ball.position = carrier.position + Vector2(base_x + vx, OFFSET_FROM_PLAYER.y - vertical_offset)
	
