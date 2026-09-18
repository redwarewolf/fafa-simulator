class_name Goal
extends Node2D

## Dedicated collision layer for goal-mouth raycasting.
## Must not be shared with balls (4), players (2), or walls (8).
## Also must not be 32 — that's GoalieHands' physical layer (player.tscn),
## which the ball's collision_mask includes so it can bounce off keeper
## saves. Sharing it made scoring_body (a real StaticBody2D placed right in
## the goal mouth) physically block/bounce shots that should have scored.
const SCORING_COLLISION_LAYER := 64

@onready var back_net_area := %BackNetArea
@onready var scoring_area := %ScoringArea
@onready var targets := %Targets

## The team that DEFENDS this goal. Set by ActorsContainer after spawn.
## When a ball enters the scoring area, GameEvents.team_scored is emitted with this value.
@export var team: String = ""

## StaticBody2D placed across the goal mouth for ball raycast detection.
var scoring_body: StaticBody2D = null

func _ready() -> void:
	back_net_area.body_entered.connect(_on_ball_enter_back_net.bind())
	scoring_area.body_entered.connect(_on_ball_enter_scoring_area.bind())
	_build_scoring_body()

func _build_scoring_body() -> void:
	var top_pos := get_top_target_position()
	var bot_pos := get_bottom_target_position()
	var mouth_height := (bot_pos - top_pos).length() + 8.0  # small margin past each post

	scoring_body = StaticBody2D.new()
	scoring_body.collision_layer = SCORING_COLLISION_LAYER
	scoring_body.collision_mask = 0
	add_child(scoring_body)

	var shape_node := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(6.0, mouth_height)
	shape_node.shape = rect
	scoring_body.add_child(shape_node)
	scoring_body.global_position = (top_pos + bot_pos) * 0.5

func _on_ball_enter_back_net(ball: Ball) -> void:
	ball.stop()

func _on_ball_enter_scoring_area(_ball: Ball) -> void:
	if team.is_empty():
		return
	GameEvents.team_scored.emit(team)

func get_random_target_position() -> Vector2:
	return targets.get_child(randi_range(0, targets.get_child_count() - 1)).global_position

func get_center_target_position() -> Vector2:
	return targets.get_child(int(targets.get_child_count() / 2.0)).global_position

func get_top_target_position() -> Vector2:
	return targets.get_child(0).global_position

func get_bottom_target_position() -> Vector2:
	return targets.get_child(targets.get_child_count() - 1).global_position

