class_name BallStateFactory

var states : Dictionary

func _init() -> void:
	states = {
		Ball.State.CARRIED : BallStateCarried,
		Ball.State.SHOT : BallStateShot,
		Ball.State.FREEFORM : BallStateFreeform
	}
	
func get_fresh_state(state: Ball.State) -> BallState:
	assert(states.has(state), "Ball doesn't have state: " + str(state))
	return states.get(state).new()
	
