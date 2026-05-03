class_name AIBehaviorFactory

var roles: Dictionary

func _init() -> void:
	roles = {
		Player.Role.DEFENSE: DefenderBehavior,
		Player.Role.GOALIE: GoalieBehavior,
		Player.Role.MIDFIELD: MidfielderBehavior,
		Player.Role.OFFENSE: ForwardBehavior,
	}

func get_role_behavior(role: Player.Role) -> RoleBehavior:
	assert(roles.has(role), "role doesn't exist!")
	return roles.get(role).new()
