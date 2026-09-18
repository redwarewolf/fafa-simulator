class_name DialogueBox
extends Control

## Visual-novel-style dialogue overlay: a speaker portrait on the left built
## from two stacked half-sprites, a typewriter-animated text box, and an
## optional image slot on the right for showcasing something related to the
## line (a crest, an event picture, etc).
##
## While a line is typing, the portrait's top half (head) bobs and tilts
## against the static bottom half (body/jaw) to fake speech, the way a hand
## puppet's head moves against its body. Click/tap or press accept to speed
## through the current line, then to advance to the next one.
##
## Usage:
##   dialogue_box.say([
##       DialogueLine.new("Tapir", top_tex, bottom_tex, "Hey, welcome!"),
##       DialogueLine.new("Tapir", top_tex, bottom_tex, "Let's get started."),
##   ])
##   await dialogue_box.finished

signal finished
signal line_started(line: DialogueLine)

@export var chars_per_second : float = 45.0

@export_group("Talk sound")
@export var talk_sound_volume_db : float = -14.0
## Random pitch jitter (+/-) applied around a character's base pitch each
## time the clip (re)starts, so back-to-back lines/loops don't sound identical.
@export var talk_sound_pitch_variance : float = 0.06
## When the clip finishes mid-line, restart from a random point within this
## fraction of its length instead of always from the top — samples a
## different "part" of the gibberish each time instead of repeating it verbatim.
@export var talk_sound_restart_range : float = 0.6

const _TALK_SOUND_STREAM := preload("res://assets/music/gibberish.mp3")

@export_group("Head bobble")
@export var talk_animation_speed : float = 2.0
@export var bob_amplitude_px : float = 4.0
@export var sway_amplitude_px : float = 3.0
@export var tilt_amplitude_deg : float = 4.0
@export var bob_frequency : float = 13.0
@export var sway_frequency : float = 6.5
@export var tilt_frequency : float = 9.5
@export var top_pivot_fraction : Vector2 = Vector2(0.5, 0.95)

@export_group("Portrait spritesheet animation")
## How long each frame of a multi-frame portrait (see DialogueLine) stays on
## screen while the line is typing.
@export var portrait_frame_interval : float = 0.18

@onready var _portrait_anchor : Control = $Stage/PortraitAnchor
@onready var _portrait_bottom : TextureRect = $Stage/PortraitAnchor/PortraitBottom
@onready var _portrait_top : TextureRect = $Stage/PortraitAnchor/PortraitTop
@onready var _right_content : Control = $Stage/RightContent
@onready var _right_image : TextureRect = $Stage/RightContent/RightImage
@onready var _name_plate : Control = $NamePlate
@onready var _name_label : Label = $NamePlate/NameLabel
@onready var _dialogue_label : RichTextLabel = $TextPanel/Margin/DialogueLabel
@onready var _continue_indicator : Label = $TextPanel/ContinueIndicator
@onready var _talk_sound : AudioStreamPlayer = $TalkSound

var _queue : Array[DialogueLine] = []
var _queue_index : int = -1
var _is_typing : bool = false
var _talk_time : float = 0.0
var _bob_amp : float = 0.0
var _char_progress : float = 0.0
var _talk_sound_pitch : float = CharacterVoices.DEFAULT_PITCH

## The portraits' textures are always an AtlasTexture (even for a plain
## single-frame portrait, where it's just a 1-frame "sheet") so frame-cycling
## code doesn't need a separate path for static portraits.
var _top_atlas := AtlasTexture.new()
var _bottom_atlas := AtlasTexture.new()
var _top_frame_count : int = 1
var _bottom_frame_count : int = 1
var _portrait_frame_index : int = 0
var _portrait_frame_timer : float = 0.0
## PortraitTop's rest position for the CURRENT frame — _animate_portrait's
## bob/sway/tilt is added on top of this rather than overwriting it. Recomputed
## whenever the cycling frame changes (see _apply_frame_offsets()), not just
## once per line, since it already bakes in that frame's offset correction.
var _portrait_top_base_position : Vector2 = Vector2.ZERO
## Centering + user-tuned offset only, before either per-frame correction or
## the talk animation — what _portrait_top_base_position/_portrait_bottom's
## position reset to at the start of each frame. Set by _layout_portrait(),
## consumed by _apply_frame_offsets().
var _portrait_top_rest_position : Vector2 = Vector2.ZERO
var _portrait_bottom_rest_position : Vector2 = Vector2.ZERO
## Auto-fit scale (box-width-derived) times the line's own top/bottom scale
## multiplier — how far _frame_offsets_for()'s texture-space pixel shifts
## need to be scaled to land correctly on screen. Set by _layout_portrait().
var _top_frame_scale : float = 1.0
var _bottom_frame_scale : float = 1.0
## Per-frame horizontal correction (texture-space pixels, frame-0-relative)
## for the currently-loaded top/bottom textures — see _frame_offsets_for().
var _top_frame_offsets : Array = []
var _bottom_frame_offsets : Array = []
## Texture2D -> Array[Vector2], memoized per texture since computing it scans
## every pixel — see _frame_offsets_for().
var _frame_offset_cache : Dictionary = {}

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_continue_indicator.visible = false
	_portrait_top.texture = _top_atlas
	_portrait_bottom.texture = _bottom_atlas
	_talk_sound.stream = _TALK_SOUND_STREAM
	_talk_sound.volume_db = talk_sound_volume_db
	_talk_sound.finished.connect(_on_talk_sound_finished)

