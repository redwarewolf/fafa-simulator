extends Node

## Headless batch match runner — the measurement harness for engine v2.
## See docs/match-engine-v2.md Phase 1.
##
## Run (from the repo root):
##   <godot_console.exe> --path . --headless --fixed-fps 60 res://tools/batch_match.tscn -- \
##       --matches 20 --seed 1 --duration 480 --out user://batch.json
##
## --fixed-fps 60 makes every frame advance exactly 1/60s of simulation time
## as fast as the CPU allows (no real-time sync), and is what makes a run
## with the same --seed reproducible.
##
## Two procedurally generated clubs (fixed by --clubs-seed) play every
## match. Sides are balanced in blocks of four: side A alternates
## left/right every match and the club pairing flips every two, so neither
## side of the pitch nor either club's roster biases the A-vs-B numbers
## (with identical AI on both sides, the A-B diffs measure pure noise).
##
## Args:
##   --matches N       number of matches (default 10)
##   --seed S          base match seed; match i uses S+i (default 1)
##   --clubs-seed C    seed for generating the two clubs (default 12345)
##   --duration SEC    match length in sim seconds (default MatchWorld.MATCH_DURATION)
##   --out PATH        JSON output (default user://batch_results.json)
##   --quiet           suppress per-match lines

const WORLD_SCENE := preload("res://scenes/world/world.tscn")
## Hard cap per match in frames, in case a match soft-locks (restart timeouts
## should prevent that, but a harness must never hang).
const MAX_FRAMES_PER_MATCH_FACTOR := 3.0

var _args := {
	"matches": 10, "seed": 1, "clubs-seed": 12345,
	"duration": -1.0,
	"out": "user://batch_results.json", "quiet": false,
}
var _clubs : Array[ClubResource] = []
var _traced_passes : Array = []

func _ready() -> void:
	_parse_args()
	if _args.has("merge"):
		_merge(String(_args["merge"]).split(","))
		return
	MatchConfig.reset_to_defaults()
	MatchConfig.headless = true
	MatchConfig.disable_random_events = true
	MatchConfig.match_duration_override = float(_args["duration"])
	Tuning.set_from_string(String(_args.get("param", "")))
	if not Tuning.overrides.is_empty():
		print("tuning overrides: %s" % str(Tuning.overrides))
	_make_clubs()
	_run.call_deferred()

func _parse_args() -> void:
	var raw := OS.get_cmdline_user_args()
	var i := 0
	while i < raw.size():
		var key := raw[i].trim_prefix("--")
		if key == "quiet":
			_args["quiet"] = true
			i += 1
			continue
		if i + 1 >= raw.size():
			break
		var val := raw[i + 1]
		match key:
			"matches", "seed", "clubs-seed":
				_args[key] = int(val)
			"duration":
				_args[key] = float(val)
			_:
				_args[key] = val
		i += 2

## Same generator Team Creation uses for AI clubs; the global RNG is seeded
## too because SquadGenerator/PlayerResource draw from it directly.
func _make_clubs() -> void:
	seed(int(_args["clubs-seed"]))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_args["clubs-seed"])
	_clubs = ClubFactory.generate_ai_clubs("E", 2, [], [], rng)
	DataLoader.clubs.clear()
	for c in _clubs:
		DataLoader.clubs[c.id] = c

