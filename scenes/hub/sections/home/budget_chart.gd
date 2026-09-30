extends Control

## Tiny line chart of the club's daily closing budget (GameState.budget_history
## plus today's live value) for the Home screen's finance card. Gold line over
## a faint fill; a dashed zero line appears only once the budget has dipped
## into the red, so a healthy club's chart isn't flattened by a $0 baseline.

const LINE_COLOR := Color(1.0, 0.85, 0.2, 1.0)
const FILL_COLOR := Color(1.0, 0.85, 0.2, 0.12)
const ZERO_COLOR := Color(0.9, 0.4, 0.4, 0.7)
const GRID_COLOR := Color(1, 1, 1, 0.08)
const PAD := 4.0

var _values : Array = []

func set_values(values: Array) -> void:
	_values = values
	queue_redraw()

func _draw() -> void:
	var rect := Rect2(Vector2(PAD, PAD), size - Vector2(PAD, PAD) * 2.0)
	for i in 3:
		var y := rect.position.y + rect.size.y * i / 2.0
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), GRID_COLOR)
	if _values.size() < 2:
		return

	var lo : float = _values.min()
	var hi : float = _values.max()
	if lo < 0.0:
		hi = maxf(hi, 0.0)
	if is_equal_approx(lo, hi):
		lo -= 1.0
		hi += 1.0

	var points := PackedVector2Array()
	for i in _values.size():
		var x := rect.position.x + rect.size.x * i / float(_values.size() - 1)
		var t := (float(_values[i]) - lo) / (hi - lo)
		points.append(Vector2(x, rect.end.y - rect.size.y * t))

	var fill := points.duplicate()
	fill.append(Vector2(rect.end.x, rect.end.y))
	fill.append(Vector2(rect.position.x, rect.end.y))
	draw_colored_polygon(fill, FILL_COLOR)

	if lo < 0.0:
		var zero_y := rect.end.y - rect.size.y * (0.0 - lo) / (hi - lo)
		draw_dashed_line(Vector2(rect.position.x, zero_y), Vector2(rect.end.x, zero_y), ZERO_COLOR, 1.0, 4.0)

	draw_polyline(points, LINE_COLOR, 2.0)
	draw_circle(points[points.size() - 1], 3.0, LINE_COLOR)