func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	var pressed : bool = (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventKey and event.pressed and not event.echo
			and (event.keycode == KEY_SPACE or event.keycode == KEY_ENTER))
	if pressed:
		accept_event()
		_advance()

func _process(delta: float) -> void:
	if _is_typing:
		_type_step(delta)
		_advance_portrait_frame(delta)
	_animate_portrait(delta)

## Starts playing a queue of lines, showing the box if it was hidden.
func say(lines: Array[DialogueLine]) -> void:
	if lines.is_empty():
		return
	_queue = lines
	_queue_index = -1
	visible = true
	_advance()

## Convenience for a single speaker narrating several lines in a row with
## the same portrait (e.g. a day-summary narrator).
func say_lines(speaker_name: String, portrait_top: Texture2D, portrait_bottom: Texture2D,
		texts: Array[String], right_texture: Texture2D = null) -> void:
	var lines : Array[DialogueLine] = []
	for t in texts:
		lines.append(DialogueLine.new(speaker_name, portrait_top, portrait_bottom, t, right_texture))
	say(lines)

## Shows [param line]'s portrait fully typed, instantly, with no sound/talk
## animation — for scenes/ui/portrait_calibrator.tscn, which needs a stable
## still frame to tune against, not real dialogue playback. Not used by any
## real dialogue caller (see say()/say_lines()).
func preview(line: DialogueLine) -> void:
	visible = true
	_queue.clear()
	_queue_index = -1
	_is_typing = false
	_stop_talk_sound()
	_prepare_portrait(line)
	_right_content.visible = line.right_texture != null
	if line.right_texture != null:
		_right_image.texture = line.right_texture
	_dialogue_label.text = line.text
	_dialogue_label.visible_characters = -1
	_continue_indicator.visible = false

## Shared by _show_line() (real playback) and preview() (calibrator) — sets
## the speaker name plate, loads/sizes both portrait halves for [param line],
## and resets frame-cycling to frame 0.
func _prepare_portrait(line: DialogueLine) -> void:
	_name_label.text = line.speaker_name
	_name_plate.visible = not line.speaker_name.is_empty()
	if line.portrait_top != null:
		_top_frame_count = maxi(line.portrait_top_frames, 1)
		_setup_portrait_atlas(_top_atlas, line.portrait_top, _top_frame_count)
		_top_frame_offsets = _frame_offsets_for(line.portrait_top, _top_frame_count)
	if line.portrait_bottom != null:
		_bottom_frame_count = maxi(line.portrait_bottom_frames, 1)
		_setup_portrait_atlas(_bottom_atlas, line.portrait_bottom, _bottom_frame_count)
		_bottom_frame_offsets = _frame_offsets_for(line.portrait_bottom, _bottom_frame_count)
	_layout_portrait(line)
	_portrait_frame_index = 0
	_portrait_frame_timer = 0.0
	_update_portrait_atlas_frames()

func _advance() -> void:
	if _is_typing:
		_finish_typing()
		return
	_queue_index += 1
	if _queue_index >= _queue.size():
		_close()
		return
	_show_line(_queue[_queue_index])

