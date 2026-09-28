class_name MatchContext
extends Node

## The shared world model every v2 brain reads (docs/match-engine-v2.md
## Phase 3). It decides nothing: it maintains the pitch-control surface
## (staggered over frames), answers space/value queries, and draws the
## analytics debug overlays. Created by ActorsContainer when any side runs
## the v2 AI or an analytics overlay is on — v1-only matches skip its cost.

## A full pitch-control refresh is spread over this many frames (20 Hz at 60fps).
const FRAMES_PER_REFRESH := 3

var actors: ActorsContainer = null
var ball: Ball = null
var control := PitchControlGrid.new()
## Microseconds spent in the most recent _process — for the Phase 9 budget.
var last_update_usec := 0

## The most recent pass kicked: {"passer", "receiver", "left": bool, "time": s},
## or empty. Cleared when anyone gains possession or play restarts.
var last_pass := {}
## Refreshed by refresh_tactical() at the team-brain tick rate: where the loose
## ball is going, and each side's fastest player to it.
var ball_path : BallPredictor.BallPath = null
var first_left := {"player": null, "time": INF}
var first_right := {"player": null, "time": INF}

var world: MatchWorld = null

func setup(p_actors: ActorsContainer) -> void:
	actors = p_actors
	ball = p_actors.ball
	world = p_actors.get_parent() as MatchWorld

## The taker of the current set piece, from the award until he plays the ball
## (pass/shot) or loses it. Play technically resumes the instant he touches
## the ball, but the delivery comes a moment later — keeping the set-piece
## shape until then stops the attackers leaving the box before the corner is
## even taken (the probe measured 0.8-1.8 of them left at the kick otherwise).
var set_piece_taker : Player = null

## True while a set piece is being organised or is about to be delivered (not
## goal kicks — the keeper restarts those straight from his hands).
func restart_active() -> bool:
	if world == null or world.restart_kind == Restart.Kind.GOAL_KICK or set_piece_taker == null:
		return false
	if world.state == MatchWorld.MatchState.RESTART:
		return true
	return world.state == MatchWorld.MatchState.IN_PLAY and ball.carrier == set_piece_taker

func _ready() -> void:
	control.update_all(actors.left_team, actors.right_team)
	_update_potential()
	GameEvents.pass_attempted.connect(_on_pass_attempted)
	GameEvents.possession_gained.connect(_on_possession_gained)
	GameEvents.restart_awarded.connect(_on_restart)
	GameEvents.team_reset.connect(_clear_pass)
	GameEvents.shot_taken.connect(_on_shot)
	refresh_tactical()

func _exit_tree() -> void:
	for pair in [
		[GameEvents.pass_attempted, _on_pass_attempted],
		[GameEvents.possession_gained, _on_possession_gained],
		[GameEvents.restart_awarded, _on_restart],
		[GameEvents.team_reset, _clear_pass],
		[GameEvents.shot_taken, _on_shot],
	]:
		if pair[0].is_connected(pair[1]):
			pair[0].disconnect(pair[1])

func _on_pass_attempted(passer: Player, receiver: Player, _dest: Vector2) -> void:
	last_pass = {"passer": passer, "receiver": receiver, "left": passer.is_left_team, "time": MatchClock.now()}
	set_piece_taker = null

func _on_possession_gained(p: Player) -> void:
	_clear_pass()
	if p != set_piece_taker:
		set_piece_taker = null

func _on_restart(_kind: int, _team: String, _spot: Vector2) -> void:
	_clear_pass()
	set_piece_taker = world.restart_taker if world != null else null

func _on_shot(_shooter: Player, _origin: Vector2) -> void:
	set_piece_taker = null

func _clear_pass() -> void:
	last_pass = {}

## Called once per team-brain tick (ActorsContainer) so both teams' brains
## share one ball prediction instead of each recomputing it.
func refresh_tactical() -> void:
	ball_path = BallPredictor.for_ball(ball, 3.0)
	if ball.carrier == null:
		first_left = BallPredictor.first_to_ball(ball_path, active(actors.left_team))
		first_right = BallPredictor.first_to_ball(ball_path, active(actors.right_team))
	else:
		first_left = {"player": null, "time": INF}
		first_right = {"player": null, "time": INF}

## Players currently able to act (not frozen for a restart).
static func active(team: Array) -> Array:
	return team.filter(func(p): return p.process_mode != Node.PROCESS_MODE_DISABLED)

func first_to_ball(team_left: bool) -> Dictionary:
	return first_left if team_left else first_right

