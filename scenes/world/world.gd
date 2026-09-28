class_name MatchWorld
extends Node2D

## World state machine — orchestrates the full match lifecycle:
## IN_PLAY → SCORED → RESET → KICKOFF → IN_PLAY, or → GAMEOVER when time runs out.
## Any stoppage (foul, offside, ball out of play → throw-in/corner/goal kick)
## detours IN_PLAY → RESTART → IN_PLAY (see award_restart() and Restart.Kind).
## HUD rendering is delegated to MatchHUD (match_hud.tscn).

enum MatchState { IN_PLAY, SCORED, RESET, KICKOFF, GAMEOVER, EVENT, RESTART }

## Total match duration in seconds (6 minutes).
const MATCH_DURATION := 360.0
## How long to stay in SCORED state (celebration pause) before resetting.
const DURATION_SCORED := 3.0
## Safety net only — KICKOFF normally ends the instant the kickoff taker
## touches the ball (see _setup_kickoff()). Guards against a soft lock if no
## taker could be picked, or theirs gets stuck, on the way there.
const KICKOFF_TIMEOUT := 8.0
## Safety net only — RESTART normally ends the instant the taker touches the
## ball. Longer than KICKOFF_TIMEOUT since a fouled player isn't teleported
## (and may still be getting up from HURT first).
const RESTART_TIMEOUT := 12.0
## Where a teleported restart taker is placed relative to the spot — far
## enough that they aren't already overlapping the ball (the ball's pickup
## Area2D only fires on body_entered, so a taker placed ON the ball would
## never pick it up), close enough to take it almost immediately.
const RESTART_TAKER_OFFSET := 26.0
## Goal kick: opponents must be outside the penalty area (~16.5m / 105m).
const PENALTY_AREA_DEPTH := 0.16
## How often (in match seconds) to roll for a random mid-match event.
const EVENT_CHECK_INTERVAL := 60.0
## Roles eligible to take a kickoff — forwards, same as the real game.
const KICKOFF_TAKER_ROLES := [Positions.Role.ST, Positions.Role.LW, Positions.Role.RW]
## The kickoff taker starts this far behind the ball (opposite their attacking
## direction) so they visibly walk up and strike it, rather than starting on it.
const KICKOFF_APPROACH_OFFSET := 40.0

@onready var actors_container   := $ActorsContainer as ActorsContainer
@onready var tribunes           := $Tribunes as Tribunes
@onready var referee            := $ActorsContainer/Referee as Referee
@onready var match_summary_popup := $MatchSummaryPopup as MatchSummaryPopup
@onready var pause_menu         := $PauseMenu as PauseMenu

## Dev "Test Match" fallback (no season fixture): show every stand and a
## mid-range crowd instead of rolling real attendance against a real club.
const DEFAULT_TEST_TRIBUNE_LEVEL := 3
const DEFAULT_TEST_FILL_RATE_RANGE := Vector2(0.5, 0.75)

var state       := MatchState.IN_PLAY
var match_time  := 0.0
var score_left  := 0
var score_right := 0
var _state_timer := 0.0
var _last_ball_carrier := ""
## Per-goal scorer log, populated in _on_team_scored(): {player, team, time_str}.
var _scorers : Array[Dictionary] = []
## At most one random event per match — set the moment one fires.
var _match_event_fired := false
var _next_event_check := EVENT_CHECK_INTERVAL
## Set while state == RESTART — the only player left unfrozen, who takes the
## set piece. See award_restart().
var _restart_taker : Player = null
var _restart_kind : int = Restart.Kind.FREE_KICK
var _restart_spot : Vector2 = Vector2.ZERO
var _offside_judge : OffsideJudge = null## Which team takes the next kickoff — the conceding team after a goal, or a
## random team for the match's opening kickoff. Consumed by _setup_kickoff().
var _kickoff_team : String = ""
## Set while state == KICKOFF — the only player left unfrozen, walking/running
## up to the ball to start play. See _setup_kickoff().
var _kickoff_taker : Player = null

