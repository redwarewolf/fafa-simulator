extends CanvasLayer

## Global narrator for random events — Pepito Perinola, using the exact same
## visual-novel DialogueBox as Grandi Tapir's Hub dialogue, just reachable
## from anywhere (Hub or Match) since this is registered as the "ClubTrainer"
## autoload (project.godot). Being a CanvasLayer autoload means it renders
## above whichever scene is current without any per-scene wiring. No
## class_name here — Godot forbids one that shadows an autoload's own name.
##
## Usage:
##   var line := RandomEvents.maybe_trigger_hub_event(GameState.player_club)
##   if not line.is_empty():
##       ClubTrainer.say(line)
##       await ClubTrainer.finished

signal finished

const TOP := preload("res://assets/art/characters/club-trainer-top.png")
const BOTTOM := preload("res://assets/art/characters/club-trainer-bottom.png")
## Both TOP and BOTTOM are 1x3 spritesheets (a talking-head animation), not
## three separate portraits — see DialogueLine.portrait_top_frames.
const PORTRAIT_FRAMES := 3
## Unlike Grandi Tapir's top/bottom art (split cleanly at the neck), TOP
## already draws down to the chin and BOTTOM's art starts a bit above it
## (chin + cigarette), so the two have to overlap rather than stack edge to
## edge or the jaw doubles up at the seam. Tune these with
## scenes/ui/portrait_calibrator.tscn (run it directly in the editor, dial in
## the sliders, hit Save, then copy its printed values here) rather than
## guessing by eye — see DialogueLine's portrait_* fields for what each one does.
const PORTRAIT_OVERLAP_FRACTION := 0.17
const PORTRAIT_TOP_SCALE := 0.75
const PORTRAIT_BOTTOM_SCALE := 0.75
const PORTRAIT_TOP_OFFSET := Vector2(39, 73)
const PORTRAIT_BOTTOM_OFFSET := Vector2(0, 92)
const SPEAKER_NAME := "Pepito Perinola"

@onready var _dialogue_box : DialogueBox = $DialogueBox

func _ready() -> void:
	layer = 10  # above Hub/Match content, above the match's GameOverOverlay CanvasLayer
	_dialogue_box.finished.connect(func() -> void: finished.emit())

func say(text: String) -> void:
	if text.is_empty():
		return
	_dialogue_box.say([_make_line(text)])

func say_lines(texts: Array[String]) -> void:
	if texts.is_empty():
		return
	var lines : Array[DialogueLine] = []
	for t in texts:
		lines.append(_make_line(t))
	_dialogue_box.say(lines)

func _make_line(text: String) -> DialogueLine:
	return DialogueLine.new(SPEAKER_NAME, TOP, BOTTOM, text, null,
		PORTRAIT_FRAMES, PORTRAIT_FRAMES, PORTRAIT_OVERLAP_FRACTION,
		PORTRAIT_TOP_SCALE, PORTRAIT_BOTTOM_SCALE,
		PORTRAIT_TOP_OFFSET, PORTRAIT_BOTTOM_OFFSET)
