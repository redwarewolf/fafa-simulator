extends Control

@onready var load_game_button : Button = $Center/VBox/LoadGameButton
@onready var load_game_hint : Label = $Center/VBox/LoadGameHint

func _ready() -> void:
	AudioManager.play_music(AudioManager.MENU_MUSIC)
	load_game_hint.add_theme_color_override("font_color", HubPalette.MUTED)
	_refresh_load_button()

## With a save on disk, loading it is the main action (FM's "Continue"):
## gold, first in the list, and labelled with the club and where it's at.
## Without one it stays a disabled "Cargar Partida" with the hint below.
func _refresh_load_button() -> void:
	var has_save := FileAccess.file_exists(GameState.CAREER_SAVE_PATH)
	load_game_button.disabled = not has_save
	load_game_hint.visible = not has_save
	if not has_save:
		return
	load_game_button.text = tr("Continuar")
	load_game_button.theme_type_variation = &"PrimaryButton"
	var summary := _save_summary()
	if summary != "":
		load_game_hint.text = summary
		load_game_hint.visible = true

## "Club  ·  Día 3 de 44  ·  1ª Mitad" read straight from career.json, without
## loading the career itself.
func _save_summary() -> String:
	var file := FileAccess.open(GameState.CAREER_SAVE_PATH, FileAccess.READ)
	if file == null:
		return ""
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not data is Dictionary:
		return ""
	var club_name := ""
	for c in data.get("division_e_clubs", []):
		if c.get("id", "") == data.get("player_club_id", ""):
			club_name = c.get("display_name", "")
	var date := SeasonManager.phase_date_string(int(data.get("phase_day", 1)),
		int(data.get("phase_length", 1)), SeasonManager.phase_from_name(data.get("phase", "")))
	return "%s  ·  %s" % [club_name, date] if club_name != "" else date

func _on_new_game_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/menu/team_creation.tscn")

func _on_load_game_pressed() -> void:
	if GameState.load_career():
		get_tree().change_scene_to_file("res://scenes/hub/hub.tscn")
	else:
		load_game_hint.text = "No se pudo cargar el club guardado"
		load_game_hint.visible = true

func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/menu/settings_screen.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()
