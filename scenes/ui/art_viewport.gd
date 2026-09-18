@tool
extends SubViewportContainer

## Scales the 2D art inside a SubViewport to the frame that holds it.
##
## The stadium art used to render at a hard-coded Camera2D zoom, so on a wide
## window the building sat as a small island in the middle of a huge empty
## panel. `stretch = true` already resizes the SubViewport to this container, so
## all that's missing is re-deriving the camera zoom from the frame size.

## Design size of the art the camera is looking at, in world units.
@export var content_size : Vector2 = Vector2(1536, 1024)

## true  → fill the frame and crop the overflow (no empty borders).
## false → letterbox so the whole artwork stays visible.
@export var cover : bool = true

var _camera : Camera2D = null

func _ready() -> void:
	resized.connect(_fit)
	_fit()

func _fit() -> void:
	if _camera == null or not is_instance_valid(_camera):
		_camera = _find_camera(self)
	if _camera == null:
		return
	if size.x <= 0.0 or size.y <= 0.0 or content_size.x <= 0.0 or content_size.y <= 0.0:
		return
	var sx := size.x / content_size.x
	var sy := size.y / content_size.y
	var z := maxf(sx, sy) if cover else minf(sx, sy)
	_camera.zoom = Vector2(z, z)

func _find_camera(node: Node) -> Camera2D:
	for child in node.get_children(true):
		if child is Camera2D:
			return child
		var found := _find_camera(child)
		if found != null:
			return found
	return null
