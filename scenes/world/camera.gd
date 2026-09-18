class_name Camera
extends Camera2D

## LOCKED: follows the ball/carrier every frame, as before. FREE: holds still
## wherever the manager last dragged it, ignoring the ball entirely — see
## MatchHUD's camera toggle button.
enum Mode { LOCKED, FREE }

const DISTANCE_TARGET := 100
const SMOOTHING_BALL_CARRIED := 2
const SMOOTHING_BALL_DEFAULT := 8

## Zoom is a magnification factor (bigger = closer in, smaller = further out)
## relative to the scene's default of 0.6. Capped just below default on the
## wide end so free-look can't pull back far enough to show empty space past
## the pitch's edge (see limit_left/top/right/bottom on this node).
const ZOOM_MIN := 0.5
const ZOOM_MAX := 1.5
const ZOOM_STEP := 0.05

## World units/sec of arrow-key panning at zoom 1.0 — divided by the current
## zoom in _handle_free_pan() so it still covers the same amount of SCREEN per
## second when zoomed out, instead of crawling.
const PAN_SPEED := 500.0

@export var ball : Ball

var mode : Mode = Mode.LOCKED

var _dragging := false

func _process(delta: float) -> void:
	if mode != Mode.LOCKED:
		if mode == Mode.FREE:
			_handle_free_pan(delta)
		return
	if ball.carrier != null:
		position = ball.carrier.position + ball.carrier.heading * DISTANCE_TARGET
		position_smoothing_speed = SMOOTHING_BALL_CARRIED
	else:
		position = ball.position
		position_smoothing_speed = SMOOTHING_BALL_DEFAULT

## Arrow keys (Godot's built-in ui_* actions) pan the free camera, same as
## dragging with the mouse.
func _handle_free_pan(delta: float) -> void:
	var dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if dir != Vector2.ZERO:
		position += dir * PAN_SPEED * delta / zoom.x

func toggle_mode() -> void:
	set_mode(Mode.FREE if mode == Mode.LOCKED else Mode.LOCKED)

## Free-look drags feel laggy under position_smoothing (it interpolates
## towards wherever the drag just set `position`, trailing the mouse), so
## smoothing is only wanted while LOCKED is doing the driving.
func set_mode(new_mode: Mode) -> void:
	mode = new_mode
	position_smoothing_enabled = (mode == Mode.LOCKED)
	_dragging = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_by(ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_by(-ZOOM_STEP)
	if mode != Mode.FREE:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		position -= event.relative / zoom
		get_viewport().set_input_as_handled()

func _zoom_by(delta: float) -> void:
	var z := clampf(zoom.x + delta, ZOOM_MIN, ZOOM_MAX)
	zoom = Vector2(z, z)

