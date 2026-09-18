class_name SpecialPlayerTypes

## Registry of non-standard player archetypes, keyed by the id stored in
## PlayerResource.special_type / Player.special_type. "" (not present here)
## always means an ordinary player — every accessor below returns the normal-
## player default when passed an unknown/empty id, so callers never need an
## extra "is this special" branch of their own.
const DATA : Dictionary = {
	"cone": {
		"body_type": "cone",
		"forced_quality": PlayerResource.Quality.COMMON,
		"forced_stats": 0,
		"forced_role": Positions.Role.CB,
		"wage": 0,
		"movable": false,
		"can_hold_ball": false,
		"can_receive_pass": false,
		"bounces_ball": true,
	},
}

static func movable(special_type: String) -> bool:
	return DATA.get(special_type, {}).get("movable", true)

static func can_hold_ball(special_type: String) -> bool:
	return DATA.get(special_type, {}).get("can_hold_ball", true)

static func can_receive_pass(special_type: String) -> bool:
	return DATA.get(special_type, {}).get("can_receive_pass", true)

static func bounces_ball(special_type: String) -> bool:
	return DATA.get(special_type, {}).get("bounces_ball", false)
