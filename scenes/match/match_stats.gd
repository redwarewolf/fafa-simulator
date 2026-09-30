extends Node

## Live team statistics for one match, built purely from the GameEvents bus —
## nothing in the engine has to know it exists. Feeds the HUD's stats panel
## and the post-match summary (possession, shots, shots on target, corners,
## fouls, offsides) plus a short event log (goals, saves, half time).
##
## Attribution, per signal:
##   possession_gained  — the carrier's team holds the ball until someone else
##                        gains it; match time accrues to the holder.
##   shot_taken         — a shot for the shooter's team.
##   keeper_decision    — a save counts as a shot on target for the other team
##                        (a missed save ends in a goal, counted there instead).
##   score_changed      — whichever side's score rose: on target + goal.
##   restart_awarded    — corner for the awarded team; a free kick is a foul
##                        by, and an offside against, the other team.

var team_left := ""
var team_right := ""

var possession := {}
var shots := {}
var on_target := {}
var corners := {}
var fouls := {}
var offsides := {}

## [{minute, kind, text, team}] — kind is "goal", "save" or "half".
var events : Array = []

var _world : Node = null
var _holder := ""
var _last_elapsed := 0.0
var _score_left := 0
var _score_right := 0

func setup(world: Node, left: String, right: String) -> void:
	_world = world
	team_left = left
	team_right = right
	for d in [possession, shots, on_target, corners, fouls, offsides]:
		d[left] = 0.0 if d == possession else 0
		d[right] = 0.0 if d == possession else 0
	GameEvents.possession_gained.connect(_on_possession_gained)
	GameEvents.match_time_updated.connect(_on_time)
	GameEvents.shot_taken.connect(_on_shot)
	GameEvents.keeper_decision.connect(_on_keeper_decision)
	GameEvents.score_changed.connect(_on_score_changed)
	GameEvents.restart_awarded.connect(_on_restart)
	GameEvents.half_time.connect(_on_half_time)
	GameEvents.substitution_made.connect(_on_substitution)

func other(team: String) -> String:
	return team_right if team == team_left else team_left

## Share of tracked possession time, 0-100 (50 before anyone has the ball).
func possession_pct(team: String) -> int:
	var total : float = possession[team_left] + possession[team_right]
	if total <= 0.0:
		return 50
	return roundi(possession[team] / total * 100.0)

## [[label, own, opp], ...] from [param own]'s point of view — the rows both
## the HUD panel and MatchSummaryPopup print.
func rows(own: String) -> Array:
	var opp := other(own)
	return [
		["Posesión", "%d%%" % possession_pct(own), "%d%%" % possession_pct(opp)],
		["Remates", str(shots[own]), str(shots[opp])],
		["Al arco", str(on_target[own]), str(on_target[opp])],
		["Córners", str(corners[own]), str(corners[opp])],
		["Faltas", str(fouls[own]), str(fouls[opp])],
		["Fuera de juego", str(offsides[own]), str(offsides[opp])],
	]

func _minute() -> int:
	return _world.game_minute() if _world != null and _world.has_method("game_minute") else 0

func _log(kind: String, text: String, team: String) -> void:
	events.append({"minute": _minute(), "kind": kind, "text": text, "team": team})

func _on_possession_gained(player: Player) -> void:
	if player != null and possession.has(player.team):
		_holder = player.team

func _on_time(elapsed: float) -> void:
	if possession.has(_holder) and elapsed > _last_elapsed:
		possession[_holder] += elapsed - _last_elapsed
	_last_elapsed = elapsed

func _on_shot(shooter: Player, _origin: Vector2) -> void:
	if shooter != null and shots.has(shooter.team):
		shots[shooter.team] += 1

func _on_keeper_decision(keeper: Player, _p_save: float, save: bool) -> void:
	if not save or keeper == null or not on_target.has(keeper.team):
		return
	on_target[other(keeper.team)] += 1
	_log("save", tr("Atajada de %s") % keeper.full_name, keeper.team)

## score_changed only fires for goals the world accepted (team_scored also
## fires during celebrations/resets, which MatchWorld ignores), so the side
## whose score went up is the scorer.
func _on_score_changed() -> void:
	var scorer_team := ""
	if _world.score_left > _score_left:
		scorer_team = team_left
	elif _world.score_right > _score_right:
		scorer_team = team_right
	_score_left = _world.score_left
	_score_right = _world.score_right
	if scorer_team == "":
		return
	on_target[scorer_team] += 1
	var scorer : String = _world.get("_last_ball_carrier") if _world != null else ""
	_log("goal", tr("GOL — %s") % scorer if scorer != "" else tr("GOL"), scorer_team)

func _on_restart(kind: int, team: String, _spot: Vector2) -> void:
	if not corners.has(team):
		return
	match kind:
		Restart.Kind.CORNER:
			corners[team] += 1
		Restart.Kind.FREE_KICK:
			fouls[other(team)] += 1
		Restart.Kind.OFFSIDE:
			offsides[other(team)] += 1

func _on_half_time() -> void:
	_log("half", tr("Entretiempo"), "")

func _on_substitution(team: String, off_name: String, on_name: String) -> void:
	_log("sub", tr("Cambio: entra %s, sale %s") % [on_name, off_name], team)
