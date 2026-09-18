class_name AIBehaviorFactory

## Ten playing positions, four behaviours. The position picks which class
## drives the player; how far they range from their anchor and whether they
## hold a touchline comes from the Positions table, not from a subclass per
## position.
var groups: Dictionary

func _init() -> void:
	groups = {
		Positions.Group.GOALIE: GoalieAI,
		Positions.Group.DEFENSE: DefenderAI,
		Positions.Group.MIDFIELD: MidfielderAI,
		Positions.Group.OFFENSE: ForwardAI,
	}

func get_role_ai(role: Positions.Role) -> RoleAI:
	var group := Positions.group(role)
	assert(groups.has(group), "behaviour group doesn't exist!")
	return groups.get(group).new()
