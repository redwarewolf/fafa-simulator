extends Control

## Win / draw / loss split drawn as one three-segment bar (green / grey / red)
## with each percentage printed inside its own segment — reads at a glance
## where the old "Victoria 36% · Empate 25% · Derrota 38%" sentence had to be
## parsed. Segments too narrow for their label just stay unlabelled.

const WIN_COLOR  := Color(0.3, 0.75, 0.35, 1.0)
const DRAW_COLOR := Color(0.55, 0.6, 0.63, 1.0)
const LOSS_COLOR := Color(0.85, 0.33, 0.3, 1.0)
const INK        := Color(0.04, 0.1, 0.12, 1.0)
const GAP := 2.0

var _odds : Array = [0.0, 0.0, 0.0]

func set_odds(win: float, draw: float, loss: float) -> void:
	_odds = [win, draw, loss]
	queue_redraw()

func _draw() -> void:
	var total : float = _odds[0] + _odds[1] + _odds[2]
	if total <= 0.0:
		return
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	var colors := [WIN_COLOR, DRAW_COLOR, LOSS_COLOR]
	var usable := size.x - GAP * 2.0
	var x := 0.0
	for i in 3:
		var w : float = usable * _odds[i] / total
		if w <= 0.0:
			continue
		draw_rect(Rect2(x, 0.0, w, size.y), colors[i])
		var text := "%d%%" % roundi(_odds[i] / total * 100.0)
		var extent := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		if extent.x + 6.0 <= w:
			draw_string(font, Vector2(x + (w - extent.x) * 0.5, (size.y + extent.y * 0.62) * 0.5),
				text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, INK)
		x += w + GAP