## Parent _enter_tree runs before any child's _enter_tree/_ready — the only
## hook early enough to reset the sim clock and seed MatchRng before
## ActorsContainer spawns players (whose AIBehavior already draws from
## MatchRng in its own _ready). See docs/match-engine-v2.md Phase 1.
func _enter_tree() -> void:
	MatchClock.reset()
	MatchRng.seed_match(MatchConfig.match_seed)
	# Watched matches follow the pause menu's dev AI toggle; the batch harness
	# sets MatchConfig itself.
	if not MatchConfig.headless and GameState != null:
		MatchConfig.ai_version_left = GameState.match_ai_version
		MatchConfig.ai_version_right = GameState.match_ai_version

func _ready() -> void:
	GameEvents.team_scored.connect(_on_team_scored)
	GameEvents.kickoff_ready.connect(_on_kickoff_ready)
	GameEvents.ball_possessed.connect(_on_ball_possessed)
	GameEvents.foul_called.connect(_on_foul_called)
	match_summary_popup.continue_pressed.connect(_on_back_to_hub_pressed)
	_offside_judge = OffsideJudge.new()
	_offside_judge.name = "OffsideJudge"
	_offside_judge.setup(self)
	add_child(_offside_judge)
	if not MatchConfig.headless:
		_setup_stadium()
	# Opening kickoff: a proper restart, same as after a goal, just with a
	# randomly chosen team instead of the conceding one.
	_kickoff_team = MatchRng.pick([actors_container.team_left, actors_container.team_right])
	_transition(MatchState.KICKOFF)

## MATCH_DURATION unless the batch harness overrides it (MatchConfig).
func match_duration() -> float:
	return MatchConfig.match_duration_override if MatchConfig.match_duration_override > 0.0 else MATCH_DURATION

## Rolls this match's attendance once (kickoff_ready fires only after a goal,
## never at match start, so _ready() is the only correct one-time hook) and
## uses it to size and fill the tribunes. The same attendance figure is
## stashed on pending_player_fixture so SeasonManager.report_player_match_result()
## reuses it for gate revenue instead of rolling a second, inconsistent number.
func _setup_stadium() -> void:
	var home_club := _resolve_home_club()
	if home_club == null:
		tribunes.configure_for_tribune_level(DEFAULT_TEST_TRIBUNE_LEVEL)
		tribunes.fill_active_sections(randf_range(
			DEFAULT_TEST_FILL_RATE_RANGE.x, DEFAULT_TEST_FILL_RATE_RANGE.y))
		return

	var attendance := FanEconomy.roll_attendance(home_club)
	if not SeasonManager.pending_player_fixture.is_empty():
		SeasonManager.pending_player_fixture["attendance"] = attendance

	tribunes.configure_for_tribune_level(home_club.upgrades.get("tribune", 0))
	tribunes.fill_active_sections(float(attendance) / float(home_club.get_stadium_capacity()))
	tribunes.set_fan_colors(home_club.primary_color, home_club.secondary_color)

## Home always plays on the left (see actors_container.gd's fixture-team
## setup, which does the same DataLoader.get_club(f["home_id"]) lookup). The
## tribunes always represent the HOME club's stadium; only revenue is gated
## on is_home, in season_manager.gd.
func _resolve_home_club() -> ClubResource:
	var fixture := SeasonManager.pending_player_fixture
	if not fixture.is_empty():
		var home := DataLoader.get_club(fixture.get("home_id", ""))
		if home != null:
			return home
	return GameState.player_club

