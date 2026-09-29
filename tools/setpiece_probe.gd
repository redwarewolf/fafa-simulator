extends Node

## Controlled set-piece experiment (docs/match-engine-v2.md, set pieces):
## plays live v2-vs-v2 matches and, every few seconds of open play, awards a
## corner (or a free kick in shooting range) to a random side, then records
## what happens — the "natural" rate of corners is too low to judge the
## routine from full matches alone.
##   <godot_console.exe> --path . --headless --fixed-fps 60 res://tools/setpiece_probe.tscn -- --kind corner --n 40 --seed 1
## Per set piece: set-up time until taken, whether the delivery was lofted,
## players on their box posts at the kick, then the outcome within 10s
## (shot + xG, goal, cleared/lost).

const WORLD_SCENE := preload("res://scenes/world/world.tscn")
const WINDOW_S := 10.0

var _kind := Restart.Kind.CORNER
var _n := 40
var _seed := 1
var _world : MatchWorld = null
var _cur := {}
var _results : Array = []

func _ready() -> void:
	var raw := OS.get_cmdline_user_args()
	for i in range(0, raw.size() - 1, 2):
		match raw[i]:
			"--kind": _kind = Restart.Kind.CORNER if raw[i + 1] == "corner" else Restart.Kind.FREE_KICK
			"--n": _n = int(raw[i + 1])
			"--seed": _seed = int(raw[i + 1])
	MatchConfig.reset_to_defaults()
	MatchConfig.headless = true
	MatchConfig.disable_random_events = true
	MatchConfig.match_duration_override = 100000.0
	MatchConfig.match_seed = _seed
	seed(12345)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var clubs := ClubFactory.generate_ai_clubs("E", 2, [], [], rng)
	DataLoader.clubs.clear()
	for c in clubs:
		DataLoader.clubs[c.id] = c
	GameState.test_match_teams = [clubs[0].team_key, clubs[1].team_key]
	GameEvents.pass_attempted.connect(_on_pass)
	GameEvents.shot_taken.connect(_on_shot)
	GameEvents.team_scored.connect(_on_goal)
	_run.call_deferred()

func _physics_process(_d: float) -> void:
	# pass_attempted fires just BEFORE the kick is applied, so read the ball's
	# lift on the next physics frame.
	if not _cur.is_empty() and _cur.get("delivery", "") == "pending":
		var b := _world.actors_container.ball
		_cur["delivery"] = "lofted" if b.height > 0.0 or b.height_velocity > 0.0 else "ground"

func _on_pass(passer: Player, _r: Player, dest: Vector2) -> void:
	if not _cur.is_empty() and not _cur.has("delivery") and passer == _cur["taker"]:
		_cur["delivery"] = "pending"
		_cur["first_action"] = "pass"
		_cur["taken_after_s"] = MatchClock.now() - float(_cur["t0"])
		_cur["dest_in_box"] = _in_box(dest, passer.is_left_team)
		_cur["attackers_in_box"] = _count_in_box(passer.get_teammates(), passer.is_left_team)
		if _results.size() < 3:
			var parts := []
			for tm: Player in passer.get_teammates():
				if tm.brain != null and tm.brain.job != null:
					var n := PitchSpace.normalised(tm.position, passer.is_left_team)
					var jn := PitchSpace.normalised(tm.brain.job.point, passer.is_left_team)
					parts.append("%s@%.2f,%.2f→%.2f,%.2f" % [Job.NAMES[tm.brain.job.kind], n.x, n.y, jn.x, jn.y])
			print("  kick snapshot: " + "  ".join(parts))
		_cur["defenders_in_box"] = _count_in_box(passer.get_opponents(), passer.is_left_team)

func _on_shot(shooter: Player, origin: Vector2) -> void:
	if not _cur.is_empty() and shooter == _cur.get("taker") and not _cur.has("first_action"):
		_cur["first_action"] = "shot"
	if not _cur.is_empty() and shooter.is_left_team == _cur["left"] and not _cur.has("shot_xg"):
		_cur["shot_xg"] = ShotModel.xg_for_goal(origin, shooter.target_goal)

func _on_goal(team_conceded: String) -> void:
	if not _cur.is_empty():
		var conceded_left := team_conceded == _world.actors_container.team_left
		if conceded_left != _cur["left"]:
			_cur["goal"] = true

static func _in_box(p: Vector2, attack_left: bool) -> bool:
	var n := PitchSpace.normalised(p, attack_left)
	return n.x > 0.84 and absf(n.y - 0.5) < 0.3

