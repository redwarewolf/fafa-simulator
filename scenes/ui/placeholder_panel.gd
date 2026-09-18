extends Control

## Framed "coming soon" filler for Hub sub-sections that have no content yet.
## Replaces the four near-identical bare-Label panels (staff/training/costs/
## earnings): an unframed Control left the window's raw grey clear colour
## showing through the whole content area.

@export var title : String = "Sección" :
	set(value):
		title = value
		if is_node_ready():
			_apply()

@onready var _title   : Label = $Center/VBox/Title
@onready var _message : Label = $Center/VBox/Message

func _ready() -> void:
	_apply()

func _apply() -> void:
	_title.text = tr(title).to_upper()
	_message.add_theme_color_override("font_color", HubPalette.MUTED)
