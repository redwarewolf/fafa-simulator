class_name MatchStats
extends Node

## Per-match analytics collector for the headless batch harness
## (tools/batch_match.gd). Listens to the GameEvents match-analytics signals
## and samples team shape at SHAPE_SAMPLE_HZ while the ball is in play, then
## produces a flat, JSON-friendly result via build_result().
##
## Sides are keyed "L"/"R" (Player.is_left_team), not by club name, so A/B
## runs can swap clubs between sides freely.
##
## Match time is compressed (MatchWorld.MATCH_DURATION = 360s stands in for
## 90 minutes), so totals aren't comparable to real matches — the harness
## compares RATES instead (completion %, xG/shot, passes per possession...).
## See docs/match-engine-v2.md Phase 1 and tools/targets.json.

const SHAPE_SAMPLE_HZ := 2.0
## Opta-style progressive pass: the ball ends at least this fraction closer
## to the goal being attacked than it started.
const PROGRESSIVE_FRACTION := 0.25
## PPDA zone: opponent passes in their own first PPDA_ZONE of the pitch vs
## our defensive actions in that same area.
const PPDA_ZONE := 0.6
## Radius (metres) for the bunching index — players besides the carrier and
## the single closest opponent this close to the ball are "bunched".
const BUNCH_RADIUS_M := 8.0

var _world: MatchWorld = null
var _ball: Ball = null
var _shape_timer := 0.0

var _last_possessor: Player = null
var _pending_pass: Dictionary = {}  # side, origin, destination, receiver, in_ppda_zone
var _passes_in_possession := 0
var _possession_lengths: Array[int] = []  # completed passes per possession, both sides pooled

var _s := {}  # "L"/"R" -> Dictionary of counters/accumulators

func setup(world: MatchWorld) -> void:
	_world = world
	_ball = world.actors_container.ball
	for side in ["L", "R"]:
		_s[side] = {
			"possession_s": 0.0,
			"passes": 0, "passes_completed": 0, "passes_progressive": 0,
			"passes_forward": 0, "pass_length_m_sum": 0.0, "passes_intercepted": 0,
			"untargeted_kicks": 0,
			"shots": 0, "xg": 0.0, "shot_dist_m_sum": 0.0,
			"tackles": 0, "tackles_won": 0, "fouls": 0,
			"interceptions": 0,
			"turnovers": 0, "turnovers_def_third": 0, "turnovers_mid_third": 0, "turnovers_att_third": 0,
			"recoveries_att_third": 0,
			"opp_buildup_passes": 0, "high_def_actions": 0,
			"shape_samples_in": 0, "shape_samples_out": 0,
			"length_in_m": 0.0, "width_in_m": 0.0,
			"length_out_m": 0.0, "width_out_m": 0.0,
			"line_height_out_m": 0.0, "compactness_out_m": 0.0,
			"players_behind_ball_out": 0.0,
		}
		for kind_key in Restart.KEYS.values():
			_s[side]["restarts_" + kind_key] = 0
		for g in ["gk", "defense", "midfield", "offense"]:
			_s[side]["turnovers_by_" + g] = 0
	_s["bunching_sum"] = 0.0
	_s["bunching_samples"] = 0
	GameEvents.possession_gained.connect(_on_possession_gained)
	GameEvents.pass_attempted.connect(_on_pass_attempted)
	GameEvents.shot_taken.connect(_on_shot_taken)
	GameEvents.tackle_resolved.connect(_on_tackle_resolved)
	GameEvents.team_reset.connect(_on_restart)
	GameEvents.foul_called.connect(_on_foul_called)
	GameEvents.restart_awarded.connect(_on_restart_awarded)

func _exit_tree() -> void:
	# GameEvents is a long-lived autoload; a batch run instantiates many
	# MatchStats in one process, so disconnect explicitly.
	for sig_and_cb in [
		[GameEvents.possession_gained, _on_possession_gained],
		[GameEvents.pass_attempted, _on_pass_attempted],
		[GameEvents.shot_taken, _on_shot_taken],
		[GameEvents.tackle_resolved, _on_tackle_resolved],
		[GameEvents.team_reset, _on_restart],
		[GameEvents.foul_called, _on_foul_called],
		[GameEvents.restart_awarded, _on_restart_awarded],
	]:
		if sig_and_cb[0].is_connected(sig_and_cb[1]):
			sig_and_cb[0].disconnect(sig_and_cb[1])

