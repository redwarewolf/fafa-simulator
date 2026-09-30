class_name MatchPreviewPopup
extends CanvasLayer

## Pre-match popup shown from the Hub whenever "Next Date" lands on a
## scheduled fixture for the player's club — crest/overall comparison, the
## true win/draw/loss odds, what they become under the "Simular" penalty, and
## the Jugar/Simular choice itself. See SeasonManager.get_pending_match_preview()
## for the odds calc and SeasonManager.simulate_pending_player_match() for
## what "Simular" actually resolves to. Styled like PauseMenu (backdrop +
## UIFrame panel), reused as a single instance the same way DialogueBox/
## PauseMenu are (see hub.tscn).

signal play_pressed
signal simulate_pressed

@onready var home_logo    : TextureRect = $PanelRoot/Margin/Main/MatchupRow/HomeSide/Logo
@onready var home_name    : Label       = $PanelRoot/Margin/Main/MatchupRow/HomeSide/Name
@onready var home_overall : Label       = $PanelRoot/Margin/Main/MatchupRow/HomeSide/Overall
@onready var home_tag     : Label       = $PanelRoot/Margin/Main/MatchupRow/HomeSide/Tag
@onready var away_logo    : TextureRect = $PanelRoot/Margin/Main/MatchupRow/AwaySide/Logo
@onready var away_name    : Label       = $PanelRoot/Margin/Main/MatchupRow/AwaySide/Name
@onready var away_overall : Label       = $PanelRoot/Margin/Main/MatchupRow/AwaySide/Overall
@onready var away_tag     : Label       = $PanelRoot/Margin/Main/MatchupRow/AwaySide/Tag
@onready var odds_label          : Label = $PanelRoot/Margin/Main/OddsLabel
@onready var simulate_odds_label : Label = $PanelRoot/Margin/Main/SimulateOddsLabel
@onready var odds_bar            : Control = $PanelRoot/Margin/Main/OddsBar
@onready var simulate_odds_bar   : Control = $PanelRoot/Margin/Main/SimulateOddsBar

@onready var main : VBoxContainer = $PanelRoot/Margin/Main
@onready var button_row : Control = $PanelRoot/Margin/Main/ButtonRow

## "Por debajo de la mesa": one toggle per ClubHeat.BRIBES entry. Ticking one
## only picks it (the odds above update); it's paid at kickoff (hub.gd).
var _bribe_buttons := {}
var _risk_label : Label = null
var _warning_label : Label = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	simulate_odds_label.add_theme_color_override("font_color", HubPalette.MUTED)
	_build_bribes()

func _build_bribes() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	main.add_child(box)
	main.move_child(box, button_row.get_index())
	box.add_child(HSeparator.new())
	var title := Label.new()
	title.text = tr("POR DEBAJO DE LA MESA")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", HubPalette.MUTED)
	box.add_child(title)
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	box.add_child(row)
	for key in ClubHeat.BRIBES:
		var btn := Button.new()
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.tooltip_text = tr(ClubHeat.BRIBES[key]["tip"])
		btn.toggled.connect(_on_bribe_toggled.bind(key))
		row.add_child(btn)
		_bribe_buttons[key] = btn
	_risk_label = Label.new()
	_risk_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_risk_label)
	_warning_label = Label.new()
	_warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warning_label.add_theme_color_override("font_color", HubPalette.LOSS)
	box.add_child(_warning_label)

func _refresh_bribes(preview: Dictionary) -> void:
	var afa := GameState.afa
	var division := GameState.player_club.division
	for key in _bribe_buttons:
		var btn : Button = _bribe_buttons[key]
		btn.text = "%s  $%s" % [tr(ClubHeat.BRIBES[key]["label"]), MoneyFormat.format(ClubHeat.bribe_cost(key, division))]
		var available := ClubHeat.bribe_available(key, GameState.barra)
		if not available:
			afa["bribes"][key] = false
		btn.disabled = not available
		if available:
			btn.tooltip_text = tr(ClubHeat.BRIBES[key]["tip"])
		elif float(GameState.barra["relacion"]) < float(ClubHeat.BRIBES[key].get("min_relacion", 0.0)):
			btn.tooltip_text = tr("Para esto la barra tiene que ser Incondicional.")
		else:
			btn.tooltip_text = tr("La barra todavía no tiene poder para esto.")
		btn.set_pressed_no_signal(afa["bribes"][key])
	if ClubHeat.any_bribe(afa):
		_risk_label.text = tr("Riesgo de que se sepa: %d%% por arreglo") % roundi(ClubHeat.scandal_chance(afa) * 100.0)
		_risk_label.add_theme_color_override("font_color", HubPalette.HIGHLIGHT)
	else:
		_risk_label.text = tr("Nadie se tiene que enterar.")
		_risk_label.add_theme_color_override("font_color", HubPalette.MUTED)
	var warnings : Array[String] = []
	if preview.get("is_own_home", false) and ClubHeat.closed_doors_now(afa, true):
		warnings.append(tr("Sanción de la AFA: este partido se juega sin público."))
	var heat_warning := ClubHeat.warning(afa)
	if heat_warning != "":
		warnings.append(heat_warning)
	_warning_label.text = "\n".join(warnings)
	_warning_label.visible = not warnings.is_empty()

func _on_bribe_toggled(pressed: bool, key: String) -> void:
	GameState.afa["bribes"][key] = pressed
	var preview := SeasonManager.get_pending_match_preview()
	_set_odds(preview)
	_refresh_bribes(preview)

## [param preview] is SeasonManager.get_pending_match_preview()'s return value.
func show_for_fixture(preview: Dictionary) -> void:
	if preview.is_empty():
		return
	var home : ClubResource = preview["home"]
	var away : ClubResource = preview["away"]
	var is_own_home : bool = preview["is_own_home"]

	ClubLogo.apply(home_logo, home)
	ClubLogo.apply(away_logo, away)
	home_name.text = home.display_name
	away_name.text = away.display_name
	home_overall.text = tr("OVR %d") % home.get_squad_overall()
	away_overall.text = tr("OVR %d") % away.get_squad_overall()
	home_tag.visible = is_own_home
	away_tag.visible = not is_own_home

	_set_odds(preview)
	_refresh_bribes(preview)

	visible = true
	get_tree().paused = true

func _set_odds(preview: Dictionary) -> void:
	var own_odds : Dictionary = preview["own_odds"]
	var sim_odds : Dictionary = preview["simulate_odds"]
	odds_label.text = tr("Si jugás  —  victoria / empate / derrota")
	odds_bar.set_odds(own_odds["win"], own_odds["draw"], own_odds["loss"])
	simulate_odds_label.text = tr("Si simulás  —  victoria –10%")
	simulate_odds_bar.set_odds(sim_odds["win"], sim_odds["draw"], sim_odds["loss"])

func _hide_popup() -> void:
	visible = false
	get_tree().paused = false

func _on_play_pressed() -> void:
	_hide_popup()
	play_pressed.emit()

func _on_simulate_pressed() -> void:
	_hide_popup()
	simulate_pressed.emit()
