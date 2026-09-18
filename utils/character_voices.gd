class_name CharacterVoices

## Per-speaker base pitch for the gibberish "talk" sound DialogueBox plays
## while a line types out. Add an entry here for any speaker who needs a
## pitch different from the default; unlisted speakers use DEFAULT_PITCH.

const DEFAULT_PITCH := 1.0

const _PITCH_BY_SPEAKER := {
	"Grandi Tapir": 0.85,
	"Pepito Perinola": 0.6,
}

static func pitch_for(speaker_name: String) -> float:
	return _PITCH_BY_SPEAKER.get(speaker_name, DEFAULT_PITCH)