static func _count_in_box(team: Array, attack_left: bool) -> int:
	var c := 0
	for p: Player in team:
		if _in_box(p.position, attack_left):
			c += 1
	return c

func _run() -> void:
	_world = WORLD_SCENE.instantiate()
	add_child(_world)
	var ac := _world.actors_container
	for i in _n:
		# Wait for open play.
		var guard := 0
		while _world.state != MatchWorld.MatchState.IN_PLAY and guard < 2000:
			await get_tree().process_frame
			guard += 1
		for f in 90:
			await get_tree().process_frame
		if _world.state != MatchWorld.MatchState.IN_PLAY:
			continue
		var left := MatchRng.randf() < 0.5
		var team := ac.team_left if left else ac.team_right
		var spot : Vector2
		if _kind == Restart.Kind.CORNER:
			var top := MatchRng.randf() < 0.5
			spot = PitchSpace.from_normalised(Vector2(0.988, 0.03 if top else 0.97), left)
		else:
			spot = PitchSpace.from_normalised(Vector2(MatchRng.randf_range(0.7, 0.78), MatchRng.randf_range(0.35, 0.65)), left)
		_cur = {"left": left, "t0": MatchClock.now()}
		_world.award_restart(_kind, team, spot)
		_cur["taker"] = _world.restart_taker
		# The outcome window starts when play resumes (set-up can take up to
		# Restart.setup_time), not at the award.
		var wait := 0
		while _world.state == MatchWorld.MatchState.RESTART and wait < 1200:
			await get_tree().process_frame
			wait += 1
		_cur["setup_s"] = MatchClock.now() - float(_cur["t0"])
		var t_end := MatchClock.now() + WINDOW_S
		var debugged := true
		while MatchClock.now() < t_end and _world.state in [MatchWorld.MatchState.IN_PLAY, MatchWorld.MatchState.RESTART]:
			await get_tree().process_frame
			if not debugged and MatchClock.now() - float(_cur["t0"]) > 2.0:
				debugged = true
				var ctx := ac.match_context
				var tk : Player = _world.restart_taker
				var parts := []
				if tk != null:
					for tm: Player in tk.get_teammates():
						if tm.brain != null and tm.brain.job != null:
							parts.append("%s pm=%d v=%.0f" % [Job.NAMES[tm.brain.job.kind], tm.process_mode, tm.velocity.length()])
				print("  mid-setup: state=%s restart_active=%s  %s" % [MatchWorld.MatchState.keys()[_world.state],
					ctx.restart_active() if ctx != null else "no ctx", " | ".join(parts)])
		_results.append(_cur)
		_cur = {}
	_summarize()
	get_tree().quit(0)

func _summarize() -> void:
	var n := _results.size()
	var lofted := 0
	var taken := 0
	var taken_s := 0.0
	var box_dest := 0
	var att := 0.0
	var dfn := 0.0
	var shots := 0
	var xg := 0.0
	var goals := 0
	var actions := {}
	for r in _results:
		var a : String = r.get("first_action", "none (carried / lost / not taken)")
		actions[a] = actions.get(a, 0) + 1
		if r.has("delivery"):
			taken += 1
			taken_s += r["taken_after_s"]
			lofted += 1 if r["delivery"] == "lofted" else 0
			box_dest += 1 if r["dest_in_box"] else 0
			att += r["attackers_in_box"]
			dfn += r["defenders_in_box"]
		if r.has("shot_xg"):
			shots += 1
			xg += r["shot_xg"]
		if r.get("goal", false):
			goals += 1
	var t := maxi(taken, 1)
	print("\n%s probe: %d awarded, %d taken as a pass (avg %.2fs after award)" % [
		"CORNER" if _kind == Restart.Kind.CORNER else "FREE KICK", n, taken, taken_s / t])
	print("  delivery: %d%% lofted, %d%% aimed into the box; at the kick: %.1f attackers / %.1f defenders in the box" % [
		roundi(100.0 * lofted / t), roundi(100.0 * box_dest / t), att / t, dfn / t])
	var setup_sum := 0.0
	for r in _results:
		setup_sum += float(r.get("setup_s", 0.0))
	print("  set-up time: %.1fs average; taker's first action: %s" % [setup_sum / maxi(n, 1), str(actions)])
	print("  outcome within %ds: shot %d%% (xG %.3f per set piece), goals %d (%.1f%%)" % [
		int(WINDOW_S), roundi(100.0 * shots / maxi(n, 1)), xg / maxi(n, 1), goals, 100.0 * goals / maxi(n, 1)])
