class_name PlayerStateMoving
extends PlayerState

## Idle / walk / run chosen from the player's real ground speed (m/s, in true
## distance — PitchSpace.iso_len), with the cycle's playback rate scaled to
## that speed so the feet keep up with the ground. A fixed-rate run cycle at
## sprint speed looked like skating.
const IDLE_BELOW_MS := 0.3
const RUN_FROM_MS := 2.2
## Ground speed at which each cycle plays at its authored rate (walk: 0.9s
## cycle, run: 0.6s cycle), and the playback clamp.
const WALK_REF_MS := 1.4
const RUN_REF_MS := 4.5
const MIN_PLAYBACK := 0.6
const MAX_PLAYBACK := 1.9

func _process(_delta: float) -> void:
	set_movement_animation()
	player.set_heading()
	ai_behavior.process_ai()
	if player.velocity != Vector2.ZERO:
		teammate_detection_area.rotation = player.velocity.angle()

func set_movement_animation() -> void:
	var ms := PitchSpace.iso_len(player.velocity) * PitchSpace.metres_per_px().x
	if ms < IDLE_BELOW_MS:
		player.play_anim("idle")
	elif ms < RUN_FROM_MS:
		player.play_anim("walk", clampf(ms / WALK_REF_MS, MIN_PLAYBACK, MAX_PLAYBACK))
	else:
		player.play_anim("run", clampf(ms / RUN_REF_MS, MIN_PLAYBACK, MAX_PLAYBACK))

func can_carry_ball() -> bool:
	return player.role != Positions.Role.GK
