class_name ActorsContainer
extends Node2D

const DURATION_TACTICAL_REFRESH := 200 # ms between pressing/marking recomputes; increase if performance suffers
const PLAYER_PREFAB := preload("res://scenes/characters/player.tscn")

# World-space bounds of the playable field area (from wall geometry in world.tscn)
const FIELD_LEFT   := 91.0
const FIELD_RIGHT  := 2288.0
const FIELD_TOP    := 164.0
const FIELD_BOTTOM := 1052.0

## Kickoff squeezes every anchor into the team's own half: an anchor at x=0.76
## lines up at x=0.38 for the restart, then the player pushes out to it.
const KICKOFF_COMPRESSION := 0.5

@export var ball : Ball
@export var goal_left : Goal
@export var goal_right : Goal

@export var team_left : String
@export var team_right : String

@onready var spawns_left : Node2D = $SpawnsLeft
@onready var spawns_right : Node2D = %SpawnsRight

var left_team : Array[Player] = []
var right_team : Array[Player] = []

var time_since_last_tactical_refresh := Time.get_ticks_msec()
var _field_zones : FieldZones = null
var _team_tactical_left := TeamTacticalState.new()
var _team_tactical_right := TeamTacticalState.new()

func _ready() -> void:
	_apply_pending_fixture_teams()

	# Tell each goal which team defends it, so ScoringArea can emit team_scored correctly.
	goal_left.team  = team_left
	goal_right.team = team_right

	left_team  = _spawn_team(team_left,  goal_left,  spawns_left,  false)
	right_team = _spawn_team(team_right, goal_right, spawns_right, true)
	for player in left_team:
		player.teammates = left_team
		player.opponents = right_team
	for player in right_team:
		player.teammates = right_team
		player.opponents = left_team

	GameEvents.team_scored.connect(_on_team_scored)
	GameEvents.team_reset.connect(_on_team_reset)
	# FieldZones registers into its group on _enter_tree (before any _ready in
	# the scene) specifically so this lookup can't lose the race — see the
	# comment on FieldZones._enter_tree.
	_field_zones = get_tree().get_first_node_in_group("field_zones") as FieldZones

## When a season fixture is pending, override the scene's default teams
## with the scheduled home/away clubs instead of the hardcoded test match.
## Falls back to GameState.test_match_teams (set by the Hub's dev "Test
## Match" button) so that shortcut also resolves to real clubs instead of
## the scene's hardcoded legacy team keys, which predate the procedural
## club system and resolve to no ClubResource at all.
func _apply_pending_fixture_teams() -> void:
	if SeasonManager != null and not SeasonManager.pending_player_fixture.is_empty():
		var f := SeasonManager.pending_player_fixture
		var home := DataLoader.get_club(f["home_id"])
		var away := DataLoader.get_club(f["away_id"])
		if home != null and away != null:
			team_left  = home.team_key
			team_right = away.team_key
		return
	if GameState != null and GameState.test_match_teams.size() == 2:
		team_left  = GameState.test_match_teams[0]
		team_right = GameState.test_match_teams[1]
		GameState.test_match_teams = []  # consumed — don't leak into a later unrelated scene load

func _any_slot_assigned(tactic) -> bool:
	for s in tactic.slots:
		if s.is_assigned():
			return true
	return false

## Spawns one side, in a tactic if [param team]'s club can produce one (the
## player's own active tactic for their side, or a shape TacticBuilder fits to
## the AI club's own roster otherwise) or the legacy fixed spawn points as a
## last resort when no roster is assigned at all.
func _spawn_team(team: String, own_goal: Goal, spawns: Node2D, mirror: bool) -> Array[Player]:
	var tactic := _tactic_for_team(team)
	if tactic != null and tactic.slots.size() > 0 and _any_slot_assigned(tactic):
		return _spawn_from_tactic(tactic, team, own_goal, mirror)
	return spawn_players(team, own_goal, spawns)

## The player's own team plays whichever tactic they picked in the Squad
## screen. Every other club — AI opponents — gets a tactic TacticBuilder builds
## fresh from that club's own roster, so it no longer just mirrors the
## player's shape/headcount.
func _tactic_for_team(team: String) -> Resource:
	var club := DataLoader.get_club_by_team_key(team)
	if club == null:
		# The Hub's dev "Test Match" shortcut still points world.tscn at the
		# original hand-authored team keys, which predate the procedural club
		# system and resolve to nothing once a career replaces DataLoader's
		# clubs — fall back to the player's own tactic so that shortcut still
		# populates the pitch instead of spawning an empty match.
		return GameState.get_active_tactic() if GameState != null and not GameState.tactics.is_empty() else null
	if GameState != null and GameState.player_club != null and club.id == GameState.player_club.id:
		return GameState.get_active_tactic()
	return TacticBuilder.build_best_fit(club)