static func _side(p: Player) -> String:
	return "L" if p.is_left_team else "R"

static func _other(side: String) -> String:
	return "R" if side == "L" else "L"

func _in_play() -> bool:
	return _world != null and _world.state == MatchWorld.MatchState.IN_PLAY

# ─── Events ─────────────────────────────────────────────────────────────────

func _on_possession_gained(p: Player) -> void:
	if not _in_play() and _world.state not in [MatchWorld.MatchState.KICKOFF, MatchWorld.MatchState.RESTART]:
		return
	var side := _side(p)
	if not _pending_pass.is_empty():
		var ps : Dictionary = _pending_pass
		_pending_pass = {}
		if ps["side"] == side:
			_s[side]["passes_completed"] += 1
			_passes_in_possession += 1
		else:
			_s[ps["side"]]["passes_intercepted"] += 1
			_s[side]["interceptions"] += 1
			if ps["in_ppda_zone"]:
				_s[side]["high_def_actions"] += 1
	if _last_possessor != null and _side(_last_possessor) != side:
		_on_turnover(_side(_last_possessor), side, p.position)
		# Who lost it, by formation group — diagnoses e.g. keeper distribution.
		var group_name : String = "gk" if _last_possessor.role == Positions.Role.GK \
			else String(Positions.Group.keys()[Positions.group(_last_possessor.role)]).to_lower()
		var key := "turnovers_by_" + group_name
		_s[_side(_last_possessor)][key] = _s[_side(_last_possessor)].get(key, 0) + 1
	_last_possessor = p

func _on_turnover(loser: String, gainer: String, where: Vector2) -> void:
	_s[loser]["turnovers"] += 1
	var nx := PitchSpace.normalised(where, loser == "L").x
	if nx < 1.0 / 3.0:
		_s[loser]["turnovers_def_third"] += 1
		_s[gainer]["recoveries_att_third"] += 1
	elif nx < 2.0 / 3.0:
		_s[loser]["turnovers_mid_third"] += 1
	else:
		_s[loser]["turnovers_att_third"] += 1
	_possession_lengths.append(_passes_in_possession)
	_passes_in_possession = 0

func _on_pass_attempted(passer: Player, receiver: Player, destination: Vector2) -> void:
	if not _in_play():
		return
	var side := _side(passer)
	var st : Dictionary = _s[side]
	var in_zone := PitchSpace.normalised(passer.position, passer.is_left_team).x < PPDA_ZONE
	if receiver == null:
		st["untargeted_kicks"] += 1
	else:
		st["passes"] += 1
		st["pass_length_m_sum"] += PitchSpace.distance_m(passer.position, destination)
		var goal := passer.target_goal.get_center_target_position()
		var d0 := PitchSpace.distance_m(passer.position, goal)
		var d1 := PitchSpace.distance_m(destination, goal)
		if d1 <= d0 * (1.0 - PROGRESSIVE_FRACTION):
			st["passes_progressive"] += 1
		if d1 < d0:
			st["passes_forward"] += 1
		if in_zone:
			_s[_other(side)]["opp_buildup_passes"] += 1
	_pending_pass = {"side": side, "in_ppda_zone": in_zone}

func _on_shot_taken(shooter: Player, origin: Vector2) -> void:
	if not _in_play():
		return
	var st : Dictionary = _s[_side(shooter)]
	st["shots"] += 1
	st["xg"] += ShotModel.xg_for_goal(origin, shooter.target_goal)
	st["shot_dist_m_sum"] += PitchSpace.distance_m(origin, shooter.target_goal.get_center_target_position())
	_pending_pass = {}

func _on_tackle_resolved(tackler: Player, carrier: Player, won: bool, foul: bool) -> void:
	var side := _side(tackler)
	_s[side]["tackles"] += 1
	if won:
		_s[side]["tackles_won"] += 1
	if foul:
		_s[side]["fouls"] += 1
	# A tackle on a carrier in their own build-up zone is a high defensive action.
	if PitchSpace.normalised(carrier.position, carrier.is_left_team).x < PPDA_ZONE:
		_s[side]["high_def_actions"] += 1

func _on_restart() -> void:
	_pending_pass = {}

func _on_foul_called(_fouled: Player, _where: Vector2) -> void:
	_on_restart()

