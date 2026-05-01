extends Control

const PADDING := 16

@export var quality_tier : int = 0 :
	set(value):
		quality_tier = value
		_apply_quality()

@onready var background : NinePatchRect = $Background

func _ready() -> void:
	_apply_quality()

func _apply_quality() -> void:
	if background and background.material:
		background.material.set_shader_parameter("quality_tier", quality_tier)
