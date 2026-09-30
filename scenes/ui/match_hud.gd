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
@onready var mentality_button    := %MentalityButton as Button
@onready var home_name_label     := %HomeNameLabel as Label
@onready var away_name_label     := %AwayNameLabel as Label
@onready var ui_container        := $UIContainer as Control

## FM-style touchline shouts: one button per TacticPreset.ManualMode, index-
## matched, replacing the old single button that cycled through all four.
const SHOUT_LABELS := ["AUTO", "DEFENDER", "EQUILIBRAR", "ATACAR"]
const SHOUT_TIPS := [
	"El equipo decide solo según el marcador y el reloj",
	"Replegarse y cuidar el resultado",
	"Ni arriesgar ni encerrarse",
	"Adelantar líneas y buscar el gol",
]
const PANEL_BG := Color(0.04, 0.09, 0.11, 0.9)
const STATS_REFRESH_S := 0.5
const EVENT_ROWS := 8

var _shout_buttons : Array[Button] = []
var _stats_panel : PanelContainer = null
var _stats_grid : GridContainer = null
var _events_list : VBoxContainer = null
var _stats_refresh_left := 0.0

const SPEED_STEPS := [1.0, 2.0, 4.0, 8.0]
const SPEED_ICONS := [">", ">>", ">>>", ">>>>"
]
const PAUSE_ICON := "||"
var _speed_index := 0
var _paused := false

## Cycles AUTO -> DEFENSIVE -> NEUTRAL -> AGGRESSIVE -> AUTO. Index-matched
## to TacticPreset.ManualMode. A live in-match manager control — see
## docs/ai-overhaul.md Phase 8.
const MENTALITY_LABELS := ["MODO: AUTO", "MODO: DEFENSIVO", "MODO: NEUTRAL", "MODO: AGRESIVO"]

var _world: MatchWorld
var _actors_container: ActorsContainer
var _camera: Camera
var _last_ball_carrier := ""
var _goal_banner_shown := false

func _ready() -> void:
	# MatchHUD is a child of HUD (CanvasLayer) which is a child of the World node.
	_world = get_parent().get_parent() as MatchWorld
	_actors_container = _world.get_node("ActorsContainer") as ActorsContainer
	_camera = _world.get_node("Camera") as Camera

	_load_logos()
	_update_score()
	time_label.text = "0'"
	player_label.text = ""
	goal_scorer_label.modulate.a = 0.0
	score_info_label.modulate.a = 0.0
	_update_cam_mode_button()
	mentality_button.text = tr(MENTALITY_LABELS[TacticPreset.ManualMode.AUTO])

	GameEvents.ball_possessed.connect(_on_ball_possessed)
	GameEvents.ball_released.connect(_on_ball_released)
	GameEvents.score_changed.connect(_on_score_changed)
	GameEvents.team_reset.connect(_on_team_reset)
	GameEvents.match_time_updated.connect(_on_match_time_updated)
	GameEvents.game_over.connect(_on_game_over)
	GameEvents.restart_awarded.connect(_on_restart_awarded)
	GameEvents.half_time.connect(_on_half_time)
	cam_mode_button.pressed.connect(_on_cam_mode_button_pressed)
	mentality_button.pressed.connect(_on_mentality_button_pressed)
	mentality_button.visible = false  # superseded by the shout row below
	_build_shouts()
	_build_stats_panel()
	_build_commentary()
	_build_subs_panel()

func _on_cam_mode_button_pressed() -> void:
	_camera.toggle_mode()
	_update_cam_mode_button()

func _update_cam_mode_button() -> void:
	cam_mode_button.text = tr("CÁM: LIBRE") if _camera.mode == Camera.Mode.FREE else tr("CÁM: BALÓN")

## Cycles the human player's own team's mentality (whichever side
## is_player_team_left says that is — the AI opponent is never affected).
## See docs/ai-overhaul.md Phase 8.
func _on_mentality_button_pressed() -> void:
	var next_mode := (_actors_container.player_manual_mentality_mode + 1) % MENTALITY_LABELS.size()
	_actors_container.player_manual_mentality_mode = next_mode
	mentality_button.text = tr(MENTALITY_LABELS[next_mode])

## Load club crest textures (and names, for the scoreboard) for both teams.
func _load_logos() -> void:
	var left := DataLoader.get_club_by_team_key(_actors_container.team_left)
	var right := DataLoader.get_club_by_team_key(_actors_container.team_right)
	ClubLogo.apply(home_logo_texture, left)
	ClubLogo.apply(away_logo_texture, right)
	for label in [home_name_label, away_name_label]:
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	home_name_label.text = left.display_name if left != null else _actors_container.team_left
	away_name_label.text = right.display_name if right != null else _actors_container.team_right

