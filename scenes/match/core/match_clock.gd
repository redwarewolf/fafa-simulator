## MatchClock — autoload. Simulation time for everything match-related.
##
## Replaces Time.get_ticks_msec() (wall-clock) across the match code. Wall
## time ignores Engine.time_scale, so at 8x the AI ticked every 1.6s of game
## time, a paused match kept "deciding", and a headless batch run (see
## tools/batch_match.gd) could never be deterministic. This accumulates the
## scaled frame delta instead: pausing (time_scale 0) freezes it, speeding up
## scales it, and under --fixed-fps every run advances identically.
##
## Registered as the first autoload with a very low process_priority so it
## ticks before any scene node reads it within the same frame.
extends Node

var _elapsed := 0.0

func _ready() -> void:
	process_priority = -1000

func _process(delta: float) -> void:
	_elapsed += delta

## Seconds of simulation time since the last reset().
func now() -> float:
	return _elapsed

## Milliseconds of simulation time since the last reset() — drop-in for the
## old Time.get_ticks_msec() call sites (all of which only ever compare
## differences, never absolute values).
func now_ms() -> int:
	return int(_elapsed * 1000.0)

## Called by MatchWorld when a match starts, so every match — and every
## batch-harness run with the same seed — begins from the same clock value
## (int-ms rounding of a running float would otherwise depend on how long the
## process had been alive).
func reset() -> void:
	_elapsed = 0.0