func _show_line(line: DialogueLine) -> void:
	_prepare_portrait(line)
	if line.right_texture != null:
		_right_image.texture = line.right_texture
		_right_content.visible = true
	else:
		_right_content.visible = false
	_dialogue_label.text = line.text
	_dialogue_label.visible_characters = 0
	_char_progress = 0.0
	_continue_indicator.visible = false
	_is_typing = true
	_talk_sound_pitch = CharacterVoices.pitch_for(line.speaker_name)
	_play_talk_sound()
	line_started.emit(line)

func _type_step(delta: float) -> void:
	var total := _dialogue_label.get_total_character_count()
	_char_progress += delta * chars_per_second
	if _char_progress >= total:
		_finish_typing()
	else:
		_dialogue_label.visible_characters = int(_char_progress)

func _finish_typing() -> void:
	_dialogue_label.visible_characters = _dialogue_label.get_total_character_count()
	_is_typing = false
	_continue_indicator.visible = true
	_stop_talk_sound()

func _close() -> void:
	visible = false
	_queue.clear()
	_queue_index = -1
	_is_typing = false
	_talk_time = 0.0
	_stop_talk_sound()
	finished.emit()

func _play_talk_sound() -> void:
	_talk_sound.pitch_scale = _talk_sound_pitch + randf_range(-talk_sound_pitch_variance, talk_sound_pitch_variance)
	_talk_sound.play()

func _stop_talk_sound() -> void:
	if _talk_sound.playing:
		_talk_sound.stop()

## The clip finished on its own while the line was still typing - restart it
## from a random point (rather than always from the top) with a fresh pitch
## jitter, so a long line doesn't just loop the exact same sound verbatim.
func _on_talk_sound_finished() -> void:
	if not _is_typing:
		return
	var clip_length : float = _talk_sound.stream.get_length()
	var start_offset := 0.0
	if clip_length > 0.2:
		start_offset = randf_range(0.0, clip_length * talk_sound_restart_range)
	_talk_sound.pitch_scale = _talk_sound_pitch + randf_range(-talk_sound_pitch_variance, talk_sound_pitch_variance)
	_talk_sound.play(start_offset)

## Points [param atlas] at frame 0 of [param source], treated as a horizontal
## strip of [param frame_count] equal-width frames (1 = a plain static image).
func _setup_portrait_atlas(atlas: AtlasTexture, source: Texture2D, frame_count: int) -> void:
	var frame_width := source.get_width() / float(frame_count)
	atlas.atlas = source
	atlas.region = Rect2(0.0, 0.0, frame_width, source.get_height())

## Cycles both portrait halves' current frame together — a sheet with fewer
## frames than the other just loops faster within the same shared index.
func _advance_portrait_frame(delta: float) -> void:
	if _top_frame_count <= 1 and _bottom_frame_count <= 1:
		return
	_portrait_frame_timer += delta
	if _portrait_frame_timer < portrait_frame_interval:
		return
	_portrait_frame_timer -= portrait_frame_interval
	_portrait_frame_index += 1
	_update_portrait_atlas_frames()

func _update_portrait_atlas_frames() -> void:
	_set_atlas_frame(_top_atlas, _portrait_frame_index % _top_frame_count)
	_set_atlas_frame(_bottom_atlas, _portrait_frame_index % _bottom_frame_count)
	_apply_frame_offsets()

## Re-applies each half's per-frame horizontal correction (see
## _frame_offsets_for()) on top of its plain centering/user-offset rest
## position — called every time the cycling frame index changes, not just
## once per line, since the correction itself varies per frame.
func _apply_frame_offsets() -> void:
	var top_idx := _portrait_frame_index % _top_frame_count
	var top_shift := Vector2.ZERO
	if top_idx < _top_frame_offsets.size():
		top_shift = (_top_frame_offsets[top_idx] as Vector2) * _top_frame_scale
	_portrait_top_base_position = _portrait_top_rest_position + top_shift

	var bottom_idx := _portrait_frame_index % _bottom_frame_count
	var bottom_shift := Vector2.ZERO
	if bottom_idx < _bottom_frame_offsets.size():
		bottom_shift = (_bottom_frame_offsets[bottom_idx] as Vector2) * _bottom_frame_scale
	_portrait_bottom.position = _portrait_bottom_rest_position + bottom_shift

const _FRAME_OFFSET_ALPHA_THRESHOLD := 0.6

