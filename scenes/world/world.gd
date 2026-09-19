class_name MatchWorld
extends Node2D

## World state machine — orchestrates the full match lifecycle:
## IN_PLAY → SCORED → RESET → KICKOFF → IN_PLAY, or → GAMEOVER when time runs out.
## A foul (see Player.on_tackle_player) detours IN_PLAY → FOUL → IN_PLAY instead.
## HUD rendering is delegated to MatchHUD (match_hud.tscn).

enum MatchState { IN_PLAY, SCORED, RESET, KICKOFF, GAMEOVER, EVENT, FOUL }

## Total match duration in seconds (6 minutes).
const MATCH_DURATION := 360.0
## How long to stay in SCORED state (celebration pause) before resetting.
const DURATION_SCORED := 3.0
## Safety net only — KICKOFF normally ends the instant the kickoff taker
## touches the ball (see _setup_kickoff()). Guards against a soft lock if no
## taker could be picked, or theirs gets stuck, on the way there.
const KICKOFF_TIMEOUT := 8.0
## Safety net only — FOUL normally ends the instant the free-kick taker
## touches the ball. Longer than KICKOFF_TIMEOUT since, unlike a kickoff
## taker, the fouled player isn't teleported next to the ball first — they
## may have to walk/run across the pitch to reach it.
const FOUL_TIMEOUT := 12.0
## How far an opponent must stand from the foul spot once a free kick is
## given — mirrors the real "must retreat" distance rule so nobody is left
## frozen shoulder-to-shoulder with (or blocking) the kicker.
const MIN_FOUL_RETREAT_DISTANCE := 110.0
## How often (in match seconds) to roll for a random mid-match event.
const EVENT_CHECK_INTERVAL := 60.0
## Roles eligible to take a kickoff — forwards, same as the real game.
const KICKOFF_TAKER_ROLES := [Positions.Role.ST, Positions.Role.LW, Positions.Role.RW]
## The kickoff taker starts this far behind the ball (opposite their attacking
## direction) so they visibly walk up and strike it, rather than starting on it.
const KICKOFF_APPROACH_OFFSET := 40.0

@onready var actors_container  := $ActorsContainer as ActorsContainer
@onready var tribunes          := $Tribunes as Tribunes
@onready var referee           := $ActorsContainer/Referee as Referee
@onready var game_over_overlay := %GameOverOverlay
@onready var game_over_label   := %GameOverLabel
@onready var summary_label     := %SummaryLabel
@onready var pause_menu        := $PauseMenu as PauseMenu

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
## Set while state == FOUL — the only player left unfrozen, walking/running
## back to the loose ball to take the free kick. See _on_foul_called().
var _free_kick_taker : Player = null
## Where the foul happened — used to push retreating opponents back from it.
## See _on_foul_called() and _retreat_opponents_from_free_kick().
var _free_kick_incident_position : Vector2 = Vector2.ZERO
## Which team takes the next kickoff — the conceding team after a goal, or a
## random team for the match's opening kickoff. Consumed by _setup_kickoff().
var _kickoff_team : String = ""
## Set while state == KICKOFF — the only player left unfrozen, walking/running
## up to the ball to start play. See _setup_kickoff().
var _kickoff_taker : Player = null

func _ready() -> void:
	GameEvents.team_scored.connect(_on_team_scored)
	GameEvents.kickoff_ready.connect(_on_kickoff_ready)
	GameEvents.ball_possessed.connect(_on_ball_possessed)
	GameEvents.foul_called.connect(_on_foul_called)
	game_over_overlay.visible = false
	_setup_stadium()
	# Opening kickoff: a proper restart, same as after a goal, just with a
	# randomly chosen team instead of the conceding one.
	_kickoff_team = [actors_container.team_left, actors_container.team_right].pick_random()
	_transition(MatchState.KICKOFF)

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
			if match_time >= MATCH_DURATION:
				_transition(MatchState.GAMEOVER)
				return
			if not _match_event_fired and match_time >= _next_event_check:
				_next_event_check += EVENT_CHECK_INTERVAL
				_maybe_trigger_match_event()
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
		MatchState.FOUL:
			_state_timer += delta
			var taker_has_ball := _free_kick_taker != null and actors_container.ball.carrier == _free_kick_taker
			if taker_has_ball or _state_timer >= FOUL_TIMEOUT:
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
		return forwards.pick_random()
	if not outfield.is_empty():
		return outfield.pick_random()
	return null

