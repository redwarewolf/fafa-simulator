class_name PauseMenu
extends CanvasLayer

## Reusable ESC pause overlay shared by the Hub and the match World scene.
## Freezes the whole tree while open (get_tree().paused) so match simulation
## and Hub timers stop, while staying responsive itself via
## process_mode = ALWAYS.

## Cleared by a host scene (world.gd, once GAMEOVER hits) so ESC stops
## reopening this over a screen that already has its own exit button.
var enabled := true

var _ai_button : Button = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	# Dev toggle between the original match AI and the engine-v2 rebuild
	# (docs/match-engine-v2.md) — added from code, just above "Volver".
	_ai_button = Button.new()
	_ai_button.custom_minimum_size = Vector2(0, 36)
	_ai_button.pressed.connect(_on_ai_version_pressed)
	var back := %DebugPanel.get_node("BackButton")
	%DebugPanel.add_child(_ai_button)
	%DebugPanel.move_child(_ai_button, back.get_index())
	_update_ai_button()

func _on_ai_version_pressed() -> void:
	GameState.set_match_ai_version("v1" if GameState.match_ai_version == "v2" else "v2")
	_update_ai_button()

func _update_ai_button() -> void:
	_ai_button.text = tr("IA de partido: %s (próximo partido)") % GameState.match_ai_version.to_upper()

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if visible:
		_resume()
	elif enabled:
		_open()
	else:
		return
	get_viewport().set_input_as_handled()

func _open() -> void:
	visible = true
	get_tree().paused = true
	%DebugPanel.visible = false
	%MainPanel.visible = true

func _resume() -> void:
	visible = false
	get_tree().paused = false

func _on_resume_pressed() -> void:
	_resume()

func _on_main_menu_pressed() -> void:
	GameState.save_career()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")

func _on_quit_pressed() -> void:
	GameState.save_career()
	get_tree().quit()

func _on_debug_tools_pressed() -> void:
	%MainPanel.visible = false
	%DebugPanel.visible = true

func _on_debug_back_pressed() -> void:
	%DebugPanel.visible = false
	%MainPanel.visible = true

func _on_add_money_pressed() -> void:
	GameState.player_club.budget += 10000
	GameState.budget_changed.emit()
	GameState.save_upgrades()

func _on_add_fans_pressed() -> void:
	GameState.player_club.fans += 10
	GameState.budget_changed.emit()
	GameState.save_career()
