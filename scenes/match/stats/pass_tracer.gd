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
	var windup := -1.0
	var decided_band := ""
	var kind := ""
	if passer.brain != null:
		predicted = passer.brain.last_pass_p
		windup = MatchClock.now() - passer.brain.last_pass_decided_t if passer.brain.last_pass_decided_t >= 0.0 else -1.0
		decided_band = passer.brain.last_pass_band
		kind = passer.brain.last_pass_kind
		passer.brain.last_pass_decided_t = -1.0
		passer.brain.last_pass_p = -1.0
	_cur = {
		"predicted": predicted,
		"passer": passer, "receiver": receiver, "origin": passer.position, "dest": dest,
		"dist": passer.position.distance_to(dest), "t0": MatchClock.now(),
		"max_h": 0.0, "landed": false, "was_air": false,
		"opp_near_dest_m": _nearest_opp_m(passer, dest),
		"band": OnBallEvaluator.pressure_band(passer), "decided_band": decided_band, "windup": windup, "kind": kind,
		"fwd_m": (PitchSpace.normalised(dest, passer.is_left_team).x - PitchSpace.normalised(passer.position, passer.is_left_team).x) * 105.0,
		"to_feet": receiver.position.distance_to(dest) < 40.0,
	}

func _physics_process(_delta: float) -> void:
	if _cur.is_empty():
		return
	_cur["max_h"] = maxf(_cur["max_h"], _ball.height)
	var rcv : Player = _cur["receiver"]
	if OS.get_environment("BATCH_PASSTRACE") == "2" and _ball.carrier == null and rcv.position.distance_to(_ball.position) < 30.0 and Engine.get_physics_frames() % 3 == 0:
		print("DBG t=%.2f d=%.1f rel=%s ballv=%.0f h=%.1f rcv_v=%s state=%s job=%s tgt=%s can=%s cd=%s" % [MatchClock.now() - _cur["t0"], rcv.position.distance_to(_ball.position), str(_ball.position - rcv.position), _ball.velocity.length(), _ball.height, str(rcv.velocity.round()), Player.State.keys()[rcv._current_state_type], Job.Kind.keys()[rcv.brain.job.kind] if rcv.brain != null and rcv.brain.job != null else "-", str((rcv.brain._target - rcv.position).round()) if rcv.brain != null else "-", rcv.can_carry_ball(), _ball.is_kick_cooldown(rcv)])
	var dd := rcv.position.distance_to(_ball.position)
	if dd < _cur.get("rcv_min_px", INF):
		_cur["rcv_min_px"] = dd
		_cur["rcv_min_t"] = MatchClock.now() - _cur["t0"]
		_cur["rcv_min_state"] = Player.State.keys()[rcv._current_state_type] if "_current_state_type" in rcv else "?"
		_cur["rcv_min_job"] = Job.Kind.keys()[rcv.brain.job.kind] if rcv.brain != null and rcv.brain.job != null else "-"
		_cur["rcv_min_ball_h"] = _ball.height
		_cur["rcv_min_ball_v"] = _ball.velocity.length()
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
		"predicted": _cur["predicted"], "opp_near_dest_m": _cur["opp_near_dest_m"],
		"rcv_min_px": _cur.get("rcv_min_px", -1.0), "rcv_min_t": _cur.get("rcv_min_t", -1.0), "rcv_min_state": _cur.get("rcv_min_state", "?"),
		"rcv_min_job": _cur.get("rcv_min_job", "?"), "rcv_min_ball_h": _cur.get("rcv_min_ball_h", 0.0), "rcv_min_ball_v": _cur.get("rcv_min_ball_v", 0.0),
		"to_feet": _cur["to_feet"], "rcv_state_end": Player.State.keys()[_cur["receiver"]._current_state_type],
		"band": _cur["band"], "decided_band": _cur["decided_band"], "windup": _cur["windup"], "fwd_m": _cur["fwd_m"], "pkind": _cur["kind"],
		"collector_to_path_px": _dist_to_segment(collector.position, origin, dest) if collector != null else -1.0,
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

