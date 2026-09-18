class_name DialogueLine
extends Resource

## One line of dialogue: who's speaking, their portrait halves, the text,
## and an optional image to show on the right side of the box (e.g. an
## event illustration, a club crest — purely decorative, DialogueBox does
## not interpret it).
##
## portrait_top/portrait_bottom may each be a horizontal spritesheet of
## portrait_top_frames/portrait_bottom_frames equal-width frames (e.g. a
## talking-head animation) instead of a single static image — DialogueBox
## cycles through them while the line is typing. Defaults to 1 (a plain
## static portrait, e.g. Grandi Tapir's).

@export var speaker_name : String = ""
@export var portrait_top : Texture2D = null
@export var portrait_bottom : Texture2D = null
@export var portrait_top_frames : int = 1
@export var portrait_bottom_frames : int = 1
## Fraction of the (scaled) top portrait's height that the bottom portrait
## should tuck up underneath it. Some portrait art draws the chin/jaw on
## both halves (so the mouth still lines up regardless of how the top half
## bobs while talking) rather than splitting cleanly at the neck like Grandi
## Tapir's — for those, 0 leaves a doubled jaw at the seam.
@export var portrait_overlap_fraction : float = 0.0
## Per-half fine-tuning on top of the automatic box-fit scale (see
## DialogueBox._layout_portrait()) — 1.0 leaves that half exactly as auto-fit
## sizes it. Independent top/bottom scale exists because the two halves of a
## speaker's art aren't always drawn at the same native pixel density; a
## uniform scale (locked to the top half's width) can leave the bottom
## looking stretched/undersized relative to the top. Tune with
## scenes/ui/portrait_calibrator.tscn rather than guessing by eye.
@export var portrait_top_scale : float = 1.0
@export var portrait_bottom_scale : float = 1.0
## Per-half pixel nudge applied after auto-fit scale/position and the overlap
## offset — for fixing a residual seam/centering mismatch the scale and
## overlap knobs alone can't reach. Also tuned via portrait_calibrator.tscn.
@export var portrait_top_offset : Vector2 = Vector2.ZERO
@export var portrait_bottom_offset : Vector2 = Vector2.ZERO
@export var text : String = ""
@export var right_texture : Texture2D = null

func _init(p_speaker_name: String = "", p_portrait_top: Texture2D = null,
		p_portrait_bottom: Texture2D = null, p_text: String = "",
		p_right_texture: Texture2D = null, p_portrait_top_frames: int = 1,
		p_portrait_bottom_frames: int = 1, p_portrait_overlap_fraction: float = 0.0,
		p_portrait_top_scale: float = 1.0, p_portrait_bottom_scale: float = 1.0,
		p_portrait_top_offset: Vector2 = Vector2.ZERO,
		p_portrait_bottom_offset: Vector2 = Vector2.ZERO) -> void:
	speaker_name = p_speaker_name
	portrait_top = p_portrait_top
	portrait_bottom = p_portrait_bottom
	text = p_text
	right_texture = p_right_texture
	portrait_top_frames = p_portrait_top_frames
	portrait_bottom_frames = p_portrait_bottom_frames
	portrait_overlap_fraction = p_portrait_overlap_fraction
	portrait_top_scale = p_portrait_top_scale
	portrait_bottom_scale = p_portrait_bottom_scale
	portrait_top_offset = p_portrait_top_offset
	portrait_bottom_offset = p_portrait_bottom_offset
