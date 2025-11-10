class_name PlayerStatePreppingShot
extends PlayerState

const DURATION_MAX_BONUS := 1000.0
const EASE_REWARD_FACTOR := 2.0
var time_start_shot := Time.get_ticks_msec()

func _enter_tree() -> void:
	animation_player.play("prep_kick")
	player.velocity = Vector2.ZERO
	time_start_shot = Time.get_ticks_msec()

func _process(_delta: float) -> void:
	var bonus = EASE_REWARD_FACTOR
	var shot_power = player.power * (1 + bonus)
	print(shot_power)
	var context_state_data = PlayerStateData.build().set_shot_power(shot_power).set_shot_direction(player.heading) 
	transition_state(Player.State.SHOOTING, context_state_data)
