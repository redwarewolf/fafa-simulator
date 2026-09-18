class_name PositionMap
extends Control

## Pitch-shaped map of which positions a player covers: bright where they are
## natural, dimmed where they are accomplished, inert everywhere else.
##
## This is the piece that makes dropping someone into the wrong slot legible
## BEFORE kickoff rather than after it — a striker and a full back are both
## "an outfield player" until you can see what each of them actually covers.

## Grid layout, front line first so it reads like the pitch drawn upright.
## Empty strings are spacers.
const LAYOUT : Array = [
	[Positions.Role.ST],
	[Positions.Role.LW, Positions.Role.CAM, Positions.Role.RW],
	[Positions.Role.LM, Positions.Role.CM, Positions.Role.RM],
	[Positions.Role.CDM],
	[Positions.Role.LB, Positions.Role.CB, Positions.Role.RB],
	[Positions.Role.GK],
]

const INERT_FILL := Color(0.16, 0.31, 0.36, 1.0)
const INERT_INK  := Color(0.36, 0.49, 0.55, 1.0)
const SECONDARY_ALPHA := 0.45

var _role : Positions.Role = Positions.Role.CM
var _has_player : bool = false

func set_player_role(role: Positions.Role) -> void:
	_role = role
	_has_player = true
	queue_redraw()

func clear() -> void:
	_has_player = false
	queue_redraw()

func _draw() -> void:
	if not _has_player:
		return
	var font := get_theme_default_font()
	var rows := LAYOUT.size()
	var gap := 3.0
	var cell_h := (size.y - gap * (rows - 1)) / float(rows)
	if cell_h < 6.0:
		return
	var cell_w := minf((size.x - gap * 2.0) / 3.0, cell_h * 2.6)
	var font_size := int(clampf(cell_h * 0.62, 7.0, 12.0))

	for r in rows:
		var row : Array = LAYOUT[r]
		var total_w := cell_w * row.size() + gap * (row.size() - 1)
		var x := (size.x - total_w) * 0.5
		var y := r * (cell_h + gap)
		for slot_role in row:
			_draw_chip(font, font_size, Rect2(x, y, cell_w, cell_h), slot_role)
			x += cell_w + gap

func _draw_chip(font: Font, font_size: int, rect: Rect2, slot_role: Positions.Role) -> void:
	var fill := INERT_FILL
	var ink := INERT_INK
	match Positions.aptitude(_role, slot_role):
		Positions.Aptitude.NATURAL:
			fill = Positions.color(slot_role)
			ink = Positions.ink_on(slot_role)
		Positions.Aptitude.SECONDARY:
			fill = Color(Positions.color(slot_role), SECONDARY_ALPHA)
			ink = Color(Positions.ink_on(slot_role), 0.75)
	draw_rect(rect, fill)
	var label := Positions.label(slot_role)
	var extent := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(font, rect.position + Vector2((rect.size.x - extent.x) * 0.5,
		(rect.size.y + extent.y * 0.62) * 0.5), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink)
