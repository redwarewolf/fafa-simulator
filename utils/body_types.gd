class_name BodyTypes

## Registry of playable spritesheets, keyed by the id stored in
## PlayerResource.body_type / Player.body_type. Every entry describes the
## Sprite2D setup (texture + grid) needed to reskin a Player instance, plus an
## optional named AnimationLibrary (added to player.tscn's AnimationPlayer)
## for body types whose grid doesn't match the default animation set.
## Frames worth showing on a portrait — every non-prone pose actually used by
## an animation in player.tscn (idle/run/walk/celebrate/header/tackle/kicks),
## minus hurt/dive/mourn, which read as "on the ground" when frozen and cropped
## to a headshot square instead of seen mid-animation.
const _DEFAULT_PORTRAIT_FRAMES : Array[int] = [
	0, 1, 2, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17,
	18, 24, 25, 30, 36, 37, 38, 39, 42, 48, 49, 50, 51,
	78, 79, 80, 81, 82, 83,
]

const DATA : Dictionary = {
	"default": {
		"texture": preload("res://assets/art/characters/soccer-player.png"),
		"hframes": 6, "vframes": 14,
		"portrait_frames": _DEFAULT_PORTRAIT_FRAMES,
	},
	"fat": {
		"texture": preload("res://assets/art/characters/soccer-player-fat.png"),
		"hframes": 6, "vframes": 14,
		"portrait_frames": _DEFAULT_PORTRAIT_FRAMES,
	},
	"cone": {
		"texture": preload("res://assets/art/characters/cone-player.png"),
		"hframes": 6, "vframes": 14,
		"animation_library": "cone",
		"portrait_frames": [0],
	},
}

## Chance of rolling the "fat" body instead of "default" for a normal player,
## indexed by PlayerResource.Quality — rarer players are less likely to be fat.
const FAT_BODY_ODDS : Array[float] = [0.90, 0.60, 0.30, 0.10, 0.01]

static func roll_body_type(quality: PlayerResource.Quality) -> String:
	return "fat" if randf() < FAT_BODY_ODDS[quality] else "default"

## Picks a random frame from this body type's set of portrait-worthy poses —
## a fresh one each call, so the same player can be shown mid-run in one panel
## and mid-kick in another rather than being pinned to a single "official" pose.
static func roll_portrait_frame(body_type: String) -> int:
	var frames : Array = DATA.get(body_type, DATA["default"])["portrait_frames"]
	return frames[randi() % frames.size()]
