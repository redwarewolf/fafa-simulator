extends Control

const PLACEHOLDER := preload("res://scenes/ui/placeholder_panel.tscn")

## Sub-section key → scene. `null` means "not built yet" and gets a framed
## placeholder instead of its own near-empty .tscn.
const SUB_SECTIONS := {
	"stadium": preload("res://scenes/hub/sections/club/stadium_panel.tscn"),
	"staff": preload("res://scenes/hub/sections/club/staff_panel.tscn"),
	"training": preload("res://scenes/hub/sections/club/training_panel.tscn"),
	# Gastos + Ingresos used to be two sub-tabs; finances_panel embeds both.
	"finances": preload("res://scenes/hub/sections/club/finances_panel.tscn"),
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
	"finances": [
		"Estas son las Finanzas. Arriba tenés la plata, cómo se movió desde ayer y la evolución día a día.",
		"Abajo, lo que entra — entradas, merchandising y comida — y lo que sale: sueldos del plantel y personal contratado, que se descuentan solos cada vez que avanzás el día.",
	],
	"hiring": [
		"Esta es la pestaña de Contrataciones. Acá aparecen los candidatos que te trae el ojeador — fichalos antes de que se enfríen.",
	],
}

@onready var sub_content : Control = $HBox/SubContent
@onready var sidebar : Control = $HBox/Sidebar
@onready var sidebar_layout : Control = $HBox/Sidebar/SidebarLayout
@onready var hiring_button : Button = $HBox/Sidebar/SidebarLayout/HiringButton

var _panel_instances : Dictionary = {}
var _active_panel : String = ""
var _sidebar_floor_width : float = 0.0

func _ready() -> void:
	_sidebar_floor_width = sidebar.custom_minimum_size.x
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

## The sidebar's width is tuned to fit the English nav labels ("Training",
## "Hiring", ...) but Spanish equivalents ("Entrenamiento", "Contrataciones")
## are wider and would spill into SubContent at that fixed width. Widen the
## sidebar here — after every button already has its translated text — so it
## fits whichever language is active instead of hardcoding a per-locale width.
func _resize_sidebar_for_locale() -> void:
	var widest := 0.0
	for child in sidebar_layout.get_children():
		if child is Button:
			widest = max(widest, child.get_minimum_size().x)
	var side_padding : float = sidebar_layout.offset_left - sidebar_layout.offset_right
	sidebar.custom_minimum_size.x = max(_sidebar_floor_width, widest + side_padding)

## Mirrors hub.gd's nav badge on the "Club" tab itself — this is the button
## that actually reveals the scout pool once the player is inside the tab.
func _update_hiring_badge() -> void:
	var unseen : int = GameState.player_club.scout_unseen
	var hiring_label := tr(HIRING_LABEL)
	hiring_button.text = "%s (%d)" % [hiring_label, unseen] if unseen > 0 else hiring_label
	_resize_sidebar_for_locale()

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
