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

func _refresh_load_button() -> void:
	var has_save := FileAccess.file_exists(GameState.CAREER_SAVE_PATH)
	load_game_button.disabled = not has_save
	load_game_hint.visible = not has_save

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
