class_name PlayerStateShooting
extends PlayerState

## Convert sho stat (0–100) to actual pixel/s velocity.
## BallStateShot applies NO friction for 1000 ms, then hands off to FREEFORM,
## which decelerates it at Ball.FRICTION_GROUND (150 px/s²) to a stop. Total
## distance a shot can cover before dying is speed×1.0s (hot phase) PLUS
## speed²/(2×150) (the extra ground it covers while decelerating) — NOT just
## speed×1.0s. A max-power shot (274) covers 274+274²/300 ≈ 524px before
## stopping, comfortably past a full-power forward's own 420px effective
## shot range (SHOT_DISTANCE × up to 1.0, see
## OnBallUtility.effective_shot_range) — so the range here is intentionally
## generous. (A prior pass at this file assumed the ball simply stops dead at
## the 1s mark and cranked these way up to compensate, which made shots look
## like unrealistic rockets — reverted.)
## These were retuned down from 150/300 when FRICTION_GROUND dropped 200→150
## (see Ball.FRICTION_GROUND) specifically to keep total shot distance
## unchanged — lower ground friction alone would have let the same speed
## carry noticeably farther, since shots (unlike pass_to()) don't size their
## launch speed off distance-to-target.
## Raised for Phase 8 (docs/match-engine-v2.md Findings #8): at 140-274 px/s
## (~7-13 m/s along the pitch) shots crawled — a keeper that actually reads
## the ball would save nearly everything, and goals came mostly from the old
## keeper's clumsy collider physics. Real shots are ~20-30 m/s; ~21 px/m
## along the length puts that at ~420-620 px/s. The 1s friction-free "hot"
## phase (BallStateShot) now carries a shot well past any goal, which is fine:
## the net or the out-of-play line stops it.
const SHOT_SPEED_MIN := 300.0   # sho=0
const SHOT_SPEED_MAX := 560.0   # sho=100

func _enter_tree() -> void:
	player.play_anim("kick")
	
func on_animation_complete() -> void:
	shoot_ball()
	transition_state(Player.State.MOVING)
	
## The pre-Phase-8 range, selectable with the `shot_speed_legacy` Tuning knob
## so before/after comparisons run from the same code.
const LEGACY_SHOT_SPEED_MIN := 140.0
const LEGACY_SHOT_SPEED_MAX := 274.0

func shoot_ball() -> void:
	# v1 players (no engine-v2 brain) keep the legacy range: their side still
	# uses GoalieAI, which at realistic shot speeds saved under half of what was
	# on target (goals ran at 2.8x xG). v1 is being retired, not re-tuned.
	var legacy := Tuning.b("shot_speed_legacy", false) or player.brain == null
	var lo := LEGACY_SHOT_SPEED_MIN if legacy else SHOT_SPEED_MIN
	var hi := LEGACY_SHOT_SPEED_MAX if legacy else SHOT_SPEED_MAX
	var actual_speed := lo + (state_data.shot_power / 100.0) * (hi - lo)
	GameEvents.shot_taken.emit(player, player.position)
	ball.shoot(state_data.shot_direction * actual_speed)
