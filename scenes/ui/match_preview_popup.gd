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

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	simulate_odds_label.add_theme_color_override("font_color", HubPalette.MUTED)

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

	var own_odds : Dictionary = preview["own_odds"]
	var sim_odds : Dictionary = preview["simulate_odds"]
	odds_label.text = tr("Si jugás  —  victoria / empate / derrota")
	odds_bar.set_odds(own_odds["win"], own_odds["draw"], own_odds["loss"])
	simulate_odds_label.text = tr("Si simulás  —  victoria –10%")
	simulate_odds_bar.set_odds(sim_odds["win"], sim_odds["draw"], sim_odds["loss"])

	visible = true
	get_tree().paused = true

func _hide_popup() -> void:
	visible = false
	get_tree().paused = false

func _on_play_pressed() -> void:
	_hide_popup()
	play_pressed.emit()

func _on_simulate_pressed() -> void:
	_hide_popup()
	simulate_pressed.emit()