# ── shouts ────────────────────────────────────────────────────────────────────

func _build_shouts() -> void:
	var box := VBoxContainer.new()
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.offset_left = -116.0
	box.offset_right = -8.0
	box.offset_top = 66.0
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.add_theme_constant_override("separation", 3)
	ui_container.add_child(box)

	var title := Label.new()
	title.text = tr("INDICACIONES")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Sits straight on the grass — outlined so it reads on both stripe tones.
	title.add_theme_color_override("font_outline_color", Color(0.02, 0.06, 0.08))
	title.add_theme_constant_override("outline_size", 4)
	box.add_child(title)

	var group := ButtonGroup.new()
	for i in SHOUT_LABELS.size():
		var btn := Button.new()
		btn.text = tr(SHOUT_LABELS[i])
		btn.tooltip_text = tr(SHOUT_TIPS[i])
		btn.toggle_mode = true
		btn.button_group = group
		btn.focus_mode = Control.FOCUS_NONE
		btn.button_pressed = i == _actors_container.player_manual_mentality_mode
		btn.pressed.connect(_on_shout_pressed.bind(i))
		box.add_child(btn)
		_shout_buttons.append(btn)

func _on_shout_pressed(mode: int) -> void:
	_actors_container.player_manual_mentality_mode = mode
	mentality_button.text = tr(MENTALITY_LABELS[mode])

# ── commentary strip ──────────────────────────────────────────────────────────

var _commentary : Label = null

## One-line running commentary along the bottom edge, like FM's 2D match
## view: who has the ball, shots, saves, set pieces, goals. Driven entirely
## by GameEvents, so the match itself doesn't know it exists.
func _build_commentary() -> void:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	style.set_corner_radius_all(3)
	panel.add_theme_stylebox_override("panel", style)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -260.0
	panel.offset_right = 260.0
	panel.offset_top = -34.0
	panel.offset_bottom = -8.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_container.add_child(panel)
	_commentary = Label.new()
	_commentary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_commentary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	panel.add_child(_commentary)

	GameEvents.ball_possessed.connect(func(player_name: String) -> void:
		_say(tr("%s tiene la pelota") % player_name, Color.WHITE))
	GameEvents.shot_taken.connect(func(shooter: Player, _origin: Vector2) -> void:
		_say(tr("¡Remate de %s!") % shooter.full_name, HubPalette.HIGHLIGHT))
	GameEvents.keeper_decision.connect(func(keeper: Player, _p: float, save: bool) -> void:
		if save:
			_say(tr("¡Atajada de %s!") % keeper.full_name, HubPalette.WIN))
	GameEvents.restart_awarded.connect(func(kind: int, team: String, _spot: Vector2) -> void:
		_say("%s  —  %s" % [tr(Restart.LABELS.get(kind, "")), _club_name(team)], HubPalette.MUTED))
	GameEvents.score_changed.connect(func() -> void:
		_say(tr("¡GOOOL de %s!") % _last_ball_carrier, HubPalette.HIGHLIGHT))
	GameEvents.half_time.connect(func() -> void: _say(tr("Entretiempo"), HubPalette.MUTED))
	GameEvents.substitution_made.connect(func(team: String, off_name: String, on_name: String) -> void:
		_say(tr("Cambio en %s: entra %s, sale %s") % [_club_name(team), on_name, off_name], HubPalette.HIGHLIGHT))

func _say(text: String, color: Color) -> void:
	if _commentary == null:
		return
	_commentary.text = text
	_commentary.add_theme_color_override("font_color", color)

func _club_name(team_key: String) -> String:
	return home_name_label.text if team_key == _actors_container.team_left else away_name_label.text

# ── stats panel ───────────────────────────────────────────────────────────────

