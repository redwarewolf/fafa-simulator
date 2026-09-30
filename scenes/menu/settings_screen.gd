extends Control

@onready var spanish_button : Button = $Center/VBox/LocaleRow/SpanishButton
@onready var english_button : Button = $Center/VBox/LocaleRow/EnglishButton
@onready var disable_tutorial_check_box : CheckBox = $Center/VBox/TutorialCheckRow/DisableTutorialCheckBox
@onready var master_slider : HSlider = $Center/VBox/VolumeGrid/MasterSlider
@onready var music_slider : HSlider = $Center/VBox/VolumeGrid/MusicSlider
@onready var sfx_slider : HSlider = $Center/VBox/VolumeGrid/SfxSlider

func _ready() -> void:
	AudioManager.play_music(AudioManager.MENU_MUSIC)
	_refresh_buttons()
	disable_tutorial_check_box.button_pressed = GameState.tutorials_disabled
	_setup_volume_slider(master_slider, $Center/VBox/VolumeGrid/MasterValue, "master", GameState.master_volume)
	_setup_volume_slider(music_slider, $Center/VBox/VolumeGrid/MusicValue, "music", GameState.music_volume)
	_setup_volume_slider(sfx_slider, $Center/VBox/VolumeGrid/SfxValue, "sfx", GameState.sfx_volume)
	# Letting go of the effects slider plays a click at the new level.
	sfx_slider.drag_ended.connect(func(_changed: bool): AudioManager.play_navigate())

func _setup_volume_slider(slider: HSlider, value_label: Label, bus: String, current: float) -> void:
	slider.value = roundf(current * 100.0)
	value_label.text = "%d%%" % int(slider.value)
	slider.value_changed.connect(func(v: float):
		value_label.text = "%d%%" % int(v)
		GameState.set_volume(bus, v / 100.0))

func _refresh_buttons() -> void:
	spanish_button.disabled = GameState.locale == "es"
	english_button.disabled = GameState.locale == "en"

func _on_disable_tutorial_toggled(toggled_on: bool) -> void:
	GameState.set_tutorials_disabled(toggled_on)

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