## The offside line faced by the side attacking from [param attack_left], as
## a depth in that side's frame (0 own goal → 1 goal attacked).
func offside_depth(attack_left: bool) -> float:
	var defenders := actors.right_team if attack_left else actors.left_team
	var depths := []
	for d in defenders:
		depths.append(PitchSpace.normalised(d.position, attack_left).x)
	return OffsideJudge.offside_line(depths, PitchSpace.normalised(ball.position, attack_left).x)

## Ball prediction / first-to-ball refresh interval (s).
const TACTICAL_REFRESH_S := 0.1
var _next_tactical := 0.0

var _frame := 0

func _process(_delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	var rows_per_frame := ceili(float(PitchControlGrid.ROWS) / FRAMES_PER_REFRESH)
	control.update_rows(rows_per_frame, actors.left_team, actors.right_team)
	_frame += 1
	if _frame % FRAMES_PER_REFRESH == 0:
		_update_potential()
	AIProfile.end("pitch_control", t0)
	if MatchClock.now() >= _next_tactical:
		_next_tactical = MatchClock.now() + TACTICAL_REFRESH_S
		var t1 := AIProfile.begin()
		refresh_tactical()
		AIProfile.end("ball_prediction", t1)
	last_update_usec = Time.get_ticks_usec() - t0
	if DebugDraw.ENABLED:
		_draw_debug()

# ─── Queries ────────────────────────────────────────────────────────────────

## Probability [param team_left]'s side controls world point [param p].
func control_at(p: Vector2, team_left: bool) -> float:
	return control.control_at(p, team_left)

## Expected threat of [param p] for the side attacking from [param team_left].
static func xt_at(p: Vector2, team_left: bool) -> float:
	return XtGrid.at(p, team_left)

## Possession value of standing at [param p] with the ball, for
## [param team_left]: the threat of the spot, weighted by how securely that
## side controls it. The positional currency off-ball positioning trades in.
func value_at(p: Vector2, team_left: bool) -> float:
	return XtGrid.at(p, team_left) * control_at(p, team_left)

# ─── Reachable-value potential ──────────────────────────────────────────────
# xT alone values a spot by its location only; in a team's own half it's
# nearly flat (≈0.004-0.009), so it gives build-up play almost no gradient
# toward progress — the first v2 harness runs circulated the ball in their own
# third and made 2 of 116 decisions in the attacking third. Full EPV
# (Fernández et al.) instead values a spot by what can be DONE from it given
# the space around it. The potential grid approximates that: for every cell,
# the best xT×control reachable within POT_REACH_COLS/ROWS cells, discounted
# by distance. A receiver in a pocket with open grass ahead is then worth far
# more than one with the same xT hemmed in.

const POT_REACH_COLS := 3
const POT_REACH_ROWS := 2
const POT_DECAY_PER_CELL := 0.12

var _xt_left := PackedFloat32Array()
var _xt_right := PackedFloat32Array()
var pot_left := PackedFloat32Array()
var pot_right := PackedFloat32Array()

# ─── Forward (breakaway) potential ──────────────────────────────────────────
# The local potential above only looks ±3 cells around a spot, so a ball
# played into 40m of empty grass behind a high line was valued like any
# midfield spot (through balls scored ~0.01 in the harness, below a sideways
# carry). Dynamic programming over the control grid toward the goal fixes it:
#     fwd[c] = max( xT[c]·ctl[c],  ctl[c] · FWD_DECAY · max(fwd of the 3 cells ahead) )
# i.e. a cell is worth what can be reached from it by carrying on toward goal
# while we keep control of every cell on the way. Space leading to goal now
# carries the goal's value back to where the through ball lands.
const FWD_DECAY := 0.94
var fwd_left := PackedFloat32Array()
var fwd_right := PackedFloat32Array()

func _ensure_xt_cells() -> void:
	if not _xt_left.is_empty():
		return
	var n := control.centres.size()
	_xt_left.resize(n)
	_xt_right.resize(n)
	pot_left.resize(n)
	pot_right.resize(n)
	fwd_left.resize(n)
	fwd_right.resize(n)
	for i in n:
		_xt_left[i] = XtGrid.at(control.centres[i], true)
		_xt_right[i] = XtGrid.at(control.centres[i], false)

func _update_potential() -> void:
	_ensure_xt_cells()
	var cols := PitchControlGrid.COLS
	var rows := PitchControlGrid.ROWS
	for r in rows:
		for c in cols:
			var best_l := 0.0
			var best_r := 0.0
			for dr in range(-POT_REACH_ROWS, POT_REACH_ROWS + 1):
				var rr := r + dr
				if rr < 0 or rr >= rows:
					continue
				for dc in range(-POT_REACH_COLS, POT_REACH_COLS + 1):
					var cc := c + dc
					if cc < 0 or cc >= cols:
						continue
					var j := rr * cols + cc
					var decay := 1.0 - POT_DECAY_PER_CELL * maxf(absf(dr), absf(dc))
					var cl := control.control_left[j]
					best_l = maxf(best_l, _xt_left[j] * cl * decay)
					best_r = maxf(best_r, _xt_right[j] * (1.0 - cl) * decay)
			pot_left[r * cols + c] = best_l
			pot_right[r * cols + c] = best_r
	_update_forward(cols, rows)

## See FWD_DECAY. Left attacks toward col = COLS-1, right toward col 0, so
## each side's DP sweeps from its target goal backwards.
func _update_forward(cols: int, rows: int) -> void:
	for step in cols:
		var c_l := cols - 1 - step   # left team: from the right-hand goal back
		var c_r := step              # right team: from the left-hand goal back
		for r in rows:
			var il := r * cols + c_l
			var ctl_l := control.control_left[il]
			var ahead_l := 0.0
			if c_l + 1 < cols:
				for dr in [-1, 0, 1]:
					var rr : int = r + dr
					if rr >= 0 and rr < rows:
						ahead_l = maxf(ahead_l, fwd_left[rr * cols + c_l + 1])
			fwd_left[il] = maxf(_xt_left[il] * ctl_l, ctl_l * FWD_DECAY * ahead_l)
			var ir := r * cols + c_r
			var ctl_r := 1.0 - control.control_left[ir]
			var ahead_r := 0.0
			if c_r - 1 >= 0:
				for dr in [-1, 0, 1]:
					var rr : int = r + dr
					if rr >= 0 and rr < rows:
						ahead_r = maxf(ahead_r, fwd_right[rr * cols + c_r - 1])
			fwd_right[ir] = maxf(_xt_right[ir] * ctl_r, ctl_r * FWD_DECAY * ahead_r)

## Reachable-value potential at [param p] for [param team_left] (nearest cell).
func potential_at(p: Vector2, team_left: bool) -> float:
	_ensure_xt_cells()
	var n := PitchSpace.absolute_normalised(p)
	var c := clampi(int(n.x * PitchControlGrid.COLS), 0, PitchControlGrid.COLS - 1)
	var r := clampi(int(n.y * PitchControlGrid.ROWS), 0, PitchControlGrid.ROWS - 1)
	var i := r * PitchControlGrid.COLS + c
	return maxf(pot_left[i], fwd_left[i]) if team_left else maxf(pot_right[i], fwd_right[i])

## What having the ball at [param p] is worth to [param team_left] — the
## better of the spot itself (xT, scaled by how securely we'd hold it) and
## what can be reached from it (potential). The single value function the
## on-ball evaluator compares every option with.
func possession_value(p: Vector2, team_left: bool) -> float:
	var sec := 0.6 + 0.4 * control_at(p, team_left)
	return maxf(XtGrid.at(p, team_left) * sec, potential_at(p, team_left))

# ─── Debug overlays ─────────────────────────────────────────────────────────

func _draw_debug() -> void:
	if DebugDraw.SHOW_PITCH_CONTROL:
		var half := Vector2(
			(PitchSpace.RIGHT_BOTTOM_X - PitchSpace.LEFT_BOTTOM_X) / PitchControlGrid.COLS,
			(PitchSpace.BOTTOM_Y - PitchSpace.TOP_Y) / PitchControlGrid.ROWS) * 0.5
		for i in control.centres.size():
			var v := control.control_left[i] * 2.0 - 1.0
			var col := Color(0.2, 0.4, 1.0, absf(v) * 0.35) if v > 0.0 else Color(1.0, 0.2, 0.2, absf(v) * 0.35)
			DebugDraw.rect_filled(Rect2(control.centres[i] - half, half * 2.0), col)
	if DebugDraw.SHOW_XT:
		for i in control.centres.size():
			var xt := XtGrid.at(control.centres[i], true)
			DebugDraw.cross(control.centres[i], Color(1, 1, 0, clampf(xt * 4.0, 0.05, 1.0)), 4.0)
	if DebugDraw.SHOW_BALL_PREDICTION and ball.carrier == null:
		var path := BallPredictor.for_ball(ball)
		for i in range(1, path.size()):
			DebugDraw.line(path.positions[i - 1], path.positions[i], Color(1, 1, 1, 0.8))
	if DebugDraw.SHOW_PASS_FAN and ball.carrier != null:
		var carrier := ball.carrier
		for tm in carrier.get_teammates():
			if tm == carrier:
				continue
			var e := PassModel.evaluate(carrier.position, tm.position, carrier, tm, carrier.get_teammates(), carrier.get_opponents())
			DebugDraw.line(carrier.position, tm.position, Color(1.0 - e.p_success, e.p_success, 0.2, 0.9))
