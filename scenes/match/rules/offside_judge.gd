class_name OffsideJudge
extends Node

## Law 11. At the moment a player plays the ball to a teammate (pass_attempted),
## snapshot which of their teammates are in an offside position: in the
## opponents' half, and nearer the opponents' goal line than both the ball
## and the second-last opponent. If one of those players is the next to gain
## possession, it's an offence: indirect free kick to the defending side at
## the offender's position (MatchWorld.award_restart).
##
## Depths use PitchSpace.normalised(), so the offside "line" follows the
## perspective-slanted equal-depth lines rather than a screen-vertical x.
## Not modelled (yet): "interfering with an opponent" without touching the
## ball, and deflection-vs-deliberate-play nuance — any opponent possession
## simply resets the phase.

## Level is onside (Law 11). 0.004 of the pitch length ≈ 0.4m of tolerance so
## sub-pixel "just ahead" positions aren't flagged.
const LEVEL_TOLERANCE := 0.004

var _world: MatchWorld = null
var _flagged: Dictionary = {}  # Player -> true, from the most recent pass
## Set by MatchWorld when play resumes from a throw-in/corner/goal kick —
## the next kick can't produce an offside offence.
var exempt_next_kick := false

func setup(world: MatchWorld) -> void:
	_world = world
	GameEvents.pass_attempted.connect(_on_pass_attempted)
	GameEvents.shot_taken.connect(_on_shot_taken)
	GameEvents.possession_gained.connect(_on_possession_gained)
	GameEvents.restart_awarded.connect(_on_restart_awarded)
	GameEvents.team_reset.connect(clear)

func _exit_tree() -> void:
	for pair in [
		[GameEvents.pass_attempted, _on_pass_attempted],
		[GameEvents.shot_taken, _on_shot_taken],
		[GameEvents.possession_gained, _on_possession_gained],
		[GameEvents.restart_awarded, _on_restart_awarded],
		[GameEvents.team_reset, clear],
	]:
		if pair[0].is_connected(pair[1]):
			pair[0].disconnect(pair[1])

func clear() -> void:
	_flagged.clear()

# ─── Pure geometry (unit-tested in tests/rules_test.gd) ──────────────────────

## The offside line as an attacking-frame depth (0 own goal, 1 opponents'
## goal): the deeper of the ball and the second-last opponent. With fewer
## than two opponents on the pitch the goal line itself stands in.
static func offside_line(defender_depths: Array, ball_depth: float) -> float:
	var sorted := defender_depths.duplicate()
	sorted.sort()
	sorted.reverse()  # deepest (closest to their own goal) first
	var second_last : float = sorted[1] if sorted.size() >= 2 else 1.0
	return maxf(second_last, ball_depth)

static func is_offside_position(attacker_depth: float, line: float) -> bool:
	return attacker_depth > 0.5 and attacker_depth > line + LEVEL_TOLERANCE

# ─── Events ─────────────────────────────────────────────────────────────────

func _on_pass_attempted(passer: Player, _receiver: Player, _destination: Vector2) -> void:
	_flagged.clear()
	if _world.state != MatchWorld.MatchState.IN_PLAY:
		return
	if exempt_next_kick:
		exempt_next_kick = false
		return
	var left := passer.is_left_team
	var depths : Array = []
	for d in passer.get_opponents():
		depths.append(PitchSpace.normalised(d.position, left).x)
	var line := offside_line(depths, PitchSpace.normalised(passer.position, left).x)
	for a in passer.get_teammates():
		if a == passer:
			continue
		if is_offside_position(PitchSpace.normalised(a.position, left).x, line):
			_flagged[a] = true

## A shot isn't a pass to a teammate; a rebound off the keeper to an attacker
## who was ahead is technically still offside, but that nuance is skipped.
func _on_shot_taken(_shooter: Player, _origin: Vector2) -> void:
	_flagged.clear()
	exempt_next_kick = false

func _on_possession_gained(p: Player) -> void:
	var offender := _flagged.has(p)
	_flagged.clear()
	if offender and _world.state == MatchWorld.MatchState.IN_PLAY:
		GameEvents.offside_called.emit(p)
		_world.award_offside(p)

func _on_restart_awarded(_kind: int, _team: String, _spot: Vector2) -> void:
	_flagged.clear()