func _process(delta: float) -> void:
	_poll_scenario_trigger(delta)
	match state:
		MatchState.IN_PLAY:
			match_time += delta
			GameEvents.match_time_updated.emit(match_time)
			if match_time >= match_duration():
				_transition(MatchState.GAMEOVER)
				return
			if not MatchConfig.disable_random_events and not _match_event_fired and match_time >= _next_event_check:
				_next_event_check += EVENT_CHECK_INTERVAL
				_maybe_trigger_match_event()
				if state != MatchState.IN_PLAY:
					return
			_check_out_of_play()
		MatchState.SCORED:
			_state_timer += delta
			if _state_timer >= DURATION_SCORED:
				_transition(MatchState.RESET)
		MatchState.KICKOFF:
			_state_timer += delta
			var taker_has_ball := _kickoff_taker != null and actors_container.ball.carrier == _kickoff_taker
			if taker_has_ball or _state_timer >= KICKOFF_TIMEOUT:
				GameEvents.kickoff_started.emit()
				_transition(MatchState.IN_PLAY)
		MatchState.RESTART:
			_state_timer += delta
			var taker_has_ball := _restart_taker != null and actors_container.ball.carrier == _restart_taker
			if taker_has_ball or _state_timer >= RESTART_TIMEOUT:
				_transition(MatchState.IN_PLAY)

func _on_team_scored(team: String) -> void:
	if state != MatchState.IN_PLAY:
		return  # Ignore goals during celebration/reset/kickoff
	var scoring_team : String
	if team == actors_container.team_left:
		score_right += 1
		scoring_team = actors_container.team_right
	else:
		score_left += 1
		scoring_team = actors_container.team_left
	# The conceding team restarts play — see _setup_kickoff().
	_kickoff_team = team
	_scorers.append({
		"player": _last_ball_carrier,
		"team": scoring_team,
		"time_str": "%d:%02d" % [int(match_time) / 60, int(match_time) % 60],
	})
	GameEvents.score_changed.emit()
	_transition(MatchState.SCORED)

func _on_ball_possessed(player_name: String) -> void:
	_last_ball_carrier = player_name

func _on_kickoff_ready() -> void:
	if state == MatchState.RESET:
		_transition(MatchState.KICKOFF)

## Freezes every player except one forward from _kickoff_team (picked at
## random), positions them a short walk behind the ball facing their
## attacking direction, and leaves them to take the kickoff — the same
## "one unfrozen player walks up to a loose ball" trick _on_foul_called()
## uses for free kicks. Everyone else stays exactly where the reset already
## put them, i.e. in their own half, same as a real kickoff.
func _setup_kickoff() -> void:
	var kicking_team := _kickoff_team
	_kickoff_team = ""
	_kickoff_taker = _pick_kickoff_taker(kicking_team)
	if _kickoff_taker == null:
		return  # No eligible players (e.g. an empty roster) — fall back to the timeout.
	for p in actors_container.left_team + actors_container.right_team:
		if p != _kickoff_taker:
			p.set_deferred("process_mode", Node.PROCESS_MODE_DISABLED)
	var behind_offset := KICKOFF_APPROACH_OFFSET if _kickoff_taker.is_left_team else -KICKOFF_APPROACH_OFFSET
	_kickoff_taker.position = actors_container.ball.spawn_position - Vector2(behind_offset, 0)
	_kickoff_taker.is_restart_taker = true

## Picks a random forward from [param team] to take the kickoff, falling back
## to any outfield player if that team has no forward assigned, or null if it
## has no outfield players at all.
func _pick_kickoff_taker(team: String) -> Player:
	var roster := actors_container.left_team + actors_container.right_team
	var forwards : Array[Player] = []
	var outfield : Array[Player] = []
	for p in roster:
		if p.team != team or p.role == Positions.Role.GK:
			continue
		outfield.append(p)
		if p.role in KICKOFF_TAKER_ROLES:
			forwards.append(p)
	if not forwards.is_empty():
		return MatchRng.pick(forwards)
	if not outfield.is_empty():
		return MatchRng.pick(outfield)
	return null

# ─── Restarts (fouls, offside, out of play) — docs/match-engine-v2.md Phase 2 ─

## A successful tackle was just ruled a foul (see Player.on_tackle_player):
## direct free kick to the fouled player's side, taken by the fouled player.
func _on_foul_called(fouled_player: Player, incident_position: Vector2) -> void:
	award_restart(Restart.Kind.FREE_KICK, fouled_player.team, incident_position, fouled_player)

