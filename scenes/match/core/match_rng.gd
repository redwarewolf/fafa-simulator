## MatchRng — autoload. The single random source for anything that can change
## a match's outcome (tackle duels, fouls, shot placement, clearances,
## kickoff/taker picks, AI tick staggering, decision softmax).
##
## Purely cosmetic randomness (kick-sound pitch, crowd, referee looks) keeps
## using the global randf()/randi() on purpose: routing it through here would
## make a headless run (which skips audio/visual setup) consume a different
## number of draws than a windowed one, breaking seed reproducibility.
extends Node

var _rng := RandomNumberGenerator.new()
## The seed the current match was started with — logged by the batch harness
## so any interesting match can be replayed exactly.
var current_seed : int = 0

func _ready() -> void:
	seed_match(-1)

## [param match_seed] < 0 picks a fresh random seed (normal play); >= 0 is a
## reproducible run (batch harness / debugging).
func seed_match(match_seed: int) -> void:
	if match_seed < 0:
		var r := RandomNumberGenerator.new()
		r.randomize()
		match_seed = r.randi() & 0x7fffffff
	current_seed = match_seed
	_rng.seed = match_seed

func randf() -> float:
	return _rng.randf()

func randf_range(from: float, to: float) -> float:
	return _rng.randf_range(from, to)

func randi_range(from: int, to: int) -> int:
	return _rng.randi_range(from, to)

## Gaussian sample — used for perception/execution noise.
func randfn(mean: float = 0.0, deviation: float = 1.0) -> float:
	return _rng.randfn(mean, deviation)

## Deterministic replacement for Array.pick_random(). Returns null for an
## empty array.
func pick(items: Array) -> Variant:
	if items.is_empty():
		return null
	return items[_rng.randi_range(0, items.size() - 1)]