## Counted for the side AWARDED the restart ("corners won", "throw-ins",
## "offsides won" = the defending side was awarded the free kick).
func _on_restart_awarded(kind: int, team: String, _spot: Vector2) -> void:
	_on_restart()
	var side := "L" if team == _world.actors_container.team_left else "R"
	var key : String = "restarts_" + Restart.KEYS.get(kind, "other")
	_s[side][key] = _s[side].get(key, 0) + 1

# ─── Sampling ───────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not _in_play():
		return
	if _last_possessor != null:
		_s[_side(_last_possessor)]["possession_s"] += delta
	var ctx := _world.actors_container.match_context
	if ctx != null:
		_s["ctx_usec_sum"] = _s.get("ctx_usec_sum", 0) + ctx.last_update_usec
		_s["ctx_usec_max"] = maxi(_s.get("ctx_usec_max", 0), ctx.last_update_usec)
		_s["ctx_frames"] = _s.get("ctx_frames", 0) + 1
	_shape_timer += delta
	if _shape_timer >= 1.0 / SHAPE_SAMPLE_HZ:
		_shape_timer = 0.0
		_sample_shape()

func _sample_shape() -> void:
	var ac := _world.actors_container
	var possessing := _side(_last_possessor) if _last_possessor != null else ""
	var ball_m := PitchSpace.to_metres(_ball.position)
	var near_ball := 0
	for pair in [["L", ac.left_team], ["R", ac.right_team]]:
		var side : String = pair[0]
		var team : Array = pair[1]
		var pts : Array[Vector2] = []
		var depths : Array[float] = []
		var behind := 0
		var ball_depth := PitchSpace.normalised(_ball.position, side == "L").x
		for p: Player in team:
			if p.role == Positions.Role.GK:
				continue
			var m := PitchSpace.to_metres(p.position)
			pts.append(m)
			var nx := PitchSpace.normalised(p.position, side == "L").x
			depths.append(nx)
			if nx < ball_depth:
				behind += 1
			if m.distance_to(ball_m) < BUNCH_RADIUS_M:
				near_ball += 1
		if pts.is_empty():
			continue
		var min_v := pts[0]
		var max_v := pts[0]
		var centroid := Vector2.ZERO
		for m in pts:
			min_v = min_v.min(m)
			max_v = max_v.max(m)
			centroid += m
		centroid /= pts.size()
		var spread := 0.0
		for m in pts:
			spread += m.distance_to(centroid)
		spread /= pts.size()
		var st : Dictionary = _s[side]
		if side == possessing:
			st["shape_samples_in"] += 1
			st["length_in_m"] += max_v.x - min_v.x
			st["width_in_m"] += max_v.y - min_v.y
		else:
			st["shape_samples_out"] += 1
			st["length_out_m"] += max_v.x - min_v.x
			st["width_out_m"] += max_v.y - min_v.y
			st["compactness_out_m"] += spread
			st["players_behind_ball_out"] += behind
			# Defensive line height: mean depth of the 4 deepest outfielders
			# (or all of them, for a short-handed side), in metres from own goal.
			depths.sort()
			var n := mini(4, depths.size())
			var sum := 0.0
			for i in n:
				sum += depths[i]
			st["line_height_out_m"] += sum / n * PitchSpace.LENGTH_M
	# Carrier + one challenger near the ball is normal; anything more is bunching.
	_s["bunching_sum"] += maxf(0.0, near_ball - 2)
	_s["bunching_samples"] += 1

# ─── Result ─────────────────────────────────────────────────────────────────

static func _ratio(a: float, b: float) -> float:
	return a / b if b > 0.0 else 0.0