## Hand-drawn multi-frame portraits aren't always drawn re-centered within
## each equal-width atlas slice (e.g. Pepito Perinola's talking-head art —
## see club_trainer.gd) — without correction, cycling frames reads as the
## whole head sliding sideways instead of just talking. Measures each frame's
## alpha-weighted horizontal center of mass (ignoring faint anti-aliased/smoke
## pixels below the threshold) and returns, per frame, the texture-space pixel
## shift needed to bring it back in line with frame 0's. [] for a 1-frame
## (static) portrait. Memoized per texture since it's a full pixel scan.
func _frame_offsets_for(source: Texture2D, frame_count: int) -> Array:
	if frame_count <= 1:
		return []
	if _frame_offset_cache.has(source):
		return _frame_offset_cache[source]
	var offsets : Array = []
	var img := source.get_image()
	if img == null:
		_frame_offset_cache[source] = offsets
		return offsets
	if img.is_compressed():
		img = img.duplicate()
		img.decompress()
	var w := img.get_width()
	var h := img.get_height()
	var fw := float(w) / float(frame_count)
	var centers := PackedFloat32Array()
	for i in frame_count:
		var x0 := int(round(i * fw))
		var x1 := int(round((i + 1) * fw))
		var total := 0.0
		var weighted := 0.0
		for x in range(x0, x1):
			for y in h:
				var a := img.get_pixel(x, y).a
				if a > _FRAME_OFFSET_ALPHA_THRESHOLD:
					total += a
					weighted += a * (x - x0)
		centers.append(weighted / total if total > 0.0 else 0.0)
	for i in frame_count:
		offsets.append(Vector2(centers[0] - centers[i], 0.0))
	_frame_offset_cache[source] = offsets
	return offsets

func _set_atlas_frame(atlas: AtlasTexture, frame_index: int) -> void:
	var region := atlas.region
	region.position.x = frame_index * region.size.x
	atlas.region = region

## Sizes both portrait halves from a single scale derived from the top
## texture's frame width, instead of independently stretching each to fill
## its own fixed-size box. A speaker whose top/bottom art doesn't share the
## same aspect ratio (e.g. Pepito Perinola's spritesheet, cropped to 3
## unevenly-tall frames per half) would otherwise get its body non-uniformly
## squashed/stretched to fit, throwing the head and body out of proportion
## with each other and visibly misaligning at the neck. Grandi Tapir's
## top/bottom images already share one aspect ratio matching the old fixed
## box, so this reduces to the previous behavior for them.
func _layout_portrait(line: DialogueLine) -> void:
	var top_frame_size : Vector2 = _top_atlas.region.size
	var bottom_frame_size : Vector2 = _bottom_atlas.region.size
	if top_frame_size.x <= 0.0:
		return
	var box_width := _portrait_anchor.size.x
	var base_scale := box_width / top_frame_size.x
	_top_frame_scale = base_scale * line.portrait_top_scale
	_bottom_frame_scale = base_scale * line.portrait_bottom_scale
	var top_size := top_frame_size * _top_frame_scale
	var bottom_size := bottom_frame_size * _bottom_frame_scale
	_portrait_top.size = top_size
	_portrait_top.pivot_offset = top_size * top_pivot_fraction
	_portrait_top_rest_position = Vector2((box_width - top_size.x) * 0.5, 0.0) + line.portrait_top_offset
	_portrait_top_base_position = _portrait_top_rest_position
	_portrait_bottom.size = bottom_size
	var bottom_y := top_size.y * (1.0 - line.portrait_overlap_fraction)
	_portrait_bottom_rest_position = Vector2((box_width - bottom_size.x) * 0.5, bottom_y) + line.portrait_bottom_offset

func _animate_portrait(delta: float) -> void:
	var target_amp := 1.0 if _is_typing else 0.0
	_bob_amp = move_toward(_bob_amp, target_amp, delta * 6.0)
	if _bob_amp <= 0.0:
		_portrait_top.position = _portrait_top_base_position
		_portrait_top.rotation = 0.0
		return
	_talk_time += delta * talk_animation_speed
	var bob_y := -absf(sin(_talk_time * bob_frequency)) * bob_amplitude_px * _bob_amp
	var sway_x := sin(_talk_time * sway_frequency + 0.6) * sway_amplitude_px * _bob_amp
	var tilt := sin(_talk_time * tilt_frequency + 1.3) * tilt_amplitude_deg * _bob_amp
	_portrait_top.position = _portrait_top_base_position + Vector2(sway_x, bob_y)
	_portrait_top.rotation = deg_to_rad(tilt)