## Called by OffsideJudge: indirect free kick to the defending side where the
## offender received the ball.
func award_offside(offender: Player) -> void:
	var defending := actors_container.right_team if offender.is_left_team else actors_container.left_team
	if defending.is_empty():
		return
	award_restart(Restart.Kind.OFFSIDE, defending[0].team, offender.position)

## Polled every IN_PLAY frame. The walls still physically stop the ball, so
## this fires as it reaches a line just inside them — see OutOfPlay.
func _check_out_of_play() -> void:
	var ball := actors_container.ball
	var carrier := ball.carrier
	if carrier != null and carrier.current_state != null and carrier.current_state.is_holding_ball():
		return  # a keeper holding the ball in their hands can't carry it out
	var line := OutOfPlay.crossed(ball.position, _goal_mouth(actors_container.goal_left), _goal_mouth(actors_container.goal_right))
	if line == OutOfPlay.Line.NONE:
		return
	var last_left : bool = ball.last_touch.is_left_team if ball.last_touch != null else MatchRng.randf() < 0.5
	var d := OutOfPlay.decide(line, ball.position, last_left)
	var team := actors_container.team_left if d["award_left"] else actors_container.team_right
	award_restart(d["kind"], team, d["spot"])

## (min_y, max_y) of [param goal]'s mouth, a little wider than its shot
## targets (which sit just inside the posts).
static func _goal_mouth(goal: Goal) -> Vector2:
	return Vector2(goal.get_top_target_position().y - 10.0, goal.get_bottom_target_position().y + 12.0)

## Stops play and sets up a restart for [param team] at [param spot]. Only
## [param taker] (picked automatically when null) stays unfrozen; they walk
## onto the ball and play resumes the moment they have it. Ignored outside
## IN_PLAY (e.g. a second foul while one is already being resolved).
func award_restart(kind: int, team: String, spot: Vector2, taker: Player = null) -> void:
	if state != MatchState.IN_PLAY:
		return
	if taker == null:
		taker = _pick_restart_taker(kind, team, spot)
	if taker == null:
		return
	_restart_kind = kind
	_restart_spot = spot
	_restart_taker = taker
	GameEvents.restart_awarded.emit(kind, team, spot)
	_transition(MatchState.RESTART)
	referee.focus_on(spot)

## Goal kicks go to the keeper; everything else to the nearest outfield
## player of [param team] (any player if the side has no outfielders).
func _pick_restart_taker(kind: int, team: String, spot: Vector2) -> Player:
	var side := actors_container.left_team if team == actors_container.team_left else actors_container.right_team
	var best : Player = null
	var best_d := INF
	for p in side:
		if not SpecialPlayerTypes.movable(p.special_type):
			continue
		var is_gk := p.role == Positions.Role.GK
		if kind == Restart.Kind.GOAL_KICK and is_gk:
			return p
		if is_gk:
			continue
		var d := p.position.distance_squared_to(spot)
		if d < best_d:
			best_d = d
			best = p
	return best if best != null else (side[0] if not side.is_empty() else null)

## Deferred from the RESTART transition — moving CharacterBody2Ds and the
## ball isn't safe from inside the physics callback a foul is detected in.
## Queued after the fouled player's HURT state is added (which tumbles the
## ball), so the ball placement here wins.
func _setup_restart() -> void:
	var ball := actors_container.ball
	var taker := _restart_taker
	if taker == null:
		return
	var spot := _restart_spot
	if _restart_kind == Restart.Kind.GOAL_KICK:
		# The keeper restarts from their hands: HOLDING_BALL gives them the
		# ball (tackle-immune, pressers back off) and GoalieAI's existing
		# distribution logic takes it from there.
		_clear_penalty_area(taker)
		taker.position = spot
		taker.velocity = Vector2.ZERO
		taker.switch_state(Player.State.HOLDING_BALL)
		return
	ball.carrier = null
	ball.position = spot
	ball.velocity = Vector2.ZERO
	ball.height = 0.0
	ball.height_velocity = 0.0
	ball.switch_state(Ball.State.FREEFORM)
	# Stand the taker just behind the ball: from their own goal's side for a
	# free kick, from the pitch interior for throw-ins and corners.
	var back_dir := spot.direction_to(taker.own_goal.get_center_target_position())
	if _restart_kind in [Restart.Kind.THROW_IN, Restart.Kind.CORNER]:
		back_dir = spot.direction_to(PitchSpace.from_absolute_normalised(Vector2(0.5, 0.5)))
	if Restart.teleports_taker(_restart_kind) or taker.position.distance_to(spot) < RESTART_TAKER_OFFSET:
		taker.position = spot + back_dir * RESTART_TAKER_OFFSET
		taker.velocity = Vector2.ZERO
	_retreat_opponents(taker, spot, Restart.retreat_distance(_restart_kind))

