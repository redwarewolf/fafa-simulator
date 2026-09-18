extends Control

const PLACEHOLDER := preload("res://scenes/ui/placeholder_panel.tscn")

## Sub-section key → scene. `null` means "not built yet" and gets a framed
## placeholder instead of its own near-empty .tscn.
const SUB_SECTIONS := {
	"stadium": preload("res://scenes/hub/sections/club/stadium_panel.tscn"),
	"staff": preload("res://scenes/hub/sections/club/staff_panel.tscn"),
	"training": preload("res://scenes/hub/sections/club/training_panel.tscn"),
	"costs": preload("res://scenes/hub/sections/club/costs_panel.tscn"),
	"earnings": preload("res://scenes/hub/sections/club/earnings_panel.tscn"),
	"hiring": preload("res://scenes/hub/sections/club/hiring_panel.tscn"),
}

const HIRING_LABEL := "Contrataciones"

## Pepito Perinola's one-shot walkthrough for each Club sub-tab — played the
## first time that sub-tab is shown on a given save (see
## _maybe_play_sub_tutorial()). Stored under GameState.tutorials_seen as
## "club_<key>" so these don't collide with hub.gd's own top-level "club" key
## (the generic "welcome to the Club tab" line that plays before any of these).
const SUB_TUTORIALS := {
	"stadium": [
		"Este es el Estadio. Acá ves tu capacidad actual y podés invertir en ampliarlo para meter más gente — y cobrar más entradas.",
	],
	"staff": [
		"Esta es la pestaña de Personal. Acá contratás entrenador, ojeador y otros roles que hacen crecer al club con el tiempo.",
	],
	"training": [
		"Esta es la pestaña de Entrenamiento. Con un entrenador contratado, le podés dar sesiones a un jugador para subirle stats de forma permanente.",
	],
	"costs": [
		"Acá ves los Gastos: sueldos del plantel y mantenimiento del personal contratado, se descuentan solos cada vez que avanzás el día.",
	],
	"earnings": [
		"Acá ves los Ingresos: lo que entra por entradas, merchandising y comida en cada partido.",
	],
	"hiring": [
		"Esta es la pestaña de Contrataciones. Acá aparecen los candidatos que te trae el ojeador — fichalos antes de que se enfríen.",
	],
}

@onready var sub_content : Control = $HBox/SubContent
@onready var hiring_button : Button = $HBox/Sidebar/SidebarLayout/HiringButton

var _panel_instances : Dictionary = {}
var _active_panel : String = ""

func _ready() -> void:
	for key in SUB_SECTIONS:
		var instance := _make_panel(key)
		instance.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		instance.process_mode = Node.PROCESS_MODE_DISABLED
		instance.visible = false
		sub_content.add_child(instance)
		_panel_instances[key] = instance
	_show_panel("stadium")
	GameState.pool_badges_changed.connect(_update_hiring_badge)
	_update_hiring_badge()

## Mirrors hub.gd's nav badge on the "Club" tab itself — this is the button
## that actually reveals the scout pool once the player is inside the tab.
func _update_hiring_badge() -> void:
	var unseen : int = GameState.player_club.scout_unseen
	var hiring_label := tr(HIRING_LABEL)
	hiring_button.text = "%s (%d)" % [hiring_label, unseen] if unseen > 0 else hiring_label

## Called by hub.gd when the Club tab itself is (re)shown, so the currently
## active sub-panel picks up state changed elsewhere (budget, squad, etc.).
func refresh() -> void:
	if _active_panel == "" or not _panel_instances.has(_active_panel):
		return
	var panel : Control = _panel_instances[_active_panel]
	if panel.has_method("refresh"):
		panel.refresh()

func _make_panel(key: String) -> Control:
	var scene : PackedScene = SUB_SECTIONS[key]
	if scene != null:
		return scene.instantiate()
	var placeholder : Control = PLACEHOLDER.instantiate()
	placeholder.title = key.capitalize()
	return placeholder

func _show_panel(key: String) -> void:
	if not _panel_instances.has(key):
		return
	if _active_panel != "":
		_panel_instances[_active_panel].visible = false
		_panel_instances[_active_panel].process_mode = Node.PROCESS_MODE_DISABLED
	_active_panel = key
	var panel : Control = _panel_instances[key]
	panel.process_mode = Node.PROCESS_MODE_INHERIT
	panel.visible = true
	if panel.has_method("refresh"):
		panel.refresh()

func _on_sub_nav_pressed(section: String) -> void:
	_show_panel(section)
	_maybe_play_sub_tutorial(section)

## Called by hub.gd right after the Club tab's own top-level tutorial finishes
## — Stadium is the sub-tab already showing by default, so it never gets a
## click of its own to trigger _on_sub_nav_pressed().
func maybe_play_default_sub_tutorial() -> void:
	_maybe_play_sub_tutorial(_active_panel)

func _maybe_play_sub_tutorial(key: String) -> void:
	var tutorial_key := "club_%s" % key
	if GameState.has_seen_tutorial(tutorial_key):
		return
	var lines : Array = SUB_TUTORIALS.get(key, [])
	if lines.is_empty():
		return
	var typed_lines : Array[String] = []
	typed_lines.assign(lines)
	ClubTrainer.say_lines(typed_lines)
	await ClubTrainer.finished
	GameState.mark_tutorial_seen(tutorial_key)
