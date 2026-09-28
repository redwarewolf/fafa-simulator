class_name Tuning
extends RefCounted

## Named, overridable tuning knobs for the v2 AI — so the batch harness can run
## variants side by side (`--param shot_followup=0,tackle_must_stop_geo=0`)
## without editing code between runs, and parameter sweeps (Phase 10) become
## a command line instead of a rebuild. Code reads a knob with its default:
##     Tuning.f("shot_followup", 1.15)
## Normal play has no overrides, so every knob is exactly its default.

static var overrides := {}

static func f(key: String, default_value: float) -> float:
	return float(overrides.get(key, default_value))

static func b(key: String, default_value: bool) -> bool:
	return f(key, 1.0 if default_value else 0.0) != 0.0

## Parses "a=1,b=0.5" into overrides (replacing any previous ones).
static func set_from_string(spec: String) -> void:
	overrides.clear()
	for pair in spec.split(",", false):
		var kv := pair.split("=")
		if kv.size() == 2:
			overrides[kv[0].strip_edges()] = float(kv[1])