## Opponents inside [param radius] of the spot step back toward their own goal
## (Laws 13/15/17 distances). Players already far enough away stay put.
func _retreat_opponents(taker: Player, spot: Vector2, radius: float) -> void:
	for p in actors_container.left_team + actors_container.right_team:
		if p.team == taker.team or p.position.distance_to(spot) >= radius:
			continue
		var goal_center := p.own_goal.get_center_target_position() if p.own_goal != null else spot
		var retreat_dir := spot.direction_to(goal_center)
		if retreat_dir == Vector2.ZERO:
			retreat_dir = Vector2.LEFT if p.is_left_team else Vector2.RIGHT
		p.position = spot + retreat_dir * radius

## Goal kick: every opponent inside the penalty area moves out to its edge.
func _clear_penalty_area(keeper: Player) -> void:
	for p in actors_container.left_team + actors_container.right_team:
		if p.team == keeper.team:
			continue
		var n := PitchSpace.normalised(p.position, keeper.is_left_team)
		if n.x < PENALTY_AREA_DEPTH:
			p.position = PitchSpace.from_normalised(Vector2(PENALTY_AREA_DEPTH + 0.01, n.y), keeper.is_left_team)

## Rolls for a random mid-match event (Pepito Perinola narrating something
## like a pitch invader or a crowd surge). Pauses play for the duration of
## the dialogue, same freeze GAMEOVER already applies to actors_container,
## then resumes IN_PLAY.
func _maybe_trigger_match_event() -> void:
	var line := RandomEvents.maybe_trigger_match_event(GameState.player_club)
	if line.is_empty():
		return
	_match_event_fired = true
	_transition(MatchState.EVENT)
	ClubTrainer.say(line)
	await ClubTrainer.finished
	_transition(MatchState.IN_PLAY)

func _transition(new_state: MatchState) -> void:
	_state_timer = 0.0
	state = new_state
	match new_state:
		MatchState.RESET:
			GameEvents.team_reset.emit()
		MatchState.EVENT:
			# Freeze play while Pepito Perinola narrates — same mechanism
			# GAMEOVER uses, just resumed afterward instead of staying off.
			actors_container.process_mode = Node.PROCESS_MODE_DISABLED
		MatchState.IN_PLAY:
			actors_container.process_mode = Node.PROCESS_MODE_INHERIT
			for p in actors_container.left_team + actors_container.right_team:
				# Deferred: a foul is discovered inside an Area2D body_entered
				# callback (on_tackle_player, mid physics-step), and toggling a
				# CharacterBody2D's process_mode synchronously there is a Godot
				# error ("Disabling a CollisionObject during a physics callback").
				p.set_deferred("process_mode", Node.PROCESS_MODE_INHERIT)
			if _restart_taker != null:
				_restart_taker.is_restart_taker = false
				# The taker plays it straight away rather than dribbling off
				# with it (the keeper's goal kick uses GoalieAI's own release).
				if _restart_kind != Restart.Kind.GOAL_KICK:
					_restart_taker.restart_pass_pending = true
				if Restart.offside_exempt(_restart_kind):
					_offside_judge.exempt_next_kick = true
			if _kickoff_taker != null:
				_kickoff_taker.is_restart_taker = false
			_restart_taker = null
			_kickoff_taker = null
			referee.follow_ball()
		MatchState.KICKOFF:
			_setup_kickoff()
		MatchState.RESTART:
			# Everyone except the taker freezes exactly where they are; the
			# taker walks onto the placed ball via their own unfrozen
			# AIBehavior (Player.is_restart_taker).
			_restart_taker.is_restart_taker = true
			for p in actors_container.left_team + actors_container.right_team:
				if p != _restart_taker:
					p.set_deferred("process_mode", Node.PROCESS_MODE_DISABLED)
			call_deferred("_setup_restart")
		MatchState.GAMEOVER:
			actors_container.process_mode = Node.PROCESS_MODE_DISABLED
			GameEvents.game_over.emit()
			if MatchConfig.headless:
				return  # Harness reads the result itself — no season bookkeeping, save or popup.
			_write_back_stamina()
			var match_result := {}
			if not SeasonManager.pending_player_fixture.is_empty():
				match_result = SeasonManager.report_player_match_result(score_left, score_right)
				GameState.save_career()
			_show_game_over(match_result)