static func _nearest_opp_m(passer: Player, at: Vector2) -> float:
	var best := INF
	for o: Player in passer.get_opponents():
		best = minf(best, PitchSpace.distance_m(o.position, at))
	return best

static func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	return p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))

## Why "safe" passes (predicted >= [param p_min]) fail: outcome mix and, for
## interceptions, where along the path and how close to the line the
## interceptor was, and how free the target spot looked at the kick.
static func summarize_safe_failures(all: Array, p_min: float = 0.9) -> String:
	var safe := all.filter(func(r): return r.get("predicted", -1.0) >= p_min and r["outcome"] != "superseded")
	if safe.is_empty():
		return ""
	var fails := safe.filter(func(r): return r["outcome"] not in ["receiver", "teammate"])
	var by := {}
	var fumbled := 0
	var reach := [0, 0, 0, 0, 0]
	var to_path := [0, 0, 0, 0]  # <15, 15-40, 40-80, 80+ px
	var dist_sum := 0.0
	var opp_sum := 0.0
	var t_sum := 0.0
	for r in fails:
		by[r["outcome"]] = by.get(r["outcome"], 0) + 1
		if r.get("fumbled", false):
			fumbled += 1
		reach[clampi(int(r["reach"] * 5.0), 0, 4)] += 1
		dist_sum += r["dist"]
		opp_sum += minf(r.get("opp_near_dest_m", 0.0), 30.0)
		t_sum += r["time"]
		var cp : float = r.get("collector_to_path_px", -1.0)
		if cp >= 0.0:
			to_path[0 if cp < 15.0 else (1 if cp < 40.0 else (2 if cp < 80.0 else 3))] += 1
	var ok_dist := 0.0
	var ok_opp := 0.0
	var oks := safe.filter(func(r): return r["outcome"] in ["receiver", "teammate"])
	for r in oks:
		ok_dist += r["dist"]
		ok_opp += minf(r.get("opp_near_dest_m", 0.0), 30.0)
	var outs := []
	for k in by:
		outs.append("%s %d" % [k, by[k]])
	var nf := maxi(fails.size(), 1)
	var no := maxi(oks.size(), 1)
	return "SAFE PASSES (pred>=%.2f): n=%d failed=%d (%.1f%%) | %s | fumbled %d | fail reach hist %s | collector-to-path px hist(<15/15-40/40-80/80+) %s | mean dist px fail %.0f vs ok %.0f | opp near dest m fail %.1f vs ok %.1f | fail time %.2fs" % [
		p_min, safe.size(), fails.size(), 100.0 * fails.size() / safe.size(), ", ".join(outs), fumbled,
		str(reach), str(to_path), dist_sum / nf, ok_dist / no, opp_sum / nf, ok_opp / no, t_sum / nf]

## One line per failed "safe" pass — the receiver's closest approach to the ball.
static func list_safe_failures(all: Array, p_min: float = 0.9) -> String:
	var lines := []
	for r in all:
		if r.get("predicted", -1.0) < p_min or r["outcome"] in ["receiver", "teammate", "superseded"]:
			continue
		lines.append("  fail %-16s dist %4.0fpx reach %.2f feet=%s t=%.2fs | rcv closest %.0fpx at %.2fs state %s job %s ball h %.1f v %.0f | end state %s" % [
			r["outcome"], r["dist"], r["reach"], str(r.get("to_feet", "?")), r["time"], r.get("rcv_min_px", -1.0),
			r.get("rcv_min_t", -1.0), r.get("rcv_min_state", "?"), r.get("rcv_min_job", "?"),
			r.get("rcv_min_ball_h", 0.0), r.get("rcv_min_ball_v", 0.0), r.get("rcv_state_end", "?")])
	return "\n".join(lines)

