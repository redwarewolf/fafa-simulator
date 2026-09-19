class_name PauseMenu
extends CanvasLayer

## Reusable ESC pause overlay shared by the Hub and the match World scene.
## Freezes the whole tree while open (get_tree().paused) so match simulation
## and Hub timers stop, while staying responsive itself via
## process_mode = ALWAYS.

## Cleared by a host scene (world.gd, once GAMEOVER hits) so ESC stops
## reopening this over a screen that already has its own exit button.
var enabled := true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

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
