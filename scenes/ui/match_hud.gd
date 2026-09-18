class_name MatchHUD
extends CanvasLayer

@onready var animation_player    := %AnimationPlayer as AnimationPlayer
@onready var home_logo_texture   := %HomeLogoTexture as TextureRect
@onready var away_logo_texture   := %AwayLogoTexture as TextureRect
@onready var player_label        := %PlayerLabel as Label
@onready var score_label         := %ScoreLabel as Label
@onready var time_label          := %TimeLabel as Label
@onready var goal_scorer_label   := %GoalScorerLabel as Label
@onready var score_info_label    := %ScoreInfoLabel as Label
@onready var foul_label          := %FoulLabel as Label
@onready var speed_label         := %SpeedLabel as Label
@onready var cam_mode_button     := %CamModeButton as Button

const SPEED_STEPS := [1.0, 2.0, 4.0, 8.0]
const SPEED_ICONS := [">", ">>", ">>>", ">>>>"
]
var _speed_index := 0

var _world: MatchWorld
var _actors_container: ActorsContainer
var _camera: Camera
var _last_ball_carrier := ""

func _ready() -> void:
	# MatchHUD is a child of HUD (CanvasLayer) which is a child of the World node.
	_world = get_parent().get_parent() as MatchWorld
	_actors_container = _world.get_node("ActorsContainer") as ActorsContainer
	_camera = _world.get_node("Camera") as Camera

	_load_logos()
	_update_score()
	time_label.text = "0:00"
	player_label.text = ""
	goal_scorer_label.modulate.a = 0.0
	score_info_label.modulate.a = 0.0
	_update_cam_mode_button()

	GameEvents.ball_possessed.connect(_on_ball_possessed)
	GameEvents.ball_released.connect(_on_ball_released)
	GameEvents.score_changed.connect(_on_score_changed)
	GameEvents.team_reset.connect(_on_team_reset)
	GameEvents.match_time_updated.connect(_on_match_time_updated)
	GameEvents.game_over.connect(_on_game_over)
	GameEvents.foul_called.connect(_on_foul_called)
	cam_mode_button.pressed.connect(_on_cam_mode_button_pressed)

func _on_cam_mode_button_pressed() -> void:
	_camera.toggle_mode()
	_update_cam_mode_button()

func _update_cam_mode_button() -> void:
	cam_mode_button.text = tr("CÁM: LIBRE") if _camera.mode == Camera.Mode.FREE else tr("CÁM: BALÓN")

## Load club crest textures for both teams.
func _load_logos() -> void:
	ClubLogo.apply(home_logo_texture, DataLoader.get_club_by_team_key(_actors_container.team_left))
	ClubLogo.apply(away_logo_texture, DataLoader.get_club_by_team_key(_actors_container.team_right))

func _update_score() -> void:
	score_label.text = "%d - %d" % [_world.score_left, _world.score_right]

func _on_ball_possessed(player_name: String) -> void:
	player_label.text = player_name
	_last_ball_carrier = player_name

func _on_ball_released() -> void:
	player_label.text = ""

func _on_score_changed() -> void:
	_update_score()
	goal_scorer_label.text = tr("¡GOL DE %s!") % _last_ball_carrier
	var sl := _world.score_left
	var sr := _world.score_right
	if sl == sr:
		score_info_label.text = tr("EMPATE  %d - %d") % [sl, sr]
	elif sl > sr:
		score_info_label.text = tr("%s GANA  %d - %d") % [_actors_container.team_left, sl, sr]
	else:
		score_info_label.text = tr("%s GANA  %d - %d") % [_actors_container.team_right, sr, sl]
	animation_player.play("goal_appear")

func _on_foul_called(_fouled_player: Player, _incident_position: Vector2) -> void:
	animation_player.play("foul_flash")

func _on_team_reset() -> void:
	if _world.score_left > 0 or _world.score_right > 0:
		animation_player.play("goal_hide")

func _on_match_time_updated(elapsed: float) -> void:
	var total_sec := int(elapsed)
	time_label.text = "%d:%02d" % [total_sec / 60, total_sec % 60]

func _unhandled_input(event: InputEvent) -> void:
	if _world == null or _world.state == MatchWorld.MatchState.GAMEOVER:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: _set_speed(0)
			KEY_2: _set_speed(1)
			KEY_3: _set_speed(2)
			KEY_4: _set_speed(3)

func _exit_tree() -> void:
	Engine.time_scale = 1.0

func _set_speed(index: int) -> void:
	_speed_index = index
	Engine.time_scale = SPEED_STEPS[index]
	speed_label.text = SPEED_ICONS[index]

func _on_game_over() -> void:
	Engine.time_scale = 1.0
	_speed_index = 0
	speed_label.text = SPEED_ICONS[0]
	var sl := _world.score_left
	var sr := _world.score_right
	score_info_label.text = "FINAL  %d - %d" % [sl, sr]
	animation_player.play("game_over")