## A successful tackle was just ruled a foul (see Player.on_tackle_player).
## Ignore a second foul while one is already being resolved — rare, and the
## in-flight one will finish normally.
func _on_foul_called(fouled_player: Player, incident_position: Vector2) -> void:
	if state == MatchState.FOUL:
		return
	_free_kick_taker = fouled_player
	_free_kick_incident_position = incident_position
	_transition(MatchState.FOUL)
	referee.focus_on(incident_position)

## Pushes any opponent standing inside MIN_FOUL_RETREAT_DISTANCE of the foul
## spot back toward their own goal, same as a real free kick's "must retreat"
## rule. Players already far enough away are left exactly where they are —
## this only clears out anyone crowding the restart. Deferred (see the FOUL
## branch of _transition()) for the same reason process_mode toggles are:
## the foul is detected mid physics-step, and moving a CharacterBody2D isn't
## safe to do synchronously from inside that callback.
func _retreat_opponents_from_free_kick() -> void:
	if _free_kick_taker == null:
		return
	var incident := _free_kick_incident_position
	for p in actors_container.left_team + actors_container.right_team:
		if p.team == _free_kick_taker.team:
			continue
		if p.position.distance_to(incident) >= MIN_FOUL_RETREAT_DISTANCE:
			continue
		var goal_center := p.own_goal.get_center_target_position() if p.own_goal != null else incident
		var retreat_dir := incident.direction_to(goal_center)
		if retreat_dir == Vector2.ZERO:
			retreat_dir = Vector2.LEFT if p.is_left_team else Vector2.RIGHT
		p.position = incident + retreat_dir * MIN_FOUL_RETREAT_DISTANCE

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
			if _free_kick_taker != null:
				_free_kick_taker.is_restart_taker = false
			if _kickoff_taker != null:
				_kickoff_taker.is_restart_taker = false
			_free_kick_taker = null
			_kickoff_taker = null
			referee.follow_ball()
		MatchState.KICKOFF:
			_setup_kickoff()
		MatchState.FOUL:
			# Everyone except the fouled player freezes exactly where they are
			# — they walk/run back to the loose ball themselves via their own
			# unfrozen AIBehavior (see _on_foul_called(), Player.is_restart_taker).
			_free_kick_taker.is_restart_taker = true
			for p in actors_container.left_team + actors_container.right_team:
				if p != _free_kick_taker:
					p.set_deferred("process_mode", Node.PROCESS_MODE_DISABLED)
			# Opponents must retreat off the ball too, same as a real free
			# kick — a ref would order them back rather than let them stand
			# frozen on top of the kicker.
			call_deferred("_retreat_opponents_from_free_kick")
		MatchState.GAMEOVER:
			actors_container.process_mode = Node.PROCESS_MODE_DISABLED
			GameEvents.game_over.emit()
			_write_back_stamina()
			var match_result := {}
			if not SeasonManager.pending_player_fixture.is_empty():
				match_result = SeasonManager.report_player_match_result(score_left, score_right)
				GameState.save_career()
			_show_game_over(match_result)

func _show_game_over(match_result: Dictionary) -> void:
	pause_menu.enabled = false
	game_over_overlay.visible = true
	var score_str := "%d - %d" % [score_left, score_right]
	if score_left > score_right:
		game_over_label.text = tr("¡GANÓ %s!\n%s") % [actors_container.team_left, score_str]
	elif score_right > score_left:
		game_over_label.text = tr("¡GANÓ %s!\n%s") % [actors_container.team_right, score_str]
	else:
		game_over_label.text = tr("EMPATE\n%s") % score_str

	if match_result.is_empty():
		summary_label.visible = false  # e.g. Hub's dev "Test Match" button — no season fixture involved
		return

	summary_label.visible = true
	var lines : Array[String] = []
	var fans_delta : int = match_result.get("fans_delta", 0)
	lines.append(tr("Hinchas: %s%d  (ahora %s)") % [
		"+" if fans_delta >= 0 else "", fans_delta, MoneyFormat.format(GameState.player_club.fans)])
	var ticket_revenue : int = match_result.get("ticket_revenue", 0)
	if ticket_revenue > 0:
		lines.append(tr("Ingresos por Entradas: $%s  (%s asistentes)") % [
			MoneyFormat.format(ticket_revenue), MoneyFormat.format(match_result.get("attendance", 0))])
	if not _scorers.is_empty():
		lines.append("")
		lines.append(tr("Goleadores:"))
		for s in _scorers:
			lines.append(tr("%s  %s (%s)") % [s["time_str"], s["player"], s["team"]])
	summary_label.text = "\n".join(lines)

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
