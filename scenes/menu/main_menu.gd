extends Control

const BUTTON_SOUND_TRACK := "res://assets/music/ui-button-sound.mp3"

@onready var load_game_button : Button = $Center/VBox/LoadGameButton
@onready var load_game_hint : Label = $Center/VBox/LoadGameHint
@onready var button_sound : AudioStreamPlayer = $ButtonSound

func _ready() -> void:
	button_sound.stream = load(BUTTON_SOUND_TRACK)
	for button in _find_buttons(self):
		button.pressed.connect(_play_button_sound)
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

func _find_buttons(node: Node) -> Array:
	var result : Array = []
	for child in node.get_children():
		if child is BaseButton:
			result.append(child)
		result.append_array(_find_buttons(child))
	return result

func _play_button_sound() -> void:
	button_sound.play()

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
