## DebugDraw — global singleton for per-frame debug rendering.
## Usage from anywhere:
##   DebugDraw.line(from, to, color)               # lasts one frame
##   DebugDraw.line(from, to, color, 2.0)           # lasts 2 seconds
##   DebugDraw.cross(position, color)
## Lines with a duration persist until their time expires.
extends Node2D

## Set to false to disable all debug drawing with zero overhead.
const ENABLED := true

## Line width in pixels (screen space).
const LINE_WIDTH := 1.0

# Each entry: { from, to, color, expire_ms }
var _lines: Array[Dictionary] = []

func _ready() -> void:
	z_index = 100  # Draw above all gameplay sprites

func _process(_delta: float) -> void:
	if ENABLED:
		queue_redraw()

func _draw() -> void:
	if not ENABLED:
		return
	var now := Time.get_ticks_msec()
	var still_alive: Array[Dictionary] = []
	for entry in _lines:
		if now < entry.expire_ms:
			draw_line(entry.from, entry.to, entry.color, LINE_WIDTH)
			still_alive.append(entry)
	_lines = still_alive

## Draw a line between two world positions.
## [param duration_sec] — how many seconds the line stays visible (default: one frame only).
func line(from: Vector2, to: Vector2, color: Color = Color.WHITE, duration_sec: float = 0.0) -> void:
	if ENABLED:
		# Guarantee at least one frame of visibility (~17 ms at 60 fps) so
		# per-frame draws (duration=0) survive until _draw() is called.
		var ms: int = max(17, int(duration_sec * 1000.0))
		_lines.append({ "from": from, "to": to, "color": color, "expire_ms": Time.get_ticks_msec() + ms })

## Draw a cross/X marker at a world position.
func cross(pos: Vector2, color: Color = Color.WHITE, size: float = 5.0, duration_sec: float = 0.0) -> void:
	if ENABLED:
		line(pos + Vector2(-size, -size), pos + Vector2(size, size), color, duration_sec)
		line(pos + Vector2(size, -size), pos + Vector2(-size, size), color, duration_sec)

## Draw a circle outline approximated by [param segments] line segments.
func circle(center: Vector2, radius: float, color: Color = Color.WHITE, duration_sec: float = 0.0, segments: int = 20) -> void:
	if not ENABLED or radius <= 0.0:
		return
	for i in segments:
		var a := (float(i) / segments) * TAU
		var b := (float(i + 1) / segments) * TAU
		line(center + Vector2(cos(a), sin(a)) * radius,
			 center + Vector2(cos(b), sin(b)) * radius,
			 color, duration_sec)
