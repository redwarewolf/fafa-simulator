class_name PlayerStateRecovering
extends PlayerState

const DURATION_RECOVERY := 300

var time_start_recovery := MatchClock.now_ms()

func _enter_tree() -> void:
	time_start_recovery = MatchClock.now_ms()
	player.velocity = Vector2.ZERO
	player.play_anim("recover")
	
func _process(_delta: float) -> void:
	if MatchClock.now_ms() - time_start_recovery > DURATION_RECOVERY:
		transition_state(Player.State.MOVING)
