class_name PassTracer
extends Node

## Diagnostic: follows every pass from kick to whatever ends it, in a live
## match, to answer "why do long passes fall short?" (the long-running
## lofted-pass bug — docs/match-engine-v2.md Findings #2 and #5).
## Enabled in the batch harness with BATCH_PASSTRACE=1.
##
## Per pass: intended distance, where it ended (collected by the intended
## receiver / another teammate / an opponent, went out, or still loose),
## how far the ball actually got as a fraction of the intended distance,
## the ball's height at the moment of collection, and — for lofted passes —
## whether it was collected BEFORE its first landing (i.e. plucked out of the
## air mid-flight).

const LOFT_PX := Ball.DISTANCE_HIGH_PASS

var _world : MatchWorld = null
var _ball : Ball = null
var _cur := {}          # the pass in flight
var passes : Array = []  # finished records

func setup(world: MatchWorld) -> void:
	_world = world
	_ball = world.actors_container.ball
	GameEvents.pass_attempted.connect(_on_pass)
	GameEvents.possession_gained.connect(_on_possession)
	GameEvents.restart_awarded.connect(_on_restart)
	GameEvents.heavy_touch.connect(_on_heavy_touch)

func _exit_tree() -> void:
	for pair in [[GameEvents.pass_attempted, _on_pass], [GameEvents.possession_gained, _on_possession],
			[GameEvents.restart_awarded, _on_restart], [GameEvents.heavy_touch, _on_heavy_touch]]:
		if pair[0].is_connected(pair[1]):
			pair[0].disconnect(pair[1])

func _on_pass(passer: Player, receiver: Player, dest: Vector2) -> void:
	_close("superseded", null)
	if receiver == null:
		return
	var predicted := -1.0
	if passer.brain != null:
		predicted = passer.brain.last_pass_p
		passer.brain.last_pass_p = -1.0
	_cur = {
		"predicted": predicted,
		"passer": passer, "receiver": receiver, "origin": passer.position, "dest": dest,
		"dist": passer.position.distance_to(dest), "t0": MatchClock.now(),
		"max_h": 0.0, "landed": false, "was_air": false,
	}

func _physics_process(_delta: float) -> void:
	if _cur.is_empty():
		return
	_cur["max_h"] = maxf(_cur["max_h"], _ball.height)
	if _ball.height > 0.0:
		_cur["was_air"] = true
	elif _cur["was_air"]:
		_cur["landed"] = true

func _on_heavy_touch(_p: Player) -> void:
	if not _cur.is_empty():
		_cur["fumbled"] = true

func _on_possession(p: Player) -> void:
	if _cur.is_empty():
		return
	var who := "receiver" if p == _cur["receiver"] else ("teammate" if p.is_left_team == _cur["passer"].is_left_team else "opponent")
	if p == _cur["passer"]:
		who = "passer"
	_close(who, p)

func _on_restart(_kind: int, _team: String, _spot: Vector2) -> void:
	_close("out_or_stoppage", null)

func _close(outcome: String, collector: Player) -> void:
	if _cur.is_empty():
		return
	var origin : Vector2 = _cur["origin"]
	var dest : Vector2 = _cur["dest"]
	var dir := origin.direction_to(dest)
	var along := (_ball.position - origin).dot(dir)  # how far along the intended line it got
	passes.append({
		"lofted": _cur["dist"] > LOFT_PX, "dist": _cur["dist"], "outcome": outcome,
		"reach": along / maxf(_cur["dist"], 1.0), "height": _ball.height,
		"in_air_before_landing": _cur["was_air"] and not _cur["landed"],
		"time": MatchClock.now() - _cur["t0"], "max_h": _cur["max_h"], "fumbled": _cur.get("fumbled", false),
		"predicted": _cur["predicted"],
		"collector_dist_to_dest": collector.position.distance_to(dest) if collector != null else -1.0,
	})
	_cur = {}

## Aggregates [param all] (records from any number of matches) into a table.
static func summarize(all: Array) -> String:
	var lines := []
	for lofted in [false, true]:
		var subset := all.filter(func(r): return r["lofted"] == lofted and r["outcome"] != "superseded")
		if subset.is_empty():
			continue
		var by := {}
		var reach_sum := 0.0
		var air := 0
		var h_sum := 0.0
		var fumbles := 0
		for r in subset:
			if r.get("fumbled", false):
				fumbles += 1
			by[r["outcome"]] = by.get(r["outcome"], 0) + 1
			reach_sum += r["reach"]
			h_sum += r["height"]
			if r["in_air_before_landing"]:
				air += 1
		var outcomes := []
		for k in by:
			outcomes.append("%s %d%%" % [k, roundi(100.0 * by[k] / subset.size())])
		lines.append("%s passes: n=%d  mean reach %.0f%% of intended  collected mid-air before 1st landing %d%%  fumbled %d%%  mean height at end %.1f  | %s" % [
			"LOFTED" if lofted else "GROUND", subset.size(), 100.0 * reach_sum / subset.size(),
			roundi(100.0 * air / subset.size()), roundi(100.0 * fumbles / subset.size()), h_sum / subset.size(), ", ".join(outcomes)])
		# Reach histogram for the ones that did NOT reach the receiver.
		var short_hist := [0, 0, 0, 0, 0]
		for r in subset:
			if r["outcome"] != "receiver":
				short_hist[clampi(int(r["reach"] * 5.0), 0, 4)] += 1
		lines.append("    non-receiver endings by reach (0-20/20-40/40-60/60-80/80+%%): %s" % str(short_hist))
	# Calibration: the pass model's predicted success vs what happened (kept
	# by the passing side = receiver or another teammate).
	var buckets := [[0.0, 0.5], [0.5, 0.7], [0.7, 0.85], [0.85, 0.95], [0.95, 1.01]]
	var cal := []
	for bk in buckets:
		var n := 0
		var kept := 0
		var pred_sum := 0.0
		for r in all:
			var p : float = r.get("predicted", -1.0)
			if p < 0.0 or r["outcome"] == "superseded" or p < bk[0] or p >= bk[1]:
				continue
			n += 1
			pred_sum += p
			if r["outcome"] in ["receiver", "teammate"]:
				kept += 1
		if n > 0:
			cal.append("pred %.2f→actual %.2f (n=%d)" % [pred_sum / n, float(kept) / n, n])
	lines.append("CALIBRATION (v2 passes): " + "  ".join(cal))
	return "\n".join(lines)
