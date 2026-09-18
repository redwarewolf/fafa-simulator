extends Control

## Dev tool: run this scene directly (editor "Run Current Scene", F6) to
## manually dial in a speaker's DialogueBox portrait alignment instead of
## guessing offsets/scale by eye and reloading the game over and over. Drag
## the controls on the right; the DialogueBox on the left updates live.
## Hit Save to write the current values to portrait_calibration.json next to
## the project (also printed to the Godot log) — read those off and paste
## them into the relevant speaker's constants (see club_trainer.gd's
## PORTRAIT_* consts for the pattern).
##
## Swap TOP/BOTTOM/SPEAKER_NAME below to calibrate a different speaker.

const TOP := preload("res://assets/art/characters/club-trainer-top.png")
const BOTTOM := preload("res://assets/art/characters/club-trainer-bottom.png")
const SPEAKER_NAME := "Pepito Perinola"
const PORTRAIT_FRAMES := 3

const SAVE_PATH := "res://portrait_calibration.json"

const DEFAULTS := {
	"top_scale": 1.0, "bottom_scale": 1.0,
	"top_offset_x": 0.0, "top_offset_y": 0.0,
	"bottom_offset_x": 0.0, "bottom_offset_y": 0.0,
	"overlap_fraction": 0.169,
}

const PREVIEW_TEXT := "This is a preview line — long enough to see the head bob/tilt animation while it types, so you can check the alignment while talking, not just at rest."

@onready var dialogue_box : DialogueBox = $DialogueBox
@onready var top_scale_box : SpinBox = %TopScale
@onready var bottom_scale_box : SpinBox = %BottomScale
@onready var top_offset_x_box : SpinBox = %TopOffsetX
@onready var top_offset_y_box : SpinBox = %TopOffsetY
@onready var bottom_offset_x_box : SpinBox = %BottomOffsetX
@onready var bottom_offset_y_box : SpinBox = %BottomOffsetY
@onready var overlap_box : SpinBox = %Overlap
@onready var values_label : Label = %ValuesLabel
@onready var save_button : Button = %SaveButton
@onready var reset_button : Button = %ResetButton
@onready var retype_button : Button = %RetypeButton

func _ready() -> void:
	_load_saved_or_defaults()
	for box in [top_scale_box, bottom_scale_box, top_offset_x_box, top_offset_y_box,
			bottom_offset_x_box, bottom_offset_y_box, overlap_box]:
		box.value_changed.connect(_on_value_changed)
	save_button.pressed.connect(_save)
	reset_button.pressed.connect(_reset)
	retype_button.pressed.connect(_retype)
	_refresh()

func _reset() -> void:
	top_scale_box.value = DEFAULTS["top_scale"]
	bottom_scale_box.value = DEFAULTS["bottom_scale"]
	top_offset_x_box.value = DEFAULTS["top_offset_x"]
	top_offset_y_box.value = DEFAULTS["top_offset_y"]
	bottom_offset_x_box.value = DEFAULTS["bottom_offset_x"]
	bottom_offset_y_box.value = DEFAULTS["bottom_offset_y"]
	overlap_box.value = DEFAULTS["overlap_fraction"]
	_refresh()

## Replays the line with the typewriter/head-bob animation running, so you
## can check alignment while the head is bobbing/tilting, not just at rest —
## the static preview() the sliders otherwise drive skips that entirely.
func _retype() -> void:
	dialogue_box.say([_current_line()])

func _on_value_changed(_v: float) -> void:
	_refresh()

func _current_line() -> DialogueLine:
	var line := DialogueLine.new(SPEAKER_NAME, TOP, BOTTOM, PREVIEW_TEXT, null,
		PORTRAIT_FRAMES, PORTRAIT_FRAMES, overlap_box.value)
	line.portrait_top_scale = top_scale_box.value
	line.portrait_bottom_scale = bottom_scale_box.value
	line.portrait_top_offset = Vector2(top_offset_x_box.value, top_offset_y_box.value)
	line.portrait_bottom_offset = Vector2(bottom_offset_x_box.value, bottom_offset_y_box.value)
	return line

func _refresh() -> void:
	dialogue_box.preview(_current_line())
	values_label.text = _format_values()

func _format_values() -> String:
	return (
		"const PORTRAIT_OVERLAP_FRACTION := %.3f\n" +
		"const PORTRAIT_TOP_SCALE := %.3f\n" +
		"const PORTRAIT_BOTTOM_SCALE := %.3f\n" +
		"const PORTRAIT_TOP_OFFSET := Vector2(%d, %d)\n" +
		"const PORTRAIT_BOTTOM_OFFSET := Vector2(%d, %d)"
	) % [
		overlap_box.value, top_scale_box.value, bottom_scale_box.value,
		top_offset_x_box.value, top_offset_y_box.value,
		bottom_offset_x_box.value, bottom_offset_y_box.value,
	]

func _save() -> void:
	var data := {
		"top_scale": top_scale_box.value, "bottom_scale": bottom_scale_box.value,
		"top_offset_x": top_offset_x_box.value, "top_offset_y": top_offset_y_box.value,
		"bottom_offset_x": bottom_offset_x_box.value, "bottom_offset_y": bottom_offset_y_box.value,
		"overlap_fraction": overlap_box.value,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		printerr("portrait_calibrator: could not open %s for writing" % SAVE_PATH)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	print("Portrait calibration saved to %s:\n%s" % [SAVE_PATH, _format_values()])

func _load_saved_or_defaults() -> void:
	var data : Dictionary = DEFAULTS.duplicate()
	if FileAccess.file_exists(SAVE_PATH):
		var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
		var json := JSON.new()
		if json.parse(file.get_as_text()) == OK:
			data.merge(json.data, true)
		file.close()
	top_scale_box.value = data["top_scale"]
	bottom_scale_box.value = data["bottom_scale"]
	top_offset_x_box.value = data["top_offset_x"]
	top_offset_y_box.value = data["top_offset_y"]
	bottom_offset_x_box.value = data["bottom_offset_x"]
	bottom_offset_y_box.value = data["bottom_offset_y"]
	overlap_box.value = data["overlap_fraction"]