## Builds the same Dictionary shape hub.gd's "Simular" flow does (see
## MatchSummaryData) from own/opponent perspective, using ActorsContainer.
## is_player_team_left to tell which literal side (team_left/team_right) is
## the human club's — needed since the fixture's home club isn't always the
## player's (see world.gd's _resolve_home_club() doc comment).
func _show_game_over(match_result: Dictionary) -> void:
	pause_menu.enabled = false
	var is_player_left := actors_container.is_player_team_left
	var own_name := actors_container.team_left if is_player_left else actors_container.team_right
	var opp_name := actors_container.team_right if is_player_left else actors_container.team_left
	var own_score := score_left if is_player_left else score_right
	var opp_score := score_right if is_player_left else score_left
	var data := MatchSummaryData.build(own_name, opp_name, own_score, opp_score, _scorers, false, match_result)
	match_summary_popup.show_result(data)

## Persists each player's depleted in-match Player.stamina back onto their
## PlayerResource — otherwise it's just discarded when this scene unloads.
## Covers both rosters, not only the human club's, so an AI opponent that
## plays multiple live matches in one session (e.g. repeated Test Matches)
## carries fatigue too. See docs/ai-overhaul.md Phase 5; recovery on a rest
## day is SeasonManager.resolve_day()'s job, not this scene's.
func _write_back_stamina() -> void:
	for p in actors_container.left_team + actors_container.right_team:
		if p.player_data != null:
			p.player_data.stamina = p.stamina

func _on_back_to_hub_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/hub/hub.tscn")

## Dev scripted-scenario trigger (see scenes/world/scenario_debug.gd, Phase 0
## of docs/ai-overhaul.md). Polls a small file under user:// instead of a
## keybind: this game has no reliable input-injection path for an external
## driver on Windows (PostMessage'd WM_KEYDOWN doesn't reach Godot's window —
## confirmed by hand; likely gated on real OS focus, unlike the mouse clicks
## the run-fafa-simulator skill already uses), so a file poll is the only
## automatable trigger. Only runs when DebugDraw.ENABLED, so it's inert (one
## FileAccess.file_exists check every SCENARIO_POLL_INTERVAL seconds) in a
## normal playthrough and doesn't exist at all in a release export mindset.
const SCENARIO_TRIGGER_PATH := "user://scenario_trigger.txt"
const SCENARIO_POLL_INTERVAL := 0.5
var _scenario_poll_timer := 0.0

func _poll_scenario_trigger(delta: float) -> void:
	if not DebugDraw.ENABLED:
		return
	_scenario_poll_timer += delta
	if _scenario_poll_timer < SCENARIO_POLL_INTERVAL:
		return
	_scenario_poll_timer = 0.0
	if not FileAccess.file_exists(SCENARIO_TRIGGER_PATH):
		return
	var f := FileAccess.open(SCENARIO_TRIGGER_PATH, FileAccess.READ)
	var scenario_name := f.get_as_text().strip_edges()
	f.close()
	DirAccess.remove_absolute(SCENARIO_TRIGGER_PATH)
	if scenario_name != "":
		ScenarioDebug.apply(scenario_name, actors_container)
