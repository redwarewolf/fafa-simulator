class_name PlayerStateCelebrating
extends PlayerState

## Players jump repeatedly after scoring a goal.
## actors_container._on_team_reset() teleports them back to spawn and switches to MOVING.

const AIR_FRICTION   := 60.0
const JUMP_HEIGHT    := 2.0

var _jump_delay := 0  # randomised so players don't all jump in sync
var _time_start := Time.get_ticks_msec()

func _enter_tree() -> void:
	player.velocity = Vector2.ZERO
	player.play_anim("celebrate")
	_jump_delay = randi_range(100, 500)

func _process(delta: float) -> void:
	# Slow down lateral drift
	player.velocity = player.velocity.move_toward(Vector2.ZERO, delta * AIR_FRICTION)
	# Jump once the random delay has elapsed and the player has landed
	if player.height <= 0.0 and Time.get_ticks_msec() - _time_start > _jump_delay:
		player.height = 0.1
		player.height_velocity = JUMP_HEIGHT
		_time_start = Time.get_ticks_msec()
		_jump_delay = randi_range(400, 800)  # pause between jumps
