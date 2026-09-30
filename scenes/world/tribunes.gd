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


## The match's standing mood (the home barra's — see BarraBrava.match_effect()),
## which react() returns to.
var _base_mood := TribuneSection.MOOD_NEUTRAL
var _base_share := 0.0
var _reaction_id := 0

func set_base_mood(mood: int, share: float) -> void:
	_base_mood = mood
	_base_share = share
	_show_mood(mood, share)

## A burst of [param mood] from [param share] of the crowd (a goal), for
## [param seconds] of match time, then back to the base mood.
func react(mood: int, share: float, seconds: float) -> void:
	_reaction_id += 1
	var id := _reaction_id
	_show_mood(mood, share)
	await get_tree().create_timer(seconds).timeout
	if id == _reaction_id:  # a later goal's reaction owns the stands now
		_show_mood(_base_mood, _base_share)

func _show_mood(mood: int, share: float) -> void:
	for section in sections:
		if section.visible:
			section.set_mood(mood, share)

func set_fan_colors(primary: Color, secondary: Color) -> void:
	for section in sections:
		section.set_fan_colors(primary, secondary)
