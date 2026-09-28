class_name PlayerStateChestControl
extends PlayerState

const DURATION_CONTROL := 500

var time_since_control := MatchClock.now_ms()

func _enter_tree() -> void:
	player.play_anim("chest_control")
	player.velocity = Vector2.ZERO	
	time_since_control = MatchClock.now_ms()
	
func _process(_delta: float) -> void:
	if MatchClock.now_ms() - time_since_control > DURATION_CONTROL:
		transition_state(Player.State.MOVING)