## Spawn players from a tactic. mirror=true flips x so the right team defends
## the right goal.
##
## A slot holds an ANCHOR in full-field space (x=0 own goal → x=1 opponent
## goal), so a forward's anchor legitimately sits in the opponent half. Nobody
## may START there, though — the restart would put three players inside the
## opposing box — so kickoff compresses the whole shape into the own half and
## the anchor is carried separately for the AI to aim at.
func _spawn_from_tactic(tactic, team: String, own_goal: Goal, mirror: bool) -> Array[Player]:
	var player_nodes : Array[Player] = []
	var target_goal := goal_right if own_goal == goal_left else goal_left

	for i in tactic.slots.size():
		var slot = tactic.slots[i]
		if not slot.is_assigned():
			continue
		var anchor  := _tactic_to_world(slot.position, mirror)
		# The keeper is exempt: their anchor IS their line, and GoalieAI reads
		# the goal line off the spawn point. Compressing it would drop them behind it.
		var compression : float = 1.0 if i == Formations.GOALKEEPER_SLOT else KICKOFF_COMPRESSION
		var kickoff := _tactic_to_world(Vector2(slot.position.x * compression, slot.position.y), mirror)
		var player := spawn_player(kickoff, own_goal, target_goal, slot.player, team, slot.role)
		player.anchor_position = anchor
		player_nodes.append(player)
		add_child(player)
	return player_nodes

## Full-field normalised tactic coords → world space, mirrored for the right team.
func _tactic_to_world(normalised: Vector2, mirror: bool) -> Vector2:
	var field_w := FIELD_RIGHT  - FIELD_LEFT
	var field_h := FIELD_BOTTOM - FIELD_TOP
	var x := FIELD_RIGHT - normalised.x * field_w if mirror else FIELD_LEFT + normalised.x * field_w
	return Vector2(x, FIELD_TOP + normalised.y * field_h)
	
func spawn_players(team : String, own_goal : Goal, spawns) -> Array[Player]:
	var player_nodes : Array[Player] = []
	var club := DataLoader.get_club_by_team_key(team)
	var players : Array[PlayerResource] = club.players if club != null else ([] as Array[PlayerResource])
	var target_goal := goal_right if own_goal == goal_left else goal_left
	var spawn_count: int = spawns.get_child_count()
	for i in min(players.size(), spawn_count):
		var player_position := spawns.get_child(i).global_position as Vector2
		var player_data := players[i] as PlayerResource
		var player := spawn_player(player_position, own_goal, target_goal, player_data, team, player_data.role)
		player_nodes.append(player)
		add_child(player)
	return player_nodes

## Grid cell size for the SHOW_PITCH_CONTROL debug heatmap — purely a
## visualization aid, not read by any AI decision, so this is only ever
## computed when that toggle is on.
const DEBUG_PITCH_CONTROL_CELL := 110.0

func _process(_delta: float) -> void:
	if Time.get_ticks_msec() - time_since_last_tactical_refresh > DURATION_TACTICAL_REFRESH:
		time_since_last_tactical_refresh = Time.get_ticks_msec()
		_team_tactical_left.recompute(left_team, right_team, ball, _field_zones, true)
		_team_tactical_right.recompute(right_team, left_team, ball, _field_zones, false)
	if DebugDraw.ENABLED and DebugDraw.SHOW_PITCH_CONTROL:
		_draw_pitch_control_debug()

## Tints each grid cell by which team's players (position + velocity, see
## PitchControl) could reach it first — blue for left_team, red for
## right_team, alpha scaled by how clear-cut the advantage is. Confirms
## Phase 1's anticipatory space model visually tracks real open space rather
## than just trusting the math (see docs/ai-overhaul.md Phase 1).
func _draw_pitch_control_debug() -> void:
	var cols := int(ceil((FIELD_RIGHT - FIELD_LEFT) / DEBUG_PITCH_CONTROL_CELL))
	var rows := int(ceil((FIELD_BOTTOM - FIELD_TOP) / DEBUG_PITCH_CONTROL_CELL))
	for row in rows:
		for col in cols:
			var x := FIELD_LEFT + col * DEBUG_PITCH_CONTROL_CELL
			var y := FIELD_TOP + row * DEBUG_PITCH_CONTROL_CELL
			var center := Vector2(x + DEBUG_PITCH_CONTROL_CELL * 0.5, y + DEBUG_PITCH_CONTROL_CELL * 0.5)
			var value := PitchControl.control(center, left_team, right_team)
			var color := Color(0.2, 0.4, 1.0, absf(value) * 0.35) if value > 0.0 else Color(1.0, 0.2, 0.2, absf(value) * 0.35)
			DebugDraw.rect_filled(Rect2(x, y, DEBUG_PITCH_CONTROL_CELL, DEBUG_PITCH_CONTROL_CELL), color)

## [param slot_role]: the position this player is actually being fielded in —
## a tactic slot's role, or just the player's own role for the legacy
## fixed-spawn-point path (spawn_players) where there is no tactic slot to
## diverge from.
func spawn_player(player_position : Vector2, own_goal: Goal, target_goal: Goal, player_data : PlayerResource, team: String, slot_role : Positions.Role) -> Player:
	var player := PLAYER_PREFAB.instantiate()
	return player.initialize(player_position, ball, own_goal, target_goal, player_data, team, slot_role)

## Switch players to celebrating/mourning after a goal.
func _on_team_scored(team_conceded: String) -> void:
	for player in left_team + right_team:
		if player.team == team_conceded:
			player.switch_state(Player.State.MOURNING)
		else:
			player.switch_state(Player.State.CELEBRATING)

## Teleport all players back to their spawn positions and signal kickoff readiness.
func _on_team_reset() -> void:
	for player in left_team + right_team:
		player.position = player.spawn_position
		player.velocity = Vector2.ZERO
		player.switch_state(Player.State.MOVING)
	GameEvents.kickoff_ready.emit()
