extends Node2D

## Standalone visual comparison scene: the old zombie look (soccer-player.png
## reskinned green via the RADIOACTIVE entry in replace_color.gdshader) side
## by side with the new dedicated zombie_test.png spritesheet. Not wired into
## any game flow — launched directly for a one-off art review.
##
## zombie_test.png is 672x1568 against soccer-player.png's 192x448, but both
## use the same 6x14 grid, so it's a straight 3.5x-larger frame (112px vs
## 32px) with (as far as this scene assumes) matching frame indices/poses.
## NewSprite/NewSpriteZoomed are scaled down by 32.0/112.0 to land back on
## soccer-player.png's in-game character size.

const MAX_FRAME := 6 * 14 - 1
const PLAY_FPS := 6.0

@onready var old_sprite : Sprite2D = %OldSprite
@onready var new_sprite : Sprite2D = %NewSprite
@onready var old_sprite_zoomed : Sprite2D = %OldSpriteZoomed
@onready var new_sprite_zoomed : Sprite2D = %NewSpriteZoomed
@onready var frame_label : Label = %FrameLabel
@onready var prev_button : Button = %PrevButton
@onready var next_button : Button = %NextButton
@onready var play_button : Button = %PlayButton
@onready var play_timer : Timer = %PlayTimer

var frame_index := 0

func _ready() -> void:
	prev_button.pressed.connect(_on_prev_pressed)
	next_button.pressed.connect(_on_next_pressed)
	play_button.toggled.connect(_on_play_toggled)
	play_timer.wait_time = 1.0 / PLAY_FPS
	play_timer.timeout.connect(_on_play_timer_timeout)
	_apply_frame()

func _on_prev_pressed() -> void:
	frame_index = wrapi(frame_index - 1, 0, MAX_FRAME + 1)
	_apply_frame()

func _on_next_pressed() -> void:
	frame_index = wrapi(frame_index + 1, 0, MAX_FRAME + 1)
	_apply_frame()

func _on_play_toggled(pressed: bool) -> void:
	if pressed:
		play_timer.start()
	else:
		play_timer.stop()

func _on_play_timer_timeout() -> void:
	frame_index = wrapi(frame_index + 1, 0, MAX_FRAME + 1)
	_apply_frame()

func _apply_frame() -> void:
	old_sprite.frame = frame_index
	new_sprite.frame = frame_index
	old_sprite_zoomed.frame = frame_index
	new_sprite_zoomed.frame = frame_index
	frame_label.text = "Frame %d / %d" % [frame_index, MAX_FRAME]
