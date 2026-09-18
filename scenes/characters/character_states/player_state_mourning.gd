class_name PlayerStateMourning
extends PlayerState

## Players stand still (idle) after conceding a goal.
## actors_container._on_team_reset() teleports them back to spawn and switches to MOVING.

func _enter_tree() -> void:
	player.velocity = Vector2.ZERO
	player.play_anim("mourn")
