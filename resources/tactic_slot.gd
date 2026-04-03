class_name TacticSlot
extends Resource

## One position slot in a tactic formation.
## position  – half-field normalized coords (x: goal→halfway, y: top→bottom)
## player    – assigned PlayerResource, null if unassigned

@export var position : Vector2 = Vector2.ZERO
@export var player   : PlayerResource = null

func _init(pos: Vector2 = Vector2.ZERO, p: PlayerResource = null) -> void:
	position = pos
	player   = p

func is_assigned() -> bool:
	return player != null

func clear() -> void:
	player = null