func _run() -> void:
	var results : Array = []
	var n : int = _args["matches"]
	var t0 := Time.get_ticks_msec()
	for i in n:
		var a_left := i % 2 == 0
		var club0_left := (i / 2) % 2 == 0
		var left_club := _clubs[0] if club0_left else _clubs[1]
		var right_club := _clubs[1] if club0_left else _clubs[0]
		MatchConfig.match_seed = int(_args["seed"]) + i
		GameState.test_match_teams = [left_club.team_key, right_club.team_key]
		var mt0 := Time.get_ticks_msec()
		AIProfile.reset()
		var r := await _play_one()
		r["ai_profile"] = AIProfile.report()
		r["ai_counters"] = AIProfile.counters()
		if OS.has_environment("BATCH_COUNTERS"):
			var keys : Array = r["ai_counters"].keys()
			keys.sort()
			for k in keys:
				print("    counter %-40s n=%6d mean=%.4f" % [k, r["ai_counters"][k]["n"], r["ai_counters"][k]["mean"]])
		if not _args["quiet"]:
			for k in r["ai_profile"]:
				var e : Dictionary = r["ai_profile"][k]
				print("    profile %-16s %9.1f ms  %7d calls  %8.1f us/call" % [k, e["ms"], e["calls"], e["us_per_call"]])
		r["index"] = i
		r["seed"] = MatchConfig.match_seed
		r["a_side"] = "L" if a_left else "R"
		r["left_club"] = left_club.display_name
		r["right_club"] = right_club.display_name
		r["wall_s"] = (Time.get_ticks_msec() - mt0) / 1000.0
		results.append(r)
		if not _args["quiet"]:
			print("match %3d seed=%d  %s%s %d - %d %s%s  xG %.2f-%.2f  passes %d/%d  %.1fs wall%s" % [
				i, r["seed"], left_club.display_name, " (A)" if a_left else "", r["score_left"], r["score_right"],
				right_club.display_name, "" if a_left else " (A)", r["L"]["xg"], r["R"]["xg"],
				r["L"]["passes"], r["R"]["passes"], r["wall_s"], "  TIMEOUT" if r.get("timed_out", false) else ""
			])
	var summary := _aggregate(results)
	summary["wall_s_total"] = (Time.get_ticks_msec() - t0) / 1000.0
	_print_summary(summary)
	if not _traced_passes.is_empty():
		print("
══════ PASS TRACE ══════
" + PassTracer.summarize(_traced_passes))
		print(PassTracer.summarize_safe_failures(_traced_passes, 0.9))
		print(PassTracer.summarize_safe_failures(_traced_passes, 0.97))
		print(PassTracer.summarize_by_pressure(_traced_passes))
		print(PassTracer.summarize_by_kind(_traced_passes))
		if OS.get_environment("BATCH_PASSTRACE") == "3":
			print(PassTracer.list_safe_failures(_traced_passes, 0.9))
	_write_json({"args": _args, "summary": summary, "matches": results})
	get_tree().quit(0)

## --merge a.json,b.json,... : combine result files from parallel shards
## (tools/run_parallel.sh) into one summary, without playing any matches.
func _merge(paths: PackedStringArray) -> void:
	var results : Array = []
	for path in paths:
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			printerr("batch_match: cannot read %s" % path)
			continue
		var data = JSON.parse_string(f.get_as_text())
		f.close()
		if data is Dictionary:
			results.append_array(data.get("matches", []))
	var summary := _aggregate(results)
	summary["wall_s_total"] = 0.0
	_print_summary(summary)
	if _args.has("out") and String(_args["out"]) != "user://batch_results.json":
		_write_json({"args": _args, "summary": summary, "matches": results})
	get_tree().quit(0)

func _play_one() -> Dictionary:
	var world : MatchWorld = WORLD_SCENE.instantiate()
	add_child(world)
	var stats := MatchStats.new()
	stats.name = "MatchStats"
	stats.setup(world)
	world.add_child(stats)
	var tracer : PassTracer = null
	if OS.has_environment("BATCH_PASSTRACE"):
		tracer = PassTracer.new()
		tracer.setup(world)
		world.add_child(tracer)
	var duration := world.match_duration()
	var max_frames := int(duration * 60.0 * MAX_FRAMES_PER_MATCH_FACTOR)
	var frames := 0
	while world.state != MatchWorld.MatchState.GAMEOVER and frames < max_frames:
		await get_tree().process_frame
		frames += 1
		if OS.has_environment("BATCH_SHAPES") and frames % 300 == 0:
			var ac := world.actors_container
			for tb in [ac.team_brain_left, ac.team_brain_right]:
				if tb == null or ac.match_context == null:
					continue
				var line := ac.match_context.offside_depth(tb.team_left)
				var ball_n := PitchSpace.normalised(ac.ball.position, tb.team_left)
				var parts := []
				for p in tb.players:
					var j : Job = tb.jobs.get(p)
					var n := PitchSpace.normalised(p.position, tb.team_left)
					var jn := PitchSpace.normalised(j.point, tb.team_left) if j != null else Vector2.ZERO
					parts.append("%s@%.2f,%.2f→%.2f,%.2f" % [Job.NAMES[j.kind] if j != null else "-", n.x, n.y, jn.x, jn.y])
				print("shape t=%.0f %s phase=%s ball=%.2f,%.2f offside=%.2f | %s" % [world.match_time, "L" if tb.team_left else "R",
					TacticalBrain.PHASE_NAMES[tb.tactical.phase], ball_n.x, ball_n.y, line, "  ".join(parts)])
		if OS.has_environment("BATCH_HEARTBEAT") and frames % 120 == 0:
			var b := world.actors_container.ball
			var c := b.carrier
			var job := ""
			if c != null and c.brain != null and c.brain.job != null:
				job = Job.NAMES[c.brain.job.kind]
			print("hb f=%d %s t=%.1f ball=%s v=%.0f carrier=%s(%s,%s,%s) n=%s" % [
				frames, MatchWorld.MatchState.keys()[world.state], world.match_time, b.position.round(), b.velocity.length(),
				c.full_name if c != null else "-", ("L" if c.is_left_team else "R") if c != null else "",
				Player.State.keys()[c._current_state_type] if c != null else "", job,
				PitchSpace.absolute_normalised(b.position).snapped(Vector2(0.01, 0.01))])
			for team in [world.actors_container.left_team, world.actors_container.right_team]:
				var near : Array = team.duplicate()
				near.sort_custom(func(a, bb): return a.position.distance_to(b.position) < bb.position.distance_to(b.position))
				for q in near.slice(0, 2):
					var qj : String = Job.NAMES[q.brain.job.kind] if q.brain != null and q.brain.job != null else "v1"
					print("     %s %-18s d=%5.0f state=%-10s job=%-12s vel=%5.0f pm=%d carry=%s" % [
						"L" if q.is_left_team else "R", q.full_name, q.position.distance_to(b.position),
						Player.State.keys()[q._current_state_type], qj, q.velocity.length(), q.process_mode, q.can_carry_ball()])
	var r := stats.build_result()
	if tracer != null:
		_traced_passes.append_array(tracer.passes)
	r["timed_out"] = world.state != MatchWorld.MatchState.GAMEOVER
	r["sim_frames"] = frames
	world.queue_free()
	await get_tree().process_frame
	return r

# ─── Aggregation ────────────────────────────────────────────────────────────

## Means of every numeric per-side metric, pooled per side label
## ("A"/"B"), plus A's W/D/L record and match-level metrics.
func _aggregate(results: Array) -> Dictionary:
	var sums := {"A": {}, "B": {}}
	var raw := {"A": {}, "B": {}}
	var record := {"A_wins": 0, "draws": 0, "B_wins": 0}
	var match_level := {"bunching_index": 0.0, "passes_per_possession": 0.0, "possessions_3plus_share": 0.0,
		"ctx_usec_mean": 0.0, "ctx_usec_max": 0.0}
	var xg_diffs : Array[float] = []
	var goal_diffs : Array[float] = []
	for r in results:
		var a_side : String = r["a_side"]
		var b_side := "R" if a_side == "L" else "L"
		for pair in [["A", a_side], ["B", b_side]]:
			var side_stats : Dictionary = r[pair[1]]
			for k in side_stats:
				if k == "raw":
					for rk in side_stats["raw"]:
						raw[pair[0]][rk] = raw[pair[0]].get(rk, 0.0) + float(side_stats["raw"][rk])
					continue
				sums[pair[0]][k] = sums[pair[0]].get(k, 0.0) + float(side_stats[k])
		var ga : int = r[a_side]["goals"]
		var gb : int = r[b_side]["goals"]
		xg_diffs.append(float(r[a_side]["xg"]) - float(r[b_side]["xg"]))
		goal_diffs.append(float(ga - gb))
		if ga > gb:
			record["A_wins"] += 1
		elif gb > ga:
			record["B_wins"] += 1
		else:
			record["draws"] += 1
		for k in match_level:
			match_level[k] += float(r[k])
	var n := maxf(1.0, results.size())
	var means := {"A": {}, "B": {}}
	for label in ["A", "B"]:
		for k in sums[label]:
			means[label][k] = sums[label][k] / n
		for k in MatchStats.POOLED_RATES:
			var nd : Array = MatchStats.POOLED_RATES[k]
			var den : float = raw[label].get(nd[1], 0.0)
			means[label][k] = raw[label].get(nd[0], 0.0) / den if den > 0.0 else 0.0
	for k in match_level:
		match_level[k] /= n
	# Pooled AI counters across all matches (restart timeouts, keeper reads...).
	var counters := {}
	for r in results:
		for k in r.get("ai_counters", {}):
			var c : Dictionary = r["ai_counters"][k]
			if not counters.has(k):
				counters[k] = {"n": 0, "sum": 0.0}
			counters[k]["n"] += int(c["n"])
			counters[k]["sum"] += float(c["mean"]) * int(c["n"])
	return {
		"matches": results.size(),
		"counters": counters,
		"xg_diff": _mean_se(xg_diffs),
		"goal_diff": _mean_se(goal_diffs),
		"record": record, "means": means, "match_level": match_level,
		"timeouts": results.filter(func(r): return r.get("timed_out", false)).size(),
	}

## [mean, standard error] — the headline A-vs-B numbers. Goals per side per
## match are ~0.2, so W/D/L over a few dozen matches is mostly noise; the xG
## difference is the steadier signal. A difference is only worth acting on
## when |mean| is well above ~2·SE.
static func _mean_se(values: Array[float]) -> Array:
	var n := values.size()
	if n == 0:
		return [0.0, 0.0]
	var mean := 0.0
	for v in values:
		mean += v
	mean /= n
	var var_sum := 0.0
	for v in values:
		var_sum += (v - mean) * (v - mean)
	var sd := sqrt(var_sum / maxf(n - 1, 1))
	return [mean, sd / sqrt(n)]

const TARGETS_PATH := "res://tools/targets.json"

func _load_targets() -> Dictionary:
	var f := FileAccess.open(TARGETS_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}

## "ok" inside the band, "LOW"/"HIGH" outside it, "" when no band is defined.
static func _band_mark(bands: Dictionary, key: String, value: float) -> String:
	if not bands.has(key):
		return ""
	var band : Array = bands[key]
	if value < float(band[0]):
		return "LOW"
	if value > float(band[1]):
		return "HIGH"
	return "ok"

func _print_summary(s: Dictionary) -> void:
	var targets := _load_targets()
	var side_bands : Dictionary = targets.get("per_side", {})
	var match_bands : Dictionary = targets.get("match_level", {})
	var in_band := 0
	var banded := 0
	print("\n══════ BATCH SUMMARY: %d matches, side A vs side B  (%.1fs wall) ══════" % [
		s["matches"], s["wall_s_total"]])
	print("record: A %d / D %d / B %d   timeouts: %d" % [
		s["record"]["A_wins"], s["record"]["draws"], s["record"]["B_wins"], s["timeouts"]])
	print("xG diff (A-B) per match: %+.3f ± %.3f SE    goal diff: %+.3f ± %.3f SE" % [
		s["xg_diff"][0], s["xg_diff"][1], s["goal_diff"][0], s["goal_diff"][1]])
	for k in s["match_level"]:
		var mark := _band_mark(match_bands, k, s["match_level"][k])
		if mark != "":
			banded += 1
			in_band += 1 if mark == "ok" else 0
		print("  %-28s %8.3f  %s" % [k, s["match_level"][k], mark])
	print("  %-28s %10s      %10s      %s" % ["per-side mean", "A", "B", "target"])
	var keys : Array = s["means"]["A"].keys()
	keys.sort()
	for k in keys:
		var va : float = s["means"]["A"][k]
		var vb : float = s["means"]["B"].get(k, 0.0)
		var ma := _band_mark(side_bands, k, va)
		var mb := _band_mark(side_bands, k, vb)
		if ma != "":
			banded += 2
			in_band += (1 if ma == "ok" else 0) + (1 if mb == "ok" else 0)
		var band_str := "[%s, %s]" % side_bands[k] if side_bands.has(k) else ""
		print("  %-28s %10.3f %-4s %10.3f %-4s %s" % [k, va, ma, vb, mb, band_str])
	print("metrics in target band: %d / %d" % [in_band, banded])
	var ckeys : Array = s.get("counters", {}).keys()
	ckeys.sort()
	for k in ckeys:
		if String(k).begins_with("restart_") or String(k).begins_with("gk_"):
			var c : Dictionary = s["counters"][k]
			print("  counter %-32s n=%6d  mean=%.3f" % [k, c["n"], c["sum"] / maxi(c["n"], 1)])
	s["in_band"] = in_band
	s["banded"] = banded

func _write_json(data: Dictionary) -> void:
	var path : String = _args["out"]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("batch_match: cannot write %s" % path)
		return
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	print("results written to %s" % ProjectSettings.globalize_path(path))
