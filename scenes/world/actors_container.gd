class_name ActorsContainer
extends Node2D

const DURATION_WEIGHT_CACHE := 200 # ms between steering-weight refreshes; increase if performance suffers
const PLAYER_PREFAB := preload("res://scenes/characters/player.tscn")

# World-space bounds of the playable field area (from wall geometry in world.tscn)
const FIELD_LEFT   := 91.0
const FIELD_RIGHT  := 2288.0
const FIELD_TOP    := 164.0
const FIELD_BOTTOM := 1052.0

@export var ball : Ball
@export var goal_left : Goal
@export var goal_right : Goal

@export var team_left : String
@export var team_right : String

@onready var spawns_left : Node2D = $SpawnsLeft
@onready var spawns_right : Node2D = %SpawnsRight

var left_team : Array[Player] = []
var right_team : Array[Player] = []

var time_since_last_cache_refresh := Time.get_ticks_msec()

func _ready() -> void:
	var tactic = GameState.get_active_tactic() if GameState != null else null
	if tactic != null and tactic.slots.size() > 0 and _any_slot_assigned(tactic):
		left_team  = _spawn_from_tactic(tactic, team_left,  goal_left,  false)
		right_team = _spawn_from_tactic(tactic, team_right, goal_right, true)
	else:
		left_team  = spawn_players(team_left,  goal_left,  spawns_left)
		right_team = spawn_players(team_right, goal_right, spawns_right)
	for player in left_team:
		player.teammates = left_team
	for player in right_team:
		player.teammates = right_team

func _any_slot_assigned(tactic) -> bool:
	for s in tactic.slots:
		if s.is_assigned():
			return true
	return false

## Spawn players using tactic slot positions mapped to world space.
## mirror=true flips x so the right team starts in the right half.
func _spawn_from_tactic(tactic, team: String, own_goal: Goal, mirror: bool) -> Array[Player]:
	var player_nodes : Array[Player] = []
	var target_goal := goal_right if own_goal == goal_left else goal_left
	var field_w := FIELD_RIGHT  - FIELD_LEFT
	var field_h := FIELD_BOTTOM - FIELD_TOP
	var half_w  := field_w * 0.5

	for i in tactic.slots.size():
		var slot = tactic.slots[i]
		if not slot.is_assigned():
			continue
		var nx : float = slot.position.x  # 0=goal line → 1=halfway
		var ny : float = slot.position.y  # 0=top → 1=bottom
		var world_pos : Vector2
		if not mirror:
			# Left team: x goes from FIELD_LEFT (goal) to centre (halfway)
			world_pos = Vector2(
				FIELD_LEFT + nx * half_w,
				FIELD_TOP  + ny * field_h
			)
		else:
			# Right team: mirror — x=0 is now the right goal line
			world_pos = Vector2(
				FIELD_RIGHT - nx * half_w,
				FIELD_TOP   + ny * field_h
			)
		var player := spawn_player(world_pos, own_goal, target_goal, slot.player, team)
		player_nodes.append(player)
		add_child(player)
	return player_nodes
	
func spawn_players(team : String, own_goal : Goal, spawns) -> Array[Player]:
	var player_nodes : Array[Player] = []
	var club := DataLoader.get_club_by_team_key(team)
	var players : Array[PlayerResource] = club.players if club != null else []
	var target_goal := goal_right if own_goal == goal_left else goal_left
	for i in players.size():
		var player_position := spawns.get_child(i).global_position as Vector2
		var player_data := players[i] as PlayerResource
		var player := spawn_player(player_position, own_goal, target_goal, player_data, team)
		player_nodes.append(player)
		add_child(player)
	return player_nodes
	
func _process(_delta: float) -> void:
	if Time.get_ticks_msec() - time_since_last_cache_refresh > DURATION_WEIGHT_CACHE:
		time_since_last_cache_refresh = Time.get_ticks_msec()
		set_on_duty_weights()
		
func spawn_player(player_position : Vector2, own_goal: Goal, target_goal: Goal, player_data : PlayerResource, team: String) -> Player:
	var player := PLAYER_PREFAB.instantiate()
	return player.initialize(player_position, ball, own_goal, target_goal, player_data, team )	

func set_on_duty_weights() -> void:
	for team in [left_team, right_team]:
		var players : Array[Player] = team.filter(
			func(p: Player) : return p.role != Player.Role.GOALIE
		)
		players.sort_custom(func(p1: Player, p2 : Player):
			return p1.spawn_position.distance_squared_to(ball.position) < p2.spawn_position.distance_squared_to(ball.position))
			
		for i in range(players.size()):
			players[i].weight_on_duty_steering = 1 - ease(float(i) / 10.0, 0.1) # ease curve; raise divisor when squad size grows
			