## v2 passes split by the passer's pressure band AT THE KICK ("p" <3m,
## "n" 3-6m, "f" free): predicted vs actual success, how they failed, wind-up
## (decision → kick), pressure that arrived during the wind-up, direction.
static func summarize_by_pressure(all: Array) -> String:
	var lines := []
	for band in ["p", "n", "f"]:
		var sub := all.filter(func(r): return r.get("band", "") == band and r.get("predicted", -1.0) >= 0.0 and r["outcome"] != "superseded")
		if sub.is_empty():
			continue
		var kept := 0
		var pred := 0.0
		var wind := 0.0
		var nw := 0
		var closed := 0
		var fwd := 0.0
		var back := 0
		var fumb := 0
		var by := {}
		for r in sub:
			pred += r["predicted"]
			if r["outcome"] in ["receiver", "teammate"]:
				kept += 1
			else:
				by[r["outcome"]] = by.get(r["outcome"], 0) + 1
			if r.get("windup", -1.0) >= 0.0:
				wind += r["windup"]
				nw += 1
			if r.get("decided_band", "") != band and r.get("decided_band", "") != "":
				closed += 1
			fwd += r.get("fwd_m", 0.0)
			if r.get("fwd_m", 0.0) < -2.0:
				back += 1
			if r.get("fumbled", false):
				fumb += 1
		var outs := []
		for k in by:
			outs.append("%s %d%%" % [k, roundi(100.0 * by[k] / sub.size())])
		lines.append("PRESSURE %s: n=%d pred %.2f → actual %.2f | lost: %s | fumbled %d%% | windup %.2fs, band changed during windup %d%% | fwd %.1fm, backward %d%%" % [
			band, sub.size(), pred / sub.size(), float(kept) / sub.size(), ", ".join(outs),
			roundi(100.0 * fumb / sub.size()), wind / maxi(nw, 1), roundi(100.0 * closed / sub.size()),
			fwd / sub.size(), roundi(100.0 * back / sub.size())])
		# Calibration within the band.
		var cal := []
		for bk in [[0.0, 0.7], [0.7, 0.85], [0.85, 0.95], [0.95, 1.01]]:
			var n := 0
			var k := 0
			var ps := 0.0
			for r in sub:
				if r["predicted"] >= bk[0] and r["predicted"] < bk[1]:
					n += 1
					ps += r["predicted"]
					if r["outcome"] in ["receiver", "teammate"]:
						k += 1
			if n > 0:
				cal.append("%.2f→%.2f (n=%d)" % [ps / n, float(k) / n, n])
		lines.append("    calibration: " + "  ".join(cal))
	return "\n".join(lines)

## v2 pass calibration by the decision's pass type (feet / space = through
## ball / cross) and by length — which passes does the model overrate?
static func summarize_by_kind(all: Array) -> String:
	var lines := []
	var groups := {}
	for r in all:
		if r.get("predicted", -1.0) < 0.0 or r["outcome"] == "superseded" or r.get("pkind", "") == "":
			continue
		var m : float = r["dist"] * PitchSpace.metres_per_px().x
		var len_key := "short<15m" if m < 15.0 else ("mid15-30m" if m < 30.0 else "long>30m")
		for key in [r["pkind"], r["pkind"] + "/" + len_key]:
			if not groups.has(key):
				groups[key] = []
			groups[key].append(r)
	var keys := groups.keys()
	keys.sort()
	for key in keys:
		var sub : Array = groups[key]
		var cal := []
		var kept := 0
		var ps := 0.0
		var out := 0
		for r in sub:
			ps += r["predicted"]
			if r["outcome"] in ["receiver", "teammate"]:
				kept += 1
			elif r["outcome"] == "out_or_stoppage":
				out += 1
		for bk in [[0.0, 0.7], [0.7, 0.85], [0.85, 0.95], [0.95, 1.01]]:
			var n := 0
			var k := 0
			var p := 0.0
			for r in sub:
				if r["predicted"] >= bk[0] and r["predicted"] < bk[1]:
					n += 1
					p += r["predicted"]
					if r["outcome"] in ["receiver", "teammate"]:
						k += 1
			if n > 0:
				cal.append("%.2f→%.2f(%d)" % [p / n, float(k) / n, n])
		lines.append("KIND %-18s n=%4d pred %.2f → actual %.2f  out %d%% | %s" % [key, sub.size(), ps / sub.size(), float(kept) / sub.size(), roundi(100.0 * out / sub.size()), "  ".join(cal)])
	return "\n".join(lines)