func build_result() -> Dictionary:
	var total_poss : float = _s["L"]["possession_s"] + _s["R"]["possession_s"]
	var out := {
		"score_left": _world.score_left,
		"score_right": _world.score_right,
		"bunching_index": _ratio(_s["bunching_sum"], _s["bunching_samples"]),
		"passes_per_possession": 0.0,
		"possessions_3plus_share": 0.0,
		# Frame-budget telemetry (docs/match-engine-v2.md Phase 9): MatchContext
		# per-frame cost, when one exists.
		"ctx_usec_mean": _ratio(_s.get("ctx_usec_sum", 0), _s.get("ctx_frames", 0)),
		"ctx_usec_max": _s.get("ctx_usec_max", 0),
	}
	if not _possession_lengths.is_empty():
		var sum := 0
		var three := 0
		for n in _possession_lengths:
			sum += n
			if n >= 3:
				three += 1
		out["passes_per_possession"] = float(sum) / _possession_lengths.size()
		out["possessions_3plus_share"] = float(three) / _possession_lengths.size()
	for side in ["L", "R"]:
		var st : Dictionary = _s[side]
		var si : float = maxf(1.0, st["shape_samples_in"])
		var so : float = maxf(1.0, st["shape_samples_out"])
		out[side] = {
			"goals": _world.score_left if side == "L" else _world.score_right,
			"possession_share": _ratio(st["possession_s"], total_poss),
			"passes": st["passes"],
			"pass_completion": _ratio(st["passes_completed"], st["passes"]),
			"progressive_share": _ratio(st["passes_progressive"], st["passes"]),
			"forward_share": _ratio(st["passes_forward"], st["passes"]),
			"avg_pass_length_m": _ratio(st["pass_length_m_sum"], st["passes"]),
			"untargeted_kicks": st["untargeted_kicks"],
			"shots": st["shots"],
			"xg": st["xg"],
			"xg_per_shot": _ratio(st["xg"], st["shots"]),
			"avg_shot_dist_m": _ratio(st["shot_dist_m_sum"], st["shots"]),
			"tackles": st["tackles"],
			"tackle_success": _ratio(st["tackles_won"], st["tackles"]),
			"fouls": st["fouls"],
			"interceptions": st["interceptions"],
			"turnovers": st["turnovers"],
			"turnovers_def_third_share": _ratio(st["turnovers_def_third"], st["turnovers"]),
			"recoveries_att_third": st["recoveries_att_third"],
			"ppda": _ratio(st["opp_buildup_passes"], st["high_def_actions"]),
			"length_in_m": st["length_in_m"] / si,
			"width_in_m": st["width_in_m"] / si,
			"length_out_m": st["length_out_m"] / so,
			"width_out_m": st["width_out_m"] / so,
			"line_height_out_m": st["line_height_out_m"] / so,
			"compactness_out_m": st["compactness_out_m"] / so,
			"players_behind_ball_out": st["players_behind_ball_out"] / so,
			"restarts_free_kick": st["restarts_free_kick"],
			"restarts_offside": st["restarts_offside"],
			"restarts_throw_in": st["restarts_throw_in"],
			"restarts_corner": st["restarts_corner"],
			"restarts_goal_kick": st["restarts_goal_kick"],
			"turnovers_by_gk": st["turnovers_by_gk"],
			"turnovers_by_defense": st["turnovers_by_defense"],
			"turnovers_by_midfield": st["turnovers_by_midfield"],
			"turnovers_by_offense": st["turnovers_by_offense"],
			# Raw numerators/denominators, so the harness can pool rates
			# across matches (sum/sum) instead of averaging per-match ratios —
			# a match with zero shots would otherwise drag xg_per_shot to 0.
			"raw": {
				"possession_s": st["possession_s"], "possession_total_s": total_poss,
				"passes": st["passes"], "passes_completed": st["passes_completed"],
				"passes_progressive": st["passes_progressive"], "passes_forward": st["passes_forward"],
				"pass_length_m_sum": st["pass_length_m_sum"],
				"shots": st["shots"], "xg": st["xg"], "shot_dist_m_sum": st["shot_dist_m_sum"],
				"tackles": st["tackles"], "tackles_won": st["tackles_won"],
				"turnovers": st["turnovers"], "turnovers_def_third": st["turnovers_def_third"],
				"opp_buildup_passes": st["opp_buildup_passes"], "high_def_actions": st["high_def_actions"],
			},
		}
	return out

## Rate metrics recomputed from pooled raw counts: name -> [numerator, denominator].
const POOLED_RATES := {
	"possession_share": ["possession_s", "possession_total_s"],
	"pass_completion": ["passes_completed", "passes"],
	"progressive_share": ["passes_progressive", "passes"],
	"forward_share": ["passes_forward", "passes"],
	"avg_pass_length_m": ["pass_length_m_sum", "passes"],
	"xg_per_shot": ["xg", "shots"],
	"avg_shot_dist_m": ["shot_dist_m_sum", "shots"],
	"tackle_success": ["tackles_won", "tackles"],
	"turnovers_def_third_share": ["turnovers_def_third", "turnovers"],
	"ppda": ["opp_buildup_passes", "high_def_actions"],
}
