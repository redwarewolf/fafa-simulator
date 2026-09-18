class_name Tribunes
extends Node2D

## Owns the TribuneSection instances placed along the stadium's top wall.
## Shows only the sections unlocked by the club's "tribune" upgrade level and
## fills their seats to reflect a match's attendance. Both methods are meant
## to be called exactly once per match, from MatchWorld._ready() — see
## world.gd for why kickoff_ready (fires once per goal, not at match start)
## is not the right hook.

const BASE_ACTIVE_SECTIONS := 4
const SECTIONS_PER_UPGRADE_LEVEL := 2

@onready var sections : Array = get_children() # Array[TribuneSection], left-to-right


func configure_for_tribune_level(tribune_level: int) -> void:
	var active := mini(sections.size(), BASE_ACTIVE_SECTIONS + tribune_level * SECTIONS_PER_UPGRADE_LEVEL)
	for i in sections.size():
		sections[i].visible = i < active


func fill_active_sections(rate: float) -> void:
	for section in sections:
		if section.visible:
			section.fill_seats(rate)


func set_fan_colors(primary: Color, secondary: Color) -> void:
	for section in sections:
		section.set_fan_colors(primary, secondary)
