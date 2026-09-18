extends Control

@onready var spanish_button : Button = $Center/VBox/LocaleRow/SpanishButton
@onready var english_button : Button = $Center/VBox/LocaleRow/EnglishButton

func _ready() -> void:
	_refresh_buttons()

func _refresh_buttons() -> void:
	spanish_button.disabled = GameState.locale == "es"
	english_button.disabled = GameState.locale == "en"

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")

## Reloads this same screen after switching so every label on it (including
## itself) picks up the new locale immediately instead of only on next visit.
func _on_spanish_pressed() -> void:
	GameState.set_locale("es")
	get_tree().reload_current_scene()

func _on_english_pressed() -> void:
	GameState.set_locale("en")
	get_tree().reload_current_scene()
