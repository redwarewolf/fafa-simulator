class_name Referee
extends Node2D

## Purely decorative match actor — trails the ball from a distance during
## normal play, and jogs over to a foul when one's called (see MatchWorld's
## FOUL state / GameEvents.foul_called). Deliberately a lean Node2D, not a
## CharacterBody2D: no collision or detection Areas, so it can never be
## marked, pressed, or tackled by player AI.
##
## Reuses a plain soccer-player body (see utils/body_types.gd), but with
## shaders/referee_body.gdshader instead of the normal team-palette shader —
## clothing is remapped to grayscale by luminance so the referee reads as a
## neutral black-and-white kit regardless of which two teams are playing.

const BODY_TYPES := ["default", "fat"]
const NORMAL_SKIN_TONES := [Player.SkinColor.LIGHT, Player.SkinColor.MEDIUM]
const WALK_SPEED := 50.0
const RUN_SPEED := 120.0
## Below this distance to a freshly recalculated target, walk instead of run —
## reads as an unhurried repositioning rather than sprinting a few pixels.
const WALK_RUN_DISTANCE_THRESHOLD := 100.0
## Re-picking a spot to stand every tick reads as constant jittery micro-
## adjustments — only reconsider where to stand this often.
const RECALC_INTERVAL := 2.0
## Trails behind/above the ball rather than standing on it — reads as
## "watching from a distance," not as another player in the play.
const FOLLOW_OFFSET := Vector2(0, -70)
const ARRIVE_DISTANCE := 4.0

@export var ball : Ball

@onready var sprite : Sprite2D = %RefereeSprite
@onready var animation_player : AnimationPlayer = %AnimationPlayer

var _target : Vector2
var _speed := WALK_SPEED
var _following_ball := true
var _time_since_recalc := 0.0

func _ready() -> void:
	_apply_random_look()
	_target = position
	follow_ball()
	GameEvents.team_reset.connect(_on_team_reset)

func _process(delta: float) -> void:
	if _following_ball:
		_time_since_recalc += delta
		if _time_since_recalc >= RECALC_INTERVAL:
			_time_since_recalc = 0.0
			_pick_follow_target()
	var distance := position.distance_to(_target)
	if distance > ARRIVE_DISTANCE:
		var previous_x := position.x
		position = position.move_toward(_target, _speed * delta)
		if position.x != previous_x:
			sprite.flip_h = position.x < previous_x
		animation_player.play("walk" if _speed == WALK_SPEED else "run")
	else:
		animation_player.play("idle")

## Default behavior — keep trailing the ball at a distance, re-picking a spot
## to stand every RECALC_INTERVAL rather than continuously chasing it.
func follow_ball() -> void:
	_following_ball = true
	_time_since_recalc = 0.0
	_pick_follow_target()

## Jog/walk over to call a foul at [param point] instead of following the ball.
func focus_on(point: Vector2) -> void:
	_following_ball = false
	_set_target(point)

## Players teleport straight back to their spawn positions on a reset (see
## ActorsContainer._on_team_reset) — having the referee visibly run all the
## way back across the pitch afterward reads as broken, so snap along with
## them instead. Targets ball.spawn_position directly rather than ball.position,
## since the ball's own reset may not have run yet (connection order is
## unspecified) and spawn_position is a fixed value either way.
func _on_team_reset() -> void:
	_following_ball = true
	_time_since_recalc = 0.0
	if ball != null:
		_target = ball.spawn_position + FOLLOW_OFFSET
	position = _target

func _pick_follow_target() -> void:
	if ball != null:
		_set_target(ball.position + FOLLOW_OFFSET)

func _set_target(point: Vector2) -> void:
	_target = point
	var distance := position.distance_to(_target)
	_speed = WALK_SPEED if distance < WALK_RUN_DISTANCE_THRESHOLD else RUN_SPEED

func _apply_random_look() -> void:
	var body_type : String = BODY_TYPES[randi() % BODY_TYPES.size()]
	var body_def : Dictionary = BodyTypes.DATA.get(body_type, BodyTypes.DATA["default"])
	sprite.texture = body_def["texture"]
	sprite.hframes = body_def["hframes"]
	sprite.vframes = body_def["vframes"]
	var hair_colors := Player.HairColor.values()
	sprite.material.set_shader_parameter("skin_color", NORMAL_SKIN_TONES[randi() % NORMAL_SKIN_TONES.size()])
	sprite.material.set_shader_parameter("hair_color", hair_colors[randi() % hair_colors.size()])
