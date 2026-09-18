extends Control

const TAPIR_TOP := preload("res://assets/art/characters/tapir-top.png")
const TAPIR_BOTTOM := preload("res://assets/art/characters/tapir-bottom.png")
const CLUB_PORTRAIT := preload("res://assets/art/football_club_logos/fc_portrait.png")

@onready var _dialogue_box : DialogueBox = $DialogueBox

func _ready() -> void:
	_dialogue_box.say([
		DialogueLine.new("Tapir", TAPIR_TOP, TAPIR_BOTTOM,
			"Hey there! I'm just a floating tapir head, here to test the dialogue system."),
		DialogueLine.new("Tapir", TAPIR_TOP, TAPIR_BOTTOM,
			"While I talk, my head should bob up and down and tilt a little, like I'm actually speaking."),
		DialogueLine.new("Tapir", TAPIR_TOP, TAPIR_BOTTOM,
			"You can also show something on the right side of the screen, like this club crest.",
			CLUB_PORTRAIT),
		DialogueLine.new("Tapir", TAPIR_TOP, TAPIR_BOTTOM,
			"Once I'm done talking, this box disappears. See you around!"),
	])