## Toggled with the ESTADÍSTICAS button or Tab. Reads world.match_stats
## (see scenes/match/match_stats.gd); left column = left team, like the
## scoreboard.
func _build_stats_panel() -> void:
	var toggle := Button.new()
	toggle.text = tr("ESTADÍSTICAS")
	toggle.tooltip_text = tr("Atajo: Tab")
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.anchor_left = 1.0
	toggle.anchor_right = 1.0
	toggle.offset_left = -116.0
	toggle.offset_right = -8.0
	toggle.offset_top = 212.0
	toggle.offset_bottom = 236.0
	toggle.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	toggle.pressed.connect(_toggle_stats_panel)
	ui_container.add_child(toggle)

	_stats_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.set_content_margin_all(10)
	style.set_corner_radius_all(3)
	_stats_panel.add_theme_stylebox_override("panel", style)
	_stats_panel.anchor_left = 1.0
	_stats_panel.anchor_right = 1.0
	_stats_panel.offset_left = -400.0
	_stats_panel.offset_right = -124.0
	_stats_panel.offset_top = 36.0
	_stats_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_stats_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stats_panel.visible = false
	ui_container.add_child(_stats_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_stats_panel.add_child(vbox)
	_stats_grid = GridContainer.new()
	_stats_grid.columns = 3
	_stats_grid.add_theme_constant_override("h_separation", 12)
	vbox.add_child(_stats_grid)
	vbox.add_child(HSeparator.new())
	var events_title := Label.new()
	events_title.text = tr("EVENTOS")
	events_title.add_theme_color_override("font_color", HubPalette.MUTED)
	vbox.add_child(events_title)
	_events_list = VBoxContainer.new()
	vbox.add_child(_events_list)

func _toggle_stats_panel() -> void:
	_stats_panel.visible = not _stats_panel.visible
	if _stats_panel.visible:
		_refresh_stats_panel()

func _process(delta: float) -> void:
	if _stats_panel == null or not _stats_panel.visible:
		return
	_stats_refresh_left -= delta
	if _stats_refresh_left <= 0.0:
		_stats_refresh_left = STATS_REFRESH_S
		_refresh_stats_panel()

func _refresh_stats_panel() -> void:
	var stats = _world.match_stats
	if stats == null:
		return
	for child in _stats_grid.get_children():
		_stats_grid.remove_child(child)
		child.queue_free()
	_stat_cell(home_name_label.text, HORIZONTAL_ALIGNMENT_LEFT, HubPalette.HIGHLIGHT)
	_stat_cell("", HORIZONTAL_ALIGNMENT_CENTER, HubPalette.MUTED)
	_stat_cell(away_name_label.text, HORIZONTAL_ALIGNMENT_RIGHT, HubPalette.HIGHLIGHT)
	for row in stats.rows(_actors_container.team_left):
		_stat_cell(row[1], HORIZONTAL_ALIGNMENT_LEFT, Color.WHITE)
		_stat_cell(tr(row[0]), HORIZONTAL_ALIGNMENT_CENTER, HubPalette.MUTED)
		_stat_cell(row[2], HORIZONTAL_ALIGNMENT_RIGHT, Color.WHITE)

	for child in _events_list.get_children():
		_events_list.remove_child(child)
		child.queue_free()
	var events : Array = stats.events
	if events.is_empty():
		_event_line(tr("Sin eventos todavía"), HubPalette.MUTED)
	for i in range(events.size() - 1, maxi(-1, events.size() - 1 - EVENT_ROWS), -1):
		var e : Dictionary = events[i]
		var color := HubPalette.HIGHLIGHT if e["kind"] == "goal" else Color.WHITE
		var side := ""
		if e["team"] != "":
			side = "  (%s)" % (home_name_label.text if e["team"] == _actors_container.team_left else away_name_label.text)
		_event_line("%d'  %s%s" % [e["minute"], e["text"], side], color)

func _stat_cell(text: String, align: int, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.custom_minimum_size.x = 70
	l.add_theme_color_override("font_color", color)
	_stats_grid.add_child(l)

func _event_line(text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.clip_text = true
	l.add_theme_color_override("font_color", color)
	_events_list.add_child(l)

# ── substitutions ─────────────────────────────────────────────────────────────

var _subs : Substitutions = null
var _subs_button : Button = null
var _subs_panel : PanelContainer = null
var _subs_body : VBoxContainer = null
## The on-pitch player picked to come off, waiting for a bench pick.
var _subs_selected_out : Player = null
## True when opening the panel paused the match (so closing resumes it).
var _subs_paused_match := false

## CAMBIOS button under the shouts, and the panel it opens: the human side's
## players on the pitch (stamina, morale) and its bench. Pick who comes off,
## then who comes on; the change waits for the next stoppage (Substitutions).
## Opening it pauses the match, like FM.
func _build_subs_panel() -> void:
	_subs = _world.substitutions
	if _subs == null or not _subs.enabled():
		return
	_subs_button = Button.new()
	_subs_button.tooltip_text = tr("Atajo: C")
	_subs_button.focus_mode = Control.FOCUS_NONE
	_subs_button.anchor_left = 1.0
	_subs_button.anchor_right = 1.0
	_subs_button.offset_left = -116.0
	_subs_button.offset_right = -8.0
	_subs_button.offset_top = 242.0
	_subs_button.offset_bottom = 266.0
	_subs_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_subs_button.pressed.connect(_toggle_subs_panel)
	ui_container.add_child(_subs_button)

	_subs_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.set_content_margin_all(12)
	style.set_corner_radius_all(3)
	_subs_panel.add_theme_stylebox_override("panel", style)
	_subs_panel.set_anchors_preset(Control.PRESET_CENTER)
	_subs_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_subs_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_subs_panel.visible = false
	ui_container.add_child(_subs_panel)
	_subs_body = VBoxContainer.new()
	_subs_body.add_theme_constant_override("separation", 6)
	_subs_panel.add_child(_subs_body)

	_subs.changed.connect(_refresh_subs)
	_refresh_subs()

func _player_side_left() -> bool:
	return _actors_container.is_player_team_left

func _toggle_subs_panel() -> void:
	if _subs_panel == null or _world.state == MatchWorld.MatchState.GAMEOVER:
		return
	_subs_panel.visible = not _subs_panel.visible
	_subs_selected_out = null
	if _subs_panel.visible:
		if not _paused:
			_toggle_pause()
			_subs_paused_match = true
		_refresh_subs()
	elif _subs_paused_match:
		_subs_paused_match = false
		if _paused:
			_toggle_pause()

func _refresh_subs() -> void:
	if _subs_button == null:
		return
	var left := _player_side_left()
	_subs_button.text = tr("CAMBIOS %d/%d") % [_subs.used(left), Substitutions.MAX_PER_SIDE]
	if not _subs_panel.visible:
		return
	for child in _subs_body.get_children():
		_subs_body.remove_child(child)
		child.queue_free()

	var remaining := _subs.remaining(left)
	var title := Label.new()
	title.text = tr("CAMBIOS  —  quedan %d") % remaining
	title.add_theme_color_override("font_color", HubPalette.HIGHLIGHT)
	_subs_body.add_child(title)
	var hint := Label.new()
	hint.text = tr("Elegí quién sale y después quién entra. El cambio se hace en la próxima pelota parada.")
	hint.add_theme_color_override("font_color", HubPalette.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint.custom_minimum_size.x = 560
	_subs_body.add_child(hint)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	_subs_body.add_child(columns)

	var on_col := _subs_column(columns, tr("EN CANCHA"))
	for p in _subs.on_pitch(left):
		var going := _subs.is_pending_out(p)
		var stamina := roundi(p.stamina)
		var btn := _subs_row_button("%s  %s" % [Positions.label(p.role), p.full_name], "%d%%" % stamina,
			HubPalette.LOSS if stamina < 50 else (HubPalette.HIGHLIGHT if stamina < 75 else HubPalette.WIN),
			p.player_data)
		btn.toggle_mode = true
		btn.button_pressed = p == _subs_selected_out
		btn.disabled = going or remaining <= 0
		if going:
			btn.tooltip_text = tr("Ya tiene un cambio pedido")
		btn.pressed.connect(func() -> void:
			_subs_selected_out = null if _subs_selected_out == p else p
			_refresh_subs())
		on_col.add_child(btn)

	var bench_col := _subs_column(columns, tr("SUPLENTES"))
	var bench := _subs.bench(left)
	if bench.is_empty():
		var none := Label.new()
		none.text = tr("No hay suplentes")
		none.add_theme_color_override("font_color", HubPalette.MUTED)
		bench_col.add_child(none)
	for pr in bench:
		var btn := _subs_row_button("%s  %s" % [Positions.label(pr.role), pr.full_name], "OVR %d" % pr.overall(),
			QualityStyle.COLORS[pr.quality], pr)
		btn.disabled = _subs_selected_out == null
		btn.pressed.connect(func() -> void:
			_subs.queue(_subs_selected_out, pr)
			_subs_selected_out = null
			_refresh_subs())
		bench_col.add_child(btn)

	for i in _subs.pending.size():
		var s : Dictionary = _subs.pending[i]
		if s["left"] != left:
			continue  # the AI's own queued changes stay a surprise
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = tr("Pedido: entra %s por %s") % [(s["in"] as PlayerResource).full_name, (s["out"] as Player).full_name]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var cancel := Button.new()
		cancel.text = tr("Anular")
		cancel.focus_mode = Control.FOCUS_NONE
		cancel.pressed.connect(_subs.cancel.bind(i))
		row.add_child(cancel)
		_subs_body.add_child(row)

	var close := Button.new()
	close.text = tr("LISTO")
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(_toggle_subs_panel)
	_subs_body.add_child(close)

func _subs_column(parent: Control, heading: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = 272
	col.add_theme_constant_override("separation", 2)
	var l := Label.new()
	l.text = heading
	l.add_theme_color_override("font_color", HubPalette.MUTED)
	col.add_child(l)
	parent.add_child(col)
	return col

## One player row: name on the left, [param right_text] in [param right_color]
## on the right, and a morale dot — hover shows PlayerMorale.tooltip().
func _subs_row_button(text: String, right_text: String, right_color: Color, data: PlayerResource) -> Button:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size.y = 24
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.text = text
	btn.clip_text = true
	if data != null and PlayerMorale.has_morale(data):
		btn.tooltip_text = PlayerMorale.tooltip(data)
	var right := HBoxContainer.new()
	right.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	right.offset_left = -96
	right.offset_right = -8
	right.alignment = BoxContainer.ALIGNMENT_END
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var value := Label.new()
	value.text = right_text
	value.add_theme_color_override("font_color", right_color)
	right.add_child(value)
	if data != null and PlayerMorale.has_morale(data):
		var dot := Label.new()
		dot.text = " ●"
		dot.add_theme_color_override("font_color", PlayerMorale.color(data))
		right.add_child(dot)
	btn.add_child(right)
	return btn

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
	_goal_banner_shown = true

## Every stoppage (foul, offside, throw-in, corner, goal kick) reuses the
## foul toast, just with the restart's own label.
func _on_restart_awarded(kind: int, _team: String, _spot: Vector2) -> void:
	foul_label.text = tr(Restart.LABELS.get(kind, "¡FALTA!"))
	animation_player.play("foul_flash")

## Only after a goal: the half-time reset used to replay goal_hide whenever
## the score wasn't 0-0, flashing the last "GOAL!" banner at 45'.
func _on_team_reset() -> void:
	if _goal_banner_shown:
		_goal_banner_shown = false
		animation_player.play("goal_hide")

## The match clock: real seconds scaled to 0'-90' (MatchWorld.game_minute).
func _on_match_time_updated(_elapsed: float) -> void:
	time_label.text = "%d'" % _world.game_minute()

func _on_half_time() -> void:
	foul_label.text = tr("ENTRETIEMPO")
	animation_player.play("foul_flash")

func _unhandled_input(event: InputEvent) -> void:
	if _world == null or _world.state == MatchWorld.MatchState.GAMEOVER:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_TAB: _toggle_stats_panel()
			KEY_C: _toggle_subs_panel()
			KEY_0: _toggle_pause()
			KEY_1: _set_speed(0)
			KEY_2: _set_speed(1)
			KEY_3: _set_speed(2)
			KEY_4: _set_speed(3)

func _exit_tree() -> void:
	Engine.time_scale = 1.0

## Independent of _set_speed's 1x-8x steps — resumes at whichever step was
## active before pausing rather than always snapping back to 1x. Useful for
## AI debugging (see docs/ai-overhaul.md Phase 6): freezing a moment lets
## you inspect positions/debug overlays without the match continuing to
## simulate. All match timers read MatchClock, which advances by the scaled
## frame delta, so pausing freezes AI ticks and state timers too, and higher
## speeds keep the AI's decision rate constant in game time.
func _toggle_pause() -> void:
	_paused = not _paused
	if _paused:
		Engine.time_scale = 0.0
		speed_label.text = PAUSE_ICON
	else:
		Engine.time_scale = SPEED_STEPS[_speed_index]
		speed_label.text = SPEED_ICONS[_speed_index]

func _set_speed(index: int) -> void:
	_speed_index = index
	_paused = false
	Engine.time_scale = SPEED_STEPS[index]
	speed_label.text = SPEED_ICONS[index]

func _on_game_over() -> void:
	if _stats_panel != null:
		_stats_panel.visible = false  # the summary popup shows the same numbers
	if _subs_panel != null:
		_subs_panel.visible = false
		_subs_paused_match = false
	Engine.time_scale = 1.0
	_speed_index = 0
	_paused = false
	speed_label.text = SPEED_ICONS[0]
	var sl := _world.score_left
	var sr := _world.score_right
	score_info_label.text = "FINAL  %d - %d" % [sl, sr]
	animation_player.play("game_over")
