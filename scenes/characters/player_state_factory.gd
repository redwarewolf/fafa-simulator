class_name PlayerStateFactory

var states : Dictionary

func _init() -> void:
	states = {
		Player.State.MOVING: PlayerStateMoving,
		Player.State.RECOVERING: PlayerStateRecovering,
		Player.State.TACKLING: PlayerStateTackling,
		Player.State.PREPPING_SHOT: PlayerStatePreppingShot,
		Player.State.SHOOTING: PlayerStateShooting,
		Player.State.PASSING: PlayerStatePassing,
		Player.State.HEADER: PlayerStateHeader,
		Player.State.BICYCLE_KICK: PlayerStateBicycleKick,
		Player.State.VOLLEY_KICK: PlayerStateVolleyKick,
		Player.State.CHEST_CONTROL: PlayerStateChestControl
	}
	
func get_fresh_state(state: Player.State) -> PlayerState:
	assert(states.has(state), "State doesn't exist: " + str(state))
	return states.get(state).new()
