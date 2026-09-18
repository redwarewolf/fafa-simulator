
## DebugDraw — global singleton for per-frame debug rendering.
## Usage from anywhere:
##   DebugDraw.line(from, to, color)               # lasts one frame
##   DebugDraw.line(from, to, color, 2.0)           # lasts 2 seconds
##   DebugDraw.cross(position, color)
## Lines with a duration persist until their time expires.
extends Node2D

## Master kill switch — false disables everything with zero overhead.
const ENABLED := false

## ── Per-category toggles ──────────────────────────────────────────────────────
## Shot / tackle range circles drawn per role each frame.
const SHOW_ROLE_RANGES := false
## Bicircular force radius circles (inner/outer) drawn per player each frame.
const SHOW_FORCE_RADII := false
## Pressing assignment lines (red primary, orange secondary defender).
const SHOW_PRESSING_LINES := false
## Marking assignment lines (yellow, defender → marked opponent).
const SHOW_MARKING_LINES := false
## Pass target lines and crosses drawn when a pass is played.
const SHOW_PASS_LINES := false
## Goalkeeper distribution lines (long kick / short pass targets).
const SHOW_GK_DISTRIBUTION := false
## Per-player movement intent: a line from every player to whatever point
## their AI is currently steering toward (press/mark/role target), color-coded
## by which of those it is. Diagnoses "why is this player going THERE"
## independent of what Locomotion's steering blend actually does with it.
const SHOW_INTENT_LINES := false
## Pitch-control heatmap: one filled cell per grid point, tinted by which
## team could reach it first (see scenes/characters/ai/pitch_control.gd —
## Phase 1 of docs/ai-overhaul.md). Empty/unpopulated until that lands; this
## toggle and rect_filled() exist ahead of it so Phase 1 has somewhere to draw.
const SHOW_PITCH_CONTROL := false

## Line width in pixels (screen space).
const LINE_WIDTH := 1.0

# Each entry: { from, to, color, expire_ms }
var _lines: Array[Dictionary] = []
# Each entry: { rect, color, expire_ms } — filled quads, e.g. heatmap cells.
var _rects: Array[Dictionary] = []

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
	var rects_still_alive: Array[Dictionary] = []
	for entry in _rects:
		if now < entry.expire_ms:
			draw_rect(entry.rect, entry.color, true)
			rects_still_alive.append(entry)
	_rects = rects_still_alive

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

## Draw a filled, axis-aligned world-space rect (e.g. a heatmap cell).
## [param duration_sec] — how many seconds it stays visible (default: one frame only).
func rect_filled(rect: Rect2, color: Color = Color.WHITE, duration_sec: float = 0.0) -> void:
	if ENABLED:
		var ms: int = max(17, int(duration_sec * 1000.0))
		_rects.append({ "rect": rect, "color": color, "expire_ms": Time.get_ticks_msec() + ms })
