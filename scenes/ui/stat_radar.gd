class_name StatRadar
extends Control

## Hexagonal radar of a player's six stats.
##
## Six bars answer "how good is this number"; the hexagon answers "what SHAPE of
## player is this", which is the question the squad screen is actually asking —
## a 90-pace 30-defence winger and a balanced midfielder read apart instantly.

const AXES : Array[String] = ["PAC", "SHO", "PAS", "DRI", "DEF", "PHY"]
const MAX_STAT := 100.0
const RINGS : Array[float] = [0.33, 0.66]

const GRID_COLOR  := Color(0.23, 0.37, 0.43, 1.0)
const WEB_COLOR   := Color(0.35, 0.63, 0.74, 1.0)
const WEB_FILL    := Color(0.06, 0.20, 0.25, 0.55)
const LABEL_COLOR := Color(0.62, 0.72, 0.78, 1.0)

## Effective (modified) values — drives the web shape, since that's the
## player's real in-game strength.
var _values : Array[int] = [0, 0, 0, 0, 0, 0]
## Base (unmodified) values — drawn in the neutral caption color, with any
## delta from _values appended as a colored suffix. See _draw().
var _base_values : Array[int] = [0, 0, 0, 0, 0, 0]
var _color : Color = Color.WHITE

## [param base_values]/[param effective_values] both in AXES order: pac, sho,
## pas, dri, def, phy.
func set_stats(base_values: Array, effective_values: Array, color: Color) -> void:
	_base_values.clear()
	for v in base_values:
		_base_values.append(int(v))
	_values.clear()
	for v in effective_values:
		_values.append(int(v))
	_color = color
	queue_redraw()

func _draw() -> void:
	if _values.size() < AXES.size():
		return
	var font := get_theme_default_font()
	var font_size := int(maxf(8.0, size.y * 0.058))
	# Leave room for the axis captions so the outer ring never clips them.
	var margin := font_size * 2.6
	var radius := minf(size.x, size.y) * 0.5 - margin
	if radius <= 4.0:
		return
	var centre := size * 0.5

	for ring in RINGS:
		draw_polyline(_hexagon(centre, radius * ring), GRID_COLOR, 1.0, true)
	draw_polygon(_hexagon(centre, radius), PackedColorArray([WEB_FILL]))
	draw_polyline(_hexagon(centre, radius), WEB_COLOR, 2.0, true)
	for i in AXES.size():
		draw_line(centre, _point(centre, radius, i), GRID_COLOR, 1.0, true)

	var web := PackedVector2Array()
	for i in AXES.size():
		web.append(_point(centre, radius * (clampf(_values[i], 0, MAX_STAT) / MAX_STAT), i))
	draw_polygon(web, PackedColorArray([Color(_color, 0.32)]))
	web.append(web[0])
	draw_polyline(web, _color, 2.0, true)
	for i in web.size() - 1:
		draw_circle(web[i], 2.5, _color)

	for i in AXES.size():
		# Base stat stays the neutral caption color; a nonzero modifier appends
		# a colored "+9"/"-4" suffix — same white-base/green-red-delta split
		# as the bars layout (see StatModifierStyle).
		var base_caption := "%s %d" % [AXES[i], _base_values[i]]
		var delta := _values[i] - _base_values[i]
		var delta_caption := "" if delta == 0 else " %+d" % delta
		var at := _point(centre, radius + font_size * 1.5, i)
		var base_extent := font.get_string_size(base_caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var delta_extent := font.get_string_size(delta_caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var total_w := base_extent.x + delta_extent.x
		var start := at + Vector2(-total_w * 0.5, base_extent.y * 0.32)
		draw_string(font, start, base_caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, LABEL_COLOR)
		if delta != 0:
			draw_string(font, start + Vector2(base_extent.x, 0), delta_caption,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, StatModifierStyle.color_for_delta(delta))

## Vertex [param index] of a hexagon, starting at the top and going clockwise.
func _point(centre: Vector2, radius: float, index: int) -> Vector2:
	var angle := -PI * 0.5 + TAU * (float(index) / float(AXES.size()))
	return centre + Vector2(cos(angle), sin(angle)) * radius

func _hexagon(centre: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in AXES.size():
		points.append(_point(centre, radius, i))
	points.append(points[0])
	return points
