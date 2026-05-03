extends Control

@onready var club_name_label : Label = $Header/HeaderLayout/ClubSection/ClubName
@onready var date_label : Label = $Header/HeaderLayout/InfoSection/InfoLabels/Date
@onready var budget_label : Label = $Header/HeaderLayout/InfoSection/InfoLabels/MoneyDivision/Budget
@onready var division_label : Label = $Header/HeaderLayout/InfoSection/InfoLabels/MoneyDivision/Division
@onready var content : Control = $Content

const SECTIONS := {
	"squad": preload("res://scenes/hub/sections/squad/squad_section.tscn"),
	"market": preload("res://scenes/hub/sections/market/market_section.tscn"),
	"finances": preload("res://scenes/hub/sections/finances/finances_section.tscn"),
	"calendar": preload("res://scenes/hub/sections/calendar/calendar_section.tscn"),
	"tournament": preload("res://scenes/hub/sections/tournament/tournament_section.tscn"),
}

var _section_instances : Dictionary = {}
var _active_section : String = ""

func _ready() -> void:
	_preload_sections()
	_update_header()
	_show_section("squad")

func _preload_sections() -> void:
	for key in SECTIONS:
		var instance : Control = SECTIONS[key].instantiate()
		instance.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		# Use process_mode = DISABLED + hide instead of just hide.
		# Bare visible=false keeps the node in the scene tree and its canvas
		# items remain partially active, which causes stale-pixel ghost artifacts
		# when scrollable children (Tree, ScrollContainer) are later shown.
		instance.process_mode = Node.PROCESS_MODE_DISABLED
		instance.visible = false
		content.add_child(instance)
		_section_instances[key] = instance

func _update_header() -> void:
	club_name_label.text = GameState.player_club.display_name
	division_label.text = "Division %s" % GameState.player_club.division
	budget_label.text = "$%s" % _format_money(GameState.player_club.budget)
	date_label.text = GameState.get_date_string()

func _show_section(key: String) -> void:
	if not _section_instances.has(key):
		return
	if _active_section != "":
		_section_instances[_active_section].visible = false
		_section_instances[_active_section].process_mode = Node.PROCESS_MODE_DISABLED
	_active_section = key
	_section_instances[key].process_mode = Node.PROCESS_MODE_INHERIT
	_section_instances[key].visible = true

func _format_money(amount: int) -> String:
	var s := str(amount)
	var result := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = s[i] + result
		count += 1
	return result

func _on_nav_pressed(section: String) -> void:
	_show_section(section)

func _on_next_day_pressed() -> void:
	GameState.advance_day()
	_update_header()

func _on_test_match_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/world/world.tscn")
