class_name PlayerStateData

var shot_direction : Vector2
var shot_power : float
var hurt_direction : Vector2
## Engine-v2 passes carry their own target (PlayerBrain decides it); v1 leaves
## has_pass_target false and PlayerStatePassing picks one itself.
var has_pass_target := false
## Intended receiver, or null for a pass into space.
var pass_receiver : Player = null
## Where to kick it. For a pass to feet (pass_to_feet) it's re-led at release
## from the receiver's movement during the wind-up.
var pass_destination := Vector2.ZERO
var pass_to_feet := true

static func build() -> PlayerStateData:
	return PlayerStateData.new()

func set_pass_target(receiver: Player, destination: Vector2, to_feet: bool) -> PlayerStateData:
	has_pass_target = true
	pass_receiver = receiver
	pass_destination = destination
	pass_to_feet = to_feet
	return self

func set_shot_direction(direction: Vector2) -> PlayerStateData:
	shot_direction = direction
	return self
	
func set_shot_power(power: float) -> PlayerStateData:
	shot_power = power
	return self

func set_hurt_direction(direction : Vector2) -> PlayerStateData:
	hurt_direction = direction
	return self
