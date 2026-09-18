class_name TacticSlot
extends Resource

## One position slot in a tactic formation.
##
## position – FULL-FIELD normalized coords (x: own goal 0 → opponent goal 1,
##            y: top touchline 0 → bottom 1). This is the ANCHOR — where the
##            player wants to be with the shape settled — not where they line
##            up for kickoff; ActorsContainer derives that separately.
## role     – the position this slot asks for. A player whose own position
##            differs is playing out of position; Positions.aptitude() grades it.
## player   – assigned PlayerResource, null if unassigned

@export var position : Vector2 = Vector2.ZERO
@export var role     : Positions.Role = Positions.Role.CM
@export var player   : PlayerResource = null

func _init(pos: Vector2 = Vector2.ZERO, p_role: Positions.Role = Positions.Role.CM, p: PlayerResource = null) -> void:
	position = pos
	role = p_role
	player = p

func is_assigned() -> bool:
	return player != null

func clear() -> void:
	player = null
